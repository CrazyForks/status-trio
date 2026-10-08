import Combine
import Foundation

@MainActor
final class MobileBatteryController: ObservableObject {
    private static let refreshInterval: Duration = .seconds(60)
    private static let cacheLifetime: TimeInterval = 1_200

    @Published private(set) var snapshots: [MobileBatterySnapshot] = []
    @Published private(set) var failures: [MobileBatteryReadFailure] = []
    @Published private(set) var isRefreshing = false

    private let reader: any MobileBatteryReading
    private let clock: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var claims: Set<String> = []
    private var authorizedDeviceIDs: Set<AppleDeviceID> = []
    private var backgroundAuthorizedDeviceIDs: Set<AppleDeviceID> = []
    private var isSurfaceVisible = false
    private var isReadingEnabled = true
    private var isBackgroundRefreshEnabled = false
    private var backgroundRefreshInterval: Duration = .seconds(60)
    private var isStopped = false
    private var generation: UInt64 = 0
    private var readTask: Task<Void, Never>?
    private var activeReadIDs: Set<AppleDeviceID> = []
    private var refreshTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?

    init(
        reader: any MobileBatteryReading = MobileBatteryHelperReader(),
        clock: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.reader = reader
        self.clock = clock
        self.sleep = sleep
    }

    deinit {
        readTask?.cancel()
        refreshTask?.cancel()
        expiryTask?.cancel()
    }

    func request(_ token: String) {
        guard !isStopped, !token.isEmpty else { return }
        let wasEnabled = isEnabled
        claims.insert(token)
        if !wasEnabled { updateLifecycle() }
    }

    func release(_ token: String, keepingResults: Bool = false) {
        guard !isStopped, claims.remove(token) != nil else { return }
        if claims.isEmpty {
            updateLifecycle()
            if !keepingResults && !isBackgroundRefreshEnabled {
                snapshots = []
                failures = []
            }
        }
    }

    func setSurfaceVisible(_ visible: Bool) {
        guard !isStopped, isSurfaceVisible != visible else { return }
        isSurfaceVisible = visible
        updateLifecycle()
    }

    func setAuthorizedDeviceIDs(_ ids: Set<AppleDeviceID>) {
        guard !isStopped, authorizedDeviceIDs != ids else { return }
        let wasEnabled = isEnabled
        authorizedDeviceIDs = ids
        failures.removeAll { failure in
            guard let deviceID = failure.deviceID else { return true }
            return !ids.contains { id in id.matchesHelperIdentifier(deviceID) }
        }
        if wasEnabled || isEnabled { updateLifecycle() }
    }

    func setBackgroundAuthorizedDeviceIDs(_ ids: Set<AppleDeviceID>) {
        guard !isStopped, backgroundAuthorizedDeviceIDs != ids else { return }
        backgroundAuthorizedDeviceIDs = ids
        updateLifecycle()
    }

    func revokeDeviceIDs(_ ids: Set<AppleDeviceID>) {
        guard !isStopped, !ids.isEmpty else { return }
        let identities = Set(ids.map(\.readIdentity))
        snapshots.removeAll { identities.contains($0.identity) }
        failures.removeAll { failure in
            guard let deviceID = failure.deviceID else { return false }
            return ids.contains { $0.matchesHelperIdentifier(deviceID) }
        }
        authorizedDeviceIDs.subtract(ids)
        backgroundAuthorizedDeviceIDs.subtract(ids)
        updateLifecycle()
    }

    /// Gates the controller from central settings so disabling the opt-in also
    /// clears cached results when the Bluetooth view is not mounted. Re-enabling
    /// only resumes work when a visible surface still owns a claim.
    func setReadingEnabled(_ enabled: Bool) {
        guard !isStopped, isReadingEnabled != enabled else { return }
        isReadingEnabled = enabled
        guard enabled else {
            cancelActiveWork()
            expiryTask?.cancel()
            expiryTask = nil
            snapshots = []
            failures = []
            return
        }
        updateLifecycle()
    }

    func setBackgroundRefresh(enabled: Bool, interval: Duration) {
        guard !isStopped else { return }
        let interval = interval < .seconds(60) ? .seconds(60) : interval
        guard isBackgroundRefreshEnabled != enabled || backgroundRefreshInterval != interval else { return }
        isBackgroundRefreshEnabled = enabled
        backgroundRefreshInterval = interval
        updateLifecycle()
    }

    func refresh() {
        guard !isStopped, isEnabled else { return }
        beginRead(superseding: true)
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        claims.removeAll()
        authorizedDeviceIDs.removeAll()
        isSurfaceVisible = false
        cancelActiveWork()
        expiryTask?.cancel()
        expiryTask = nil
        snapshots = []
        failures = []
        isRefreshing = false
    }

