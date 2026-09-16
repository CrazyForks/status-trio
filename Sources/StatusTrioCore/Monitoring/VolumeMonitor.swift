import CoreAudio
import Foundation
import os

private let volumeMonitorLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "VolumeMonitor"
)

struct VolumeReading: Equatable, Sendable {
    let scalar: Double?
    let isMuted: Bool
    let deviceName: String?
}

protocol VolumeReadingProviding: AnyObject {
    func read() -> VolumeReading?
}

protocol CoreAudioClient: AnyObject {
    func defaultOutputDevice() -> AudioDeviceID?
    func deviceClass(of deviceID: AudioDeviceID) -> AudioClassID?
    func isDeviceAlive(_ deviceID: AudioDeviceID) -> Bool

    func readUInt32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> UInt32?

    func readFloat32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Float32?

    func readString(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> String?

    func hasProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool

    func addListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue?,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus

    func removeListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue?,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus
}

extension CoreAudioClient {
    func validDefaultOutputDevice() -> AudioDeviceID? {
        guard
            let deviceID = defaultOutputDevice(),
            deviceID != kAudioObjectUnknown,
            deviceClass(of: deviceID) == kAudioDeviceClassID,
            isDeviceAlive(deviceID)
        else { return nil }

        return deviceID
    }
}

final class CoreAudioSystemClient: CoreAudioClient {
    func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard
            status == noErr,
            size == MemoryLayout<AudioDeviceID>.size,
            deviceID != kAudioObjectUnknown
        else { return nil }
        return deviceID
    }

    func deviceClass(of deviceID: AudioDeviceID) -> AudioClassID? {
        readUInt32(
            objectID: deviceID,
            selector: kAudioObjectPropertyClass,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain
        )
    }

    func isDeviceAlive(_ deviceID: AudioDeviceID) -> Bool {
        readUInt32(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceIsAlive,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain
        ) == 1
    }

    func readUInt32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> UInt32? {
        readScalar(
            objectID: objectID,
            selector: selector,
            scope: scope,
            element: element,
            defaultValue: UInt32(0)
        )
    }

    func readFloat32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Float32? {
        readScalar(
            objectID: objectID,
            selector: selector,
            scope: scope,
            element: element,
            defaultValue: Float32(0)
        )
    }

    func readString(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &name
        )

        guard
            status == noErr,
            size == MemoryLayout<Unmanaged<CFString>?>.size,
            let name
        else { return nil }

        let value = name.takeRetainedValue() as String
        return value.isEmpty ? nil : value
    }

    func hasProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        return AudioObjectHasProperty(objectID, &address)
    }

    func addListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue?,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        var mutableAddress = address
        return AudioObjectAddPropertyListenerBlock(
            objectID,
            &mutableAddress,
            queue,
            block
        )
    }

    func removeListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue?,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        var mutableAddress = address
        return AudioObjectRemovePropertyListenerBlock(
            objectID,
            &mutableAddress,
            queue,
            block
        )
    }

    private func readScalar<Value>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        defaultValue: Value
    ) -> Value? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        var value = defaultValue
        var size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                UnsafeMutableRawPointer(pointer)
            )
        }

        guard status == noErr, size == MemoryLayout<Value>.size else {
            return nil
        }
        return value
    }
}

final class CoreAudioVolumeReader: VolumeReadingProviding {
    static let outputElements: [AudioObjectPropertyElement] = [
        kAudioObjectPropertyElementMain,
        1,
        2
    ]

    private let client: any CoreAudioClient

    init(client: any CoreAudioClient = CoreAudioSystemClient()) {
        self.client = client
    }

    func read() -> VolumeReading? {
        guard let deviceID = defaultOutputDevice() else { return nil }

        return VolumeReading(
            scalar: volumeScalar(for: deviceID).map(Double.init),
            isMuted: isMuted(for: deviceID),
            deviceName: deviceName(for: deviceID)
        )
    }

    func defaultOutputDevice() -> AudioDeviceID? {
        client.validDefaultOutputDevice()
    }

    static func firstValue<Value>(
        from elements: [AudioObjectPropertyElement] = outputElements,
        using read: (AudioObjectPropertyElement) -> Value?
    ) -> Value? {
        for element in elements {
            if let value = read(element) {
                return value
            }
        }
        return nil
    }

