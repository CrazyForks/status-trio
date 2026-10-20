import CoreFoundation
import Foundation
import IOBluetooth

/// IOBluetooth-backed HUAWEI SPP transport.
///
/// Opens channels and serializes blocking exchanges on a dedicated run-loop
/// thread, leaving the main run loop free for UI and IOBluetooth callbacks.
/// Callbacks may arrive on the main thread even when the channel was opened on
/// the transport thread; the delegate synchronizes its receive state separately.
///
/// `@unchecked Sendable` is safe because connection ownership is confined to the
/// transport thread. The transport lock guards run-loop and queue state, while
/// each delegate lock guards its receive buffer, decoded frames, and open status.
final class HuaweiRFCOMMTransport: HuaweiListeningModeTransporting, @unchecked Sendable {
    private final class Delegate: NSObject, IOBluetoothRFCOMMChannelDelegate {
        // IOBluetooth can deliver data on the main thread even when the channel
        // was opened by the transport thread. Never expose mutable buffers to
        // exchange(); reset and dequeue operations must be atomic with callbacks.
        private let lock = NSLock()
        private var buffer: [UInt8] = []
        private var frames: [HuaweiSPPFrame] = []
        private var status: IOReturn?

        var openStatus: IOReturn? {
            lock.lock()
            defer { lock.unlock() }
            return status
        }

        func resetReplies() {
            lock.lock()
            defer { lock.unlock() }
            frames.removeAll(keepingCapacity: true)
            buffer.removeAll(keepingCapacity: true)
        }

        func takeFrame(command: [UInt8]) -> HuaweiSPPFrame? {
            lock.lock()
            defer { lock.unlock() }
            guard let index = frames.firstIndex(where: { $0.command == command }) else { return nil }
            return frames.remove(at: index)
        }

        func rfcommChannelOpenComplete(
            _ rfcommChannel: IOBluetoothRFCOMMChannel!,
            status error: IOReturn
        ) {
            lock.lock()
            defer { lock.unlock() }
            status = error
        }

        func rfcommChannelData(
            _ rfcommChannel: IOBluetoothRFCOMMChannel!,
            data dataPointer: UnsafeMutableRawPointer!,
            length dataLength: Int
        ) {
            guard let dataPointer, dataLength > 0 else { return }
            lock.lock()
            defer { lock.unlock() }
            buffer.append(contentsOf: UnsafeBufferPointer(
                start: dataPointer.assumingMemoryBound(to: UInt8.self),
                count: dataLength
            ))
            while buffer.count >= 4 {
                guard buffer[0] == HuaweiSPPFrame.magic else {
                    buffer.removeFirst()
                    continue
                }
                let frameLength = 4 + (Int(buffer[1]) << 8 | Int(buffer[2])) + 1
                guard frameLength <= 4096 else {
                    buffer.removeFirst()
                    continue
                }
                guard buffer.count >= frameLength else { break }
                if let frame = HuaweiSPPFrame.decode(Array(buffer[0..<frameLength])) {
                    frames.append(frame)
                }
                buffer.removeFirst(frameLength)
            }
        }

