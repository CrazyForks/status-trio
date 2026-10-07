import Combine
import Foundation

@MainActor
final class AppleDeviceDiscoveryController: ObservableObject {
    @Published private(set) var candidates: [AppleDeviceCandidate] = []
    @Published private(set) var isDiscovering = false
    @Published private(set) var discoveryGeneration: UInt64 = 0

    private let reader: any MobileBatteryReading
    private var claims: Set<String> = []
    private var isEnabled = false
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(reader: any MobileBatteryReading = MobileBatteryHelperReader()) {
        self.reader = reader
    }

    deinit {
        task?.cancel()
        refreshTask?.cancel()
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        if enabled {
            startDiscovery()
        } else {
            stopDiscovery(clearCandidates: true)
        }
    }

    func request(_ token: String) {
        guard !token.isEmpty else { return }
        let wasActive = isActive
        claims.insert(token)
        if !wasActive { updateLifecycle() }
    }

    func release(_ token: String) {
        guard claims.remove(token) != nil else { return }
        if claims.isEmpty && !isEnabled { stopDiscovery(clearCandidates: false) }
    }

    func refresh() {
        guard isActive else { return }
        startDiscovery()
    }

    func stop() {
        claims.removeAll()
        isEnabled = false
        stopDiscovery(clearCandidates: true)
    }

    private var isActive: Bool { isEnabled }

    private func updateLifecycle() {
        if isActive { startDiscovery() }
        else { stopDiscovery(clearCandidates: false) }
    }

    private func startDiscovery() {
        guard isActive else { return }
        refreshTask?.cancel()
        refreshTask = nil
        generation &+= 1
        let currentGeneration = generation
        discoveryGeneration = currentGeneration
        candidates = []
        task?.cancel()
        isDiscovering = true
        let reader = self.reader
        task = Task { [weak self, reader] in
            do {
                let candidates = try await reader.discover()
                guard !Task.isCancelled else { return }
                self?.finish(candidates, generation: currentGeneration)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finish([], generation: currentGeneration)
            }
        }
    }

    private func finish(_ values: [AppleDeviceCandidate], generation currentGeneration: UInt64) {
        guard generation == currentGeneration, isActive else { return }
        candidates = values.sorted { $0.id.rowID < $1.id.rowID }
        isDiscovering = false
        task = nil
        if isEnabled {
            scheduleRefresh()
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(60)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func stopDiscovery(clearCandidates: Bool) {
        generation &+= 1
        discoveryGeneration = generation
        task?.cancel()
        task = nil
        refreshTask?.cancel()
        refreshTask = nil
        isDiscovering = false
        if clearCandidates { candidates = [] }
    }
}