    static func isMuted(
        using read: (AudioObjectPropertyElement) -> UInt32?
    ) -> Bool {
        firstValue(using: read) == 1
    }

    private func volumeScalar(for deviceID: AudioDeviceID) -> Float32? {
        Self.firstValue { element in
            client.readFloat32(
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            )
        }
    }

    private func isMuted(for deviceID: AudioDeviceID) -> Bool {
        Self.isMuted { element in
            client.readUInt32(
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            )
        }
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        client.readString(
            objectID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain
        )
    }
}

@MainActor
protocol VolumeEventMonitoring: AnyObject {
    func start(
        onDefaultDeviceChange: @escaping @MainActor @Sendable () -> Void,
        onVolumeChange: @escaping @MainActor @Sendable () -> Void
    )
    func reconcile()
    func recover()
    func stop()
}

@MainActor
final class CoreAudioVolumeEventMonitor: VolumeEventMonitoring {
    private struct DeviceListenerKey: Hashable {
        let selector: AudioObjectPropertySelector
        let element: AudioObjectPropertyElement
    }

    private struct ListenerRegistration {
        let key: DeviceListenerKey
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let queue: DispatchQueue?
        let block: AudioObjectPropertyListenerBlock
    }

    nonisolated(unsafe) private let client: any CoreAudioClient
    private let callbackQueue: DispatchQueue?
    nonisolated(unsafe) private var defaultDeviceRegistration: ListenerRegistration?
    nonisolated(unsafe) private var deviceRegistrations: [ListenerRegistration] = []
    private var registeredDeviceID: AudioDeviceID?
    private var deviceNeedsReconciliation = true
    private var onDefaultDeviceChange: (@MainActor @Sendable () -> Void)?
    private var onVolumeChange: (@MainActor @Sendable () -> Void)?
    private var isStarted = false
    private var isStopped = false

    init(
        client: any CoreAudioClient = CoreAudioSystemClient(),
        callbackQueue: DispatchQueue? = .main
    ) {
        self.client = client
        self.callbackQueue = callbackQueue
    }

    deinit {
        if let defaultDeviceRegistration {
            Self.unregister(defaultDeviceRegistration, client: client)
        }
        for registration in deviceRegistrations {
            Self.unregister(registration, client: client)
        }
    }

    func start(
        onDefaultDeviceChange: @escaping @MainActor @Sendable () -> Void,
        onVolumeChange: @escaping @MainActor @Sendable () -> Void
    ) {
        guard !isStarted, !isStopped else { return }
        isStarted = true
        self.onDefaultDeviceChange = onDefaultDeviceChange
        self.onVolumeChange = onVolumeChange
        deviceNeedsReconciliation = true
        reconcile()
    }

    func reconcile() {
        guard isStarted, !isStopped else { return }

        reconcileDefaultDeviceListener()

        let currentDeviceID = client.validDefaultOutputDevice()
        if deviceNeedsReconciliation || currentDeviceID != registeredDeviceID {
            removeDeviceListeners()
            registeredDeviceID = currentDeviceID
            deviceNeedsReconciliation = false
        }

        guard let currentDeviceID else { return }
        reconcileDeviceListeners(for: currentDeviceID)
    }

    func recover() {
        guard isStarted, !isStopped else { return }

        removeAllListeners()
        registeredDeviceID = nil
        deviceNeedsReconciliation = true
        reconcile()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        removeAllListeners()
        registeredDeviceID = nil
        deviceNeedsReconciliation = true
        onDefaultDeviceChange = nil
        onVolumeChange = nil
    }