    private var isEnabled: Bool { isReadingEnabled && isSurfaceVisible && !claims.isEmpty && !authorizedDeviceIDs.isEmpty }

    private var hasReadDemand: Bool {
        isReadingEnabled && !effectiveReadIDs.isEmpty
            && ((isSurfaceVisible && !claims.isEmpty) || isBackgroundRefreshEnabled)
    }

    private var effectiveReadIDs: Set<AppleDeviceID> {
        isBackgroundRefreshEnabled
            ? authorizedDeviceIDs.union(backgroundAuthorizedDeviceIDs)
            : authorizedDeviceIDs
    }

    var backgroundReadDeviceIDs: Set<AppleDeviceID> {
        backgroundAuthorizedDeviceIDs
    }

    private func updateLifecycle() {
        if hasReadDemand {
            if readTask != nil, activeReadIDs == effectiveReadIDs { return }
            beginRead(superseding: true)
        } else {
            cancelActiveWork()
        }
    }

    private func cancelActiveWork() {
        generation &+= 1
        readTask?.cancel()
        readTask = nil
        activeReadIDs = []
        isRefreshing = false
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func beginRead(superseding: Bool) {
        guard !isStopped, hasReadDemand else { return }
        if superseding {
            generation &+= 1
            readTask?.cancel()
            readTask = nil
            refreshTask?.cancel()
            refreshTask = nil
        } else if readTask != nil {
            return
        }

        let readGeneration = generation
        let reader = self.reader
        let selectedIDs = effectiveReadIDs
        activeReadIDs = selectedIDs
        isRefreshing = true
        readTask = Task { [weak self, reader] in
            do {
                let result = try await reader.read(selectedIDs: selectedIDs)
                guard !Task.isCancelled else { return }
                self?.finishRead(result, generation: readGeneration)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishRead(
                    MobileBatteryReadResult(failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: nil)]),
                    generation: readGeneration
                )
            }
        }
    }

    private func finishRead(_ result: MobileBatteryReadResult, generation readGeneration: UInt64) {
        guard !isStopped, readGeneration == generation, hasReadDemand else { return }
        let currentIdentities = Set(effectiveReadIDs.map(\.readIdentity))
        let snapshots = result.snapshots.filter { currentIdentities.contains($0.identity) }
        readTask = nil
        activeReadIDs = []
        isRefreshing = false
        failures = result.failures.filter { failure in
            guard let deviceID = failure.deviceID else { return false }
            return effectiveReadIDs.contains { $0.matchesHelperIdentifier(deviceID) }
        }

        if !snapshots.isEmpty {
            var byIdentity = Dictionary(uniqueKeysWithValues: self.snapshots.map { ($0.identity, $0) })
            for snapshot in snapshots {
                byIdentity[snapshot.identity] = snapshot
            }
            self.snapshots = byIdentity.values.sorted { $0.identity < $1.identity }
        }
        pruneExpiredSnapshots()
        scheduleExpiry()
        scheduleNextRefresh(generation: readGeneration)
    }

    private func scheduleNextRefresh(generation readGeneration: UInt64) {
        guard !isStopped, readGeneration == generation, hasReadDemand else { return }
        let sleep = self.sleep
        let interval = isBackgroundRefreshEnabled ? backgroundRefreshInterval : Self.refreshInterval
        refreshTask = Task { [weak self, sleep] in
            do { try await sleep(interval) }
            catch { return }
            guard !Task.isCancelled else { return }
            guard let self, self.generation == readGeneration, self.hasReadDemand else { return }
            self.refreshTask = nil
            self.beginRead(superseding: false)
        }
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard let nextExpiry = snapshots.map({ $0.observedAt.addingTimeInterval(Self.cacheLifetime) }).min() else { return }

        let delay = max(0, nextExpiry.timeIntervalSince(clock()))
        let sleep = self.sleep
        expiryTask = Task { [weak self, sleep] in
            do { try await sleep(.seconds(delay)) }
            catch { return }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.expiryTask = nil
            self.pruneExpiredSnapshots()
            self.scheduleExpiry()
        }
    }

    private func pruneExpiredSnapshots() {
        let now = clock()
        let fresh = snapshots.filter { now < $0.observedAt.addingTimeInterval(Self.cacheLifetime) }
        if fresh.count != snapshots.count { snapshots = fresh }
    }

}

private extension AppleDeviceID {
    var readIdentity: String {
        switch self {
        case let .trustedDevice(id): "phone:\(id)"
        case let .trustedWatch(parentID, id): "watch:\(parentID):\(id)"
        case .ble: ""
        }
    }

    func matchesHelperIdentifier(_ identifier: String) -> Bool {
        switch self {
        case let .trustedDevice(id): id == identifier
        case let .trustedWatch(_, id): id == identifier
        case .ble: false
        }
    }
}
