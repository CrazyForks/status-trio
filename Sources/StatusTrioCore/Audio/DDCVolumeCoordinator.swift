import CoreAudio
import Foundation

struct DDCVolumeUpdate: Sendable {
    let outputID: AudioDeviceID
    let uid: String
    let generation: UInt64
    let scalar: Double?
}

/// Serializes all display discovery and I2C operations away from the main actor.
@MainActor
final class DDCVolumeCoordinator {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let worker: DDCWorker
    private let sleep: Sleep
    private let onUpdate: @MainActor (DDCVolumeUpdate) -> Void
    private let debounce: Duration
    private var outputID: AudioDeviceID?
    private var uid: String?
    private(set) var generation: UInt64 = 0
    private var detailsVisible = false
    private var displayAsleep = false
    private var stopped = false
    private var timerTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var pendingVolume: Double?
    private var failures = 0

    init(
        transport: DDCVolumeTransport = DDCDisplayTransport(),
        debounce: Duration = .milliseconds(150),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        onUpdate: @escaping @MainActor (DDCVolumeUpdate) -> Void
    ) {
        self.worker = DDCWorker(transport: transport)
        self.debounce = debounce
        self.sleep = sleep
        self.onUpdate = onUpdate
    }

    func select(outputID: AudioDeviceID, uid: String?) {
        guard !stopped else { return }
        generation &+= 1
        self.outputID = outputID
        self.uid = uid
        pendingVolume = nil
        debounceTask?.cancel()
        worker.setIdentity(outputID: outputID, uid: uid, generation: generation)
        timerTask?.cancel()
        guard let uid, !uid.isEmpty, !displayAsleep else { emit(nil); return }
        refresh()
    }

    func topologyChanged() {
        guard !stopped else { return }
        generation &+= 1
        pendingVolume = nil
        debounceTask?.cancel()
        worker.setIdentity(outputID: outputID, uid: uid, generation: generation)
        worker.invalidateTarget()
        timerTask?.cancel()
        guard uid != nil, !displayAsleep else { emit(nil); return }
        refresh()
    }

    func setDetailsVisible(_ visible: Bool) {
        guard !stopped, detailsVisible != visible else { return }
        detailsVisible = visible
        timerTask?.cancel()
        if outputID != nil, uid != nil, !displayAsleep { refresh() }
    }

    func setDisplayAsleep(_ asleep: Bool) {
        guard !stopped, displayAsleep != asleep else { return }
        displayAsleep = asleep
        timerTask?.cancel()
        if asleep { emit(nil) }
        else if outputID != nil, uid != nil { refresh() }
    }

    func setVolume(_ scalar: Double) {
        guard !stopped, !displayAsleep, uid != nil, scalar.isFinite else { return }
        pendingVolume = min(1, max(0, scalar))
        debounceTask?.cancel()
        let delay = debounce
        let sleep = self.sleep
        debounceTask = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flushPendingVolume()
        }
    }

    func flushPendingVolume() {
        guard !stopped, !displayAsleep, let scalar = pendingVolume,
              let outputID, let uid else { return }
        pendingVolume = nil
        debounceTask?.cancel()
        let token = generation
        worker.write(scalar: scalar, outputID: outputID, uid: uid, generation: token) { [weak self] succeeded in
            guard let self else { return }
            guard self.accepts(outputID: outputID, uid: uid, generation: token) else { return }
            if succeeded { self.refresh() }
            else { self.emit(nil); self.schedulePoll(after: self.nextFailureInterval()) }
        }
    }

    func refresh() {
        guard !stopped, !displayAsleep, let outputID, let uid, !uid.isEmpty else { return }
        timerTask?.cancel()
        let token = generation
        worker.read(outputID: outputID, uid: uid, generation: token) { [weak self] reply in
            guard let self, self.accepts(outputID: outputID, uid: uid, generation: token) else { return }
            if let reply {
                self.failures = 0
                self.onUpdate(DDCVolumeUpdate(outputID: outputID, uid: uid, generation: token, scalar: reply.scalar))
                self.schedulePoll(after: self.detailsVisible ? .seconds(2) : .seconds(10))
            } else {
                self.emit(nil)
                self.schedulePoll(after: self.nextFailureInterval())
            }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        generation &+= 1
        timerTask?.cancel()
        debounceTask?.cancel()
        pendingVolume = nil
        worker.setIdentity(outputID: nil, uid: nil, generation: generation)
    }

    private func nextFailureInterval() -> Duration {
        let intervals: [Duration] = [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60)]
        let result = intervals[min(failures, intervals.count - 1)]
        failures += 1
        return result
    }

    private func schedulePoll(after duration: Duration) {
        timerTask?.cancel()
        let sleep = self.sleep
        timerTask = Task { [weak self] in
            do { try await sleep(duration) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func accepts(outputID: AudioDeviceID, uid: String, generation: UInt64) -> Bool {
        !stopped && !displayAsleep && self.outputID == outputID && self.uid == uid && self.generation == generation
    }

    private func emit(_ scalar: Double?) {
        guard let outputID, let uid else { return }
        onUpdate(DDCVolumeUpdate(outputID: outputID, uid: uid, generation: generation, scalar: scalar))
    }
}

/// The transport and its non-Sendable target are only touched by this queue.
private final class DDCWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.status-trio.ddc-volume", qos: .utility)
    private let transport: DDCVolumeTransport
    private var target: DDCDisplayTarget?
    private var lastReply: DDCVolumeReply?
    private let identityLock = NSLock()
    private var currentOutputID: AudioDeviceID?
    private var currentUID: String?
    private var currentGeneration: UInt64 = 0

    init(transport: DDCVolumeTransport) { self.transport = transport }

    func setIdentity(outputID: AudioDeviceID?, uid: String?, generation: UInt64) {
        identityLock.lock()
        currentOutputID = outputID
        currentUID = uid
        currentGeneration = generation
        identityLock.unlock()
        queue.async { [self] in
            if target?.uid != uid { target = nil; lastReply = nil }
        }
    }

    func invalidateTarget() {
        queue.async { [self] in target = nil; lastReply = nil }
    }

    func read(outputID: AudioDeviceID, uid: String, generation: UInt64, completion: @escaping @MainActor (DDCVolumeReply?) -> Void) {
        queue.async { [self] in
            guard matches(outputID: outputID, uid: uid, generation: generation) else { return }
            if target?.uid != uid { target = transport.resolve(uid: uid) }
            let reply = target.flatMap { transport.read($0) }
            lastReply = reply
            Task { @MainActor in completion(reply) }
        }
    }

    func write(scalar: Double, outputID: AudioDeviceID, uid: String, generation: UInt64, completion: @escaping @MainActor (Bool) -> Void) {
        queue.async { [self] in
            guard matches(outputID: outputID, uid: uid, generation: generation) else { return }
            if target?.uid != uid { target = transport.resolve(uid: uid) }
            guard let target else {
                Task { @MainActor in completion(false) }
                return
            }
            let reply: DDCVolumeReply
            if let lastReply { reply = lastReply }
            else if let freshReply = transport.read(target) { reply = freshReply; lastReply = freshReply }
            else { Task { @MainActor in completion(false) }; return }
            guard matches(outputID: outputID, uid: uid, generation: generation) else { return }
            let result = transport.write(target, value: reply.targetValue(for: scalar))
            lastReply = nil
            Task { @MainActor in completion(result) }
        }
    }

    private func matches(outputID: AudioDeviceID, uid: String, generation: UInt64) -> Bool {
        identityLock.lock(); defer { identityLock.unlock() }
        return currentOutputID == outputID && currentUID == uid && currentGeneration == generation
    }
}