    private func reconcileDefaultDeviceListener() {
        guard defaultDeviceRegistration == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.defaultDeviceDidChange()
            }
        }
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        defaultDeviceRegistration = addDefaultDeviceListener(
            address: address,
            block: block
        )
    }

    private func reconcileDeviceListeners(for deviceID: AudioDeviceID) {
        let volumeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.volumeDidChange()
            }
        }
        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.volumeDidChange()
            }
        }

        for element in CoreAudioVolumeReader.outputElements {
            reconcileDeviceListener(
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                element: element,
                block: volumeBlock
            )
            reconcileDeviceListener(
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                element: element,
                block: muteBlock
            )
        }
    }

    private func reconcileDeviceListener(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        let key = DeviceListenerKey(selector: selector, element: element)
        guard !deviceRegistrations.contains(where: { $0.key == key }) else {
            return
        }

        let address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
        guard client.hasProperty(
            objectID: objectID,
            selector: selector,
            scope: kAudioObjectPropertyScopeOutput,
            element: element
        ) else { return }

        guard let registration = addDeviceListener(
            key: key,
            objectID: objectID,
            address: address,
            block: block
        ) else { return }
        deviceRegistrations.append(registration)
    }

    private func defaultDeviceDidChange() {
        guard isStarted, !isStopped else { return }
        deviceNeedsReconciliation = true
        reconcile()
        onDefaultDeviceChange?()
    }

    private func volumeDidChange() {
        guard isStarted, !isStopped else { return }
        onVolumeChange?()
    }

    private func addDefaultDeviceListener(
        address: AudioObjectPropertyAddress,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> ListenerRegistration? {
        let objectID = AudioObjectID(kAudioObjectSystemObject)
        let status = client.addListener(
            objectID: objectID,
            address: address,
            queue: callbackQueue,
            block: block
        )
        if status != noErr {
            volumeMonitorLogger.error(
                "Failed to add CoreAudio default-device listener for selector \(address.mSelector, privacy: .public), element \(address.mElement, privacy: .public): OSStatus \(status, privacy: .public)"
            )
            return nil
        }

        return ListenerRegistration(
            key: DeviceListenerKey(selector: address.mSelector, element: address.mElement),
            objectID: objectID,
            address: address,
            queue: callbackQueue,
            block: block
        )
    }

    private func addDeviceListener(
        key: DeviceListenerKey,
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> ListenerRegistration? {
        let status = client.addListener(
            objectID: objectID,
            address: address,
            queue: callbackQueue,
            block: block
        )
        if status != noErr {
            volumeMonitorLogger.error(
                "Failed to add CoreAudio listener for selector \(address.mSelector, privacy: .public), element \(address.mElement, privacy: .public): OSStatus \(status, privacy: .public)"
            )
            return nil
        }

        return ListenerRegistration(
            key: key,
            objectID: objectID,
            address: address,
            queue: callbackQueue,
            block: block
        )
    }

    private func removeAllListeners() {
        if let defaultDeviceRegistration {
            removeListener(defaultDeviceRegistration)
            self.defaultDeviceRegistration = nil
        }
        removeDeviceListeners()
    }

    private func removeDeviceListeners() {
        for registration in deviceRegistrations {
            removeListener(registration)
        }
        deviceRegistrations.removeAll()
    }

    private func removeListener(_ registration: ListenerRegistration) {
        Self.unregister(registration, client: client)
    }

    nonisolated private static func unregister(
        _ registration: ListenerRegistration,
        client: any CoreAudioClient
    ) {
        let status = client.removeListener(
            objectID: registration.objectID,
            address: registration.address,
            queue: registration.queue,
            block: registration.block
        )
        if status != noErr {
            volumeMonitorLogger.error(
                "Failed to remove CoreAudio listener for selector \(registration.address.mSelector, privacy: .public), element \(registration.address.mElement, privacy: .public): OSStatus \(status, privacy: .public)"
            )
        }
    }
}

@MainActor
final class VolumeMonitor: VolumeMonitoring, VolumeControlling {
    private enum Lifecycle {
        case idle
        case running
        case stopped
    }

    let updates: AsyncStream<VolumeStatus>
    private let continuation: AsyncStream<VolumeStatus>.Continuation
    private let reader: any VolumeReadingProviding
    private let eventMonitor: any VolumeEventMonitoring
    private let outputController: (any AudioOutputControlling)?
    private let refreshDebounceInterval: Duration
    private let refreshDebounceSleep: @Sendable (Duration) async throws -> Void
    private var scheduledRefreshTask: Task<Void, Never>?
    private var scheduledRefreshIncludesOutputDevices = false
    private var cachedOutputDevices: [AudioOutputDevice] = []
    private var outputDevicesCacheValid = false
    private var detailsVisible = true
    private var lifecycle = Lifecycle.idle

    init(
        reader: any VolumeReadingProviding = CoreAudioVolumeReader(),
        eventMonitor: any VolumeEventMonitoring = CoreAudioVolumeEventMonitor(),
        outputController: (any AudioOutputControlling)? = nil,
        refreshDebounceInterval: Duration = .milliseconds(150),
        refreshDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.reader = reader
        self.eventMonitor = eventMonitor
        self.outputController = outputController
        self.refreshDebounceInterval = refreshDebounceInterval
        self.refreshDebounceSleep = refreshDebounceSleep
        (updates, continuation) = MonitorStream.make(of: VolumeStatus.self)
    }

    deinit {
        MainActor.assumeIsolated {
            scheduledRefreshTask?.cancel()
            if lifecycle != .stopped {
                eventMonitor.stop()
            }
        }
        continuation.finish()
    }

    func start() {
        guard lifecycle == .idle else { return }
        lifecycle = .running

        eventMonitor.start(
            onDefaultDeviceChange: { [weak self] in
                self?.scheduleRefresh(includeOutputDevices: true)
            },
            onVolumeChange: { [weak self] in
                self?.scheduleRefresh()
            }
        )
        refresh()
    }

    func stop() {
        guard lifecycle != .stopped else { return }
        lifecycle = .stopped
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = nil
        scheduledRefreshIncludesOutputDevices = false
        teardown()
    }

    func recover() {
        guard lifecycle == .running else { return }
        eventMonitor.recover()
    }

    func setDetailsVisible(_ visible: Bool) {
        guard lifecycle != .stopped else { return }
        let changed = detailsVisible != visible
        detailsVisible = visible
        outputDevicesCacheValid = false

        if !visible {
            cachedOutputDevices = []
            outputDevicesCacheValid = true
        }

        if changed, !visible, lifecycle == .running {
            performRefresh(includeOutputDevices: false)
        }
    }

    func refresh() {
        performRefresh(includeOutputDevices: detailsVisible)
    }

    func setVolume(_ scalar: Double) {
        guard lifecycle != .stopped else { return }
        _ = outputController?.setVolume(scalar)
        scheduleRefresh()
    }

    func toggleMute() {
        guard lifecycle != .stopped else { return }
        _ = outputController?.toggleMute()
        scheduleRefresh()
    }

    func selectOutputDevice(_ deviceID: AudioDeviceID) {
        guard lifecycle != .stopped else { return }
        _ = outputController?.selectOutputDevice(deviceID)
        scheduleRefresh(includeOutputDevices: true)
    }

    private func scheduleRefresh(includeOutputDevices: Bool = false) {
        guard lifecycle == .running else { return }
        scheduledRefreshIncludesOutputDevices = scheduledRefreshIncludesOutputDevices || includeOutputDevices
        guard scheduledRefreshTask == nil else { return }

        let interval = refreshDebounceInterval
        let sleep = refreshDebounceSleep
        scheduledRefreshTask = Task { @MainActor [weak self] in
            do {
                try await sleep(interval)
            } catch {
                self?.scheduledRefreshTask = nil
                self?.scheduledRefreshIncludesOutputDevices = false
                return
            }

            guard !Task.isCancelled, let self, self.lifecycle == .running else {
                self?.scheduledRefreshTask = nil
                self?.scheduledRefreshIncludesOutputDevices = false
                return
            }

            let includeOutputDevices = self.scheduledRefreshIncludesOutputDevices
            self.scheduledRefreshTask = nil
            self.scheduledRefreshIncludesOutputDevices = false
            self.performRefresh(includeOutputDevices: includeOutputDevices)
        }
    }

    private func performRefresh(includeOutputDevices: Bool) {
        guard lifecycle != .stopped else { return }

        eventMonitor.reconcile()
        let status: VolumeStatus
        if let reading = reader.read() {
            let devices: [AudioOutputDevice]
            if !detailsVisible {
                cachedOutputDevices = []
                outputDevicesCacheValid = true
                devices = []
            } else if includeOutputDevices || !outputDevicesCacheValid {
                cachedOutputDevices = outputController?.outputDevices() ?? []
                outputDevicesCacheValid = true
                devices = cachedOutputDevices
            } else {
                devices = cachedOutputDevices
            }

            status = VolumeStatus(
                scalar: reading.scalar,
                isMuted: reading.isMuted,
                deviceName: reading.deviceName,
                outputDevices: devices
            )
        } else {
            status = .placeholder
        }
        continuation.yield(status)
    }

    private func teardown() {
        eventMonitor.stop()
        continuation.finish()
    }
}