        func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
            lock.lock()
            defer { lock.unlock() }
            status = kIOReturnNotOpen
        }
    }

    private final class Connection {
        let device: IOBluetoothDevice
        let channel: IOBluetoothRFCOMMChannel
        let delegate: Delegate

        init(device: IOBluetoothDevice, channel: IOBluetoothRFCOMMChannel, delegate: Delegate) {
            self.device = device
            self.channel = channel
            self.delegate = delegate
        }
    }

    private let lock = NSLock()
    /// Serializes the first-use startup of the transport thread.
    ///
    /// `transportRunLoop` is published by the new thread itself, so two callers
    /// that both observe `nil` would both create and start a thread. `state` and
    /// `setMode` are nonisolated `async` methods, so they run on the cooperative
    /// pool: two HUAWEI devices read at once really do reach `ensureRunLoop`
    /// concurrently. Two threads would break the "all access to `connections`
    /// happens on the transport thread" invariant this class documents, and the
    /// losing thread would run forever.
    private let startupLock = NSLock()
    private var transportThread: Thread?
    private var transportRunLoop: CFRunLoop?
    private var pending: [@Sendable () -> Void] = []
    private var isProcessing = false
    private var keepAlivePort: Port?
    private var startedThreadCount = 0

    /// How many transport threads this instance has started.
    ///
    /// One instance owns one thread. A second one would mean the first-use
    /// startup was not serialized, and the connection map would end up with two
    /// owners — the invariant this class documents.
    var transportThreadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return startedThreadCount
    }

    /// All access to `connections` happens on the transport thread.
    private var connections: [String: Connection] = [:]

    func state(address: String) async throws -> HuaweiNoiseState {
        try await perform { try self.readState(address: address) }
    }

    func setMode(_ mode: HuaweiNoiseMode, address: String) async throws -> HuaweiNoiseState {
        try await perform { try self.writeMode(mode, address: address) }
    }

    func closeAll() {
        lock.lock()
        let started = transportRunLoop != nil
        lock.unlock()
        guard started else { return }
        enqueue { self.closeAllOnTransportThread() }
    }

    // MARK: - Async → transport thread

    private func perform<T: Sendable>(
        _ body: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            enqueue {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func enqueue(_ block: @escaping @Sendable () -> Void) {
        let runLoop = ensureRunLoop()
        lock.lock()
        pending.append(block)
        let shouldSchedule = !isProcessing
        if shouldSchedule { isProcessing = true }
        lock.unlock()
        if shouldSchedule {
            CFRunLoopPerformBlock(runLoop, "kCFRunLoopCommonModes" as CFString) { [weak self] in
                self?.drain()
            }
            CFRunLoopWakeUp(runLoop)
        }
    }

    /// Runs one queued operation. A request pumps a nested run loop while it
    /// waits for the reply, so the drain block must not be rescheduled until the
    /// operation returns; otherwise a second request would run re-entrantly.
    private func drain() {
        lock.lock()
        guard !pending.isEmpty else {
            isProcessing = false
            lock.unlock()
            return
        }
        let block = pending.removeFirst()
        lock.unlock()

        block()

        lock.lock()
        let hasMore = !pending.isEmpty
        if !hasMore { isProcessing = false }
        lock.unlock()
        if hasMore, let runLoop = transportRunLoop {
            CFRunLoopPerformBlock(runLoop, "kCFRunLoopCommonModes" as CFString) { [weak self] in
                self?.drain()
            }
            CFRunLoopWakeUp(runLoop)
        }
    }

    /// Returns the transport's run loop, starting the transport thread on first
    /// use.
    ///
    /// The whole body is serialized by `startupLock`: the run loop is published
    /// by the new thread, so without it two concurrent callers would each start
    /// a thread and the transport would own two.
    private func ensureRunLoop() -> CFRunLoop {
        startupLock.lock()
        defer { startupLock.unlock() }

        lock.lock()
        if let runLoop = transportRunLoop {
            lock.unlock()
            return runLoop
        }
        lock.unlock()

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else { return }
            let runLoop = CFRunLoopGetCurrent()
            self.lock.lock()
            self.transportRunLoop = runLoop
            self.lock.unlock()
            ready.signal()
            // A run loop with no sources returns immediately; the keep-alive port
            // makes the idle wait real and keeps `CFRunLoopPerformBlock` delivery
            // from turning into a spin.
            self.keepAlivePort = Port()
            RunLoop.current.add(self.keepAlivePort!, forMode: .default)
            while true {
                RunLoop.current.run(mode: .default, before: .distantFuture)
            }
        }
        thread.name = "StatusTrio.HuaweiRFCOMM"
        thread.qualityOfService = .userInitiated

        lock.lock()
        transportThread = thread
        startedThreadCount += 1
        lock.unlock()

        thread.start()
        ready.wait()
        lock.lock()
        let runLoop = transportRunLoop ?? CFRunLoopGetMain()!
        lock.unlock()
        return runLoop
    }

    // MARK: - Transport-thread operations

    private func readState(address: String) throws -> HuaweiNoiseState {
        let connection = try connection(for: address)
        let response = try exchange(
            connection,
            frame: HuaweiSPPFrame(
                command: HuaweiSPPFrame.readANCCommand,
                parameters: [1: [], 2: []]
            ),
            expecting: HuaweiSPPFrame.readANCCommand
        )
        guard let value = response.parameters[1], value.count >= 2,
              let state = HuaweiNoiseState(level: value[0], mode: value[1]) else {
            throw HuaweiListeningModeError.malformedResponse
        }
        return state
    }

    private func writeMode(_ mode: HuaweiNoiseMode, address: String) throws -> HuaweiNoiseState {
        let connection = try connection(for: address)
        do {
            let acknowledgement = try exchange(
                connection,
                frame: HuaweiSPPFrame(
                    command: HuaweiSPPFrame.writeANCCommand,
                    parameters: [1: mode.writePayload]
                ),
                expecting: HuaweiSPPFrame.writeANCCommand,
                timeout: 1.5
            )
            if let status = acknowledgement.parameters[2]?.first, status != 0 {
                throw HuaweiListeningModeError.rejected(status)
            }
        } catch HuaweiListeningModeError.timeout {
            // Some firmware applies the mode without an ACK. The read-back below
            // is the authority; a missing ACK alone is not a failed write.
        }
        return try readState(address: address)
    }

    private func connection(for address: String) throws -> Connection {
        let key = BluetoothBatteryReader.normalizedAddress(address)
        guard !key.isEmpty else { throw HuaweiListeningModeError.deviceUnavailable }

        if let connection = connections[key], connection.channel.isOpen() {
            return connection
        }
        if let stale = connections.removeValue(forKey: key) {
            stale.channel.close()
        }

        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        guard let device = devices.first(where: {
            BluetoothBatteryReader.normalizedAddress($0.addressString ?? "") == key
        }) else {
            throw HuaweiListeningModeError.deviceUnavailable
        }

        if !device.isConnected() {
            let status = device.openConnection()
            guard status == kIOReturnSuccess else {
                throw HuaweiListeningModeError.connectionFailed(status)
            }
            guard waitUntil(timeout: 5, { device.isConnected() }) else {
                throw HuaweiListeningModeError.timeout
            }
        }

        _ = device.performSDPQuery(nil)
        // `performSDPQuery` is asynchronous even though it returns a status. The
        // cached service list can already contain SPP, so waiting for the service
        // to appear is not enough; give the query a fixed window before opening,
        // the same sequence that works from PyObjC.
        pump(1.0)
        _ = waitUntil(timeout: 1.0) { self.sppChannel(for: device) != nil }
        // A resolved SDP record is authoritative. Without one, try the two channel
        // numbers the FreeBuds family uses (6i uses 1, 4i/5i use 16).
        let resolvedChannel = sppChannel(for: device)
        let candidates: [BluetoothRFCOMMChannelID] = resolvedChannel.map { [$0] } ?? [1, 16]

        var opened: (channel: IOBluetoothRFCOMMChannel, delegate: Delegate)?
        var lastStatus: IOReturn = kIOReturnError
        for channelID in candidates {
            let delegate = Delegate()
            var channel: IOBluetoothRFCOMMChannel?
            let status = device.openRFCOMMChannelSync(
                &channel,
                withChannelID: BluetoothRFCOMMChannelID(channelID),
                delegate: delegate
            )
            lastStatus = status
            guard status == kIOReturnSuccess, let channel else {
                channel?.close()
                continue
            }
            _ = waitUntil(timeout: 2) { delegate.openStatus != nil }
            if let openStatus = delegate.openStatus, openStatus != kIOReturnSuccess {
                lastStatus = openStatus
                channel.close()
                continue
            }
            guard channel.isOpen() else {
                lastStatus = kIOReturnNotOpen
                channel.close()
                continue
            }
            opened = (channel, delegate)
            break
        }
        guard let opened else {
            throw HuaweiListeningModeError.channelOpenFailed(lastStatus)
        }

        let connection = Connection(
            device: device,
            channel: opened.channel,
            delegate: opened.delegate
        )
        connections[key] = connection
        return connection
    }

    private func exchange(
        _ connection: Connection,
        frame: HuaweiSPPFrame,
        expecting command: [UInt8],
        timeout: TimeInterval = 3
    ) throws -> HuaweiSPPFrame {
        guard connection.channel.isOpen() else { throw HuaweiListeningModeError.notOpen }
        connection.delegate.resetReplies()

        let packet = frame.encoded()
        let status = packet.withUnsafeBytes { bytes -> IOReturn in
            guard let baseAddress = bytes.baseAddress else { return kIOReturnError }
            return connection.channel.writeSync(
                UnsafeMutableRawPointer(mutating: baseAddress),
                length: UInt16(packet.count)
            )
        }
        guard status == kIOReturnSuccess else {
            throw HuaweiListeningModeError.writeFailed(status)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let response = connection.delegate.takeFrame(command: command) {
                return response
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        throw HuaweiListeningModeError.timeout
    }

    private func closeAllOnTransportThread() {
        for connection in connections.values {
            connection.channel.close()
        }
        connections.removeAll()
    }

    private func pump(_ duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private func sppChannel(for device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        for item in device.services ?? [] {
            guard let record = item as? IOBluetoothSDPServiceRecord,
                  record.matchesUUID16(0x1101) else {
                continue
            }
            var channel: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&channel) == kIOReturnSuccess {
                return channel
            }
        }
        return nil
    }
}
