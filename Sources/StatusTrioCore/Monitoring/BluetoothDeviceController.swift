import AppKit
@preconcurrency import CoreBluetooth
import Foundation

enum BluetoothWorkerResult: Sendable {
    case success([BluetoothDevice])
    case poweredOff
    case unavailable
    case failed
}

protocol BluetoothPairedDeviceReading: AnyObject {
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void)
}

@MainActor
protocol BluetoothStateMonitoring: AnyObject {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)? { get set }
    var authorization: BluetoothAuthorizationStatus { get }
    func start()
    func stop()
}


/// Reads the operating system's paired-device database from the system
/// profiler. It deliberately does not perform a Bluetooth inquiry, so nearby
/// BLE advertisements never appear as paired devices.
///
/// The profiler is the only source of device names: `IOBluetoothDevice
/// .nameOrAddress` returns a cached name that keeps reporting the old value
/// after the device is renamed, while the profiler reports what the system
/// currently uses. Battery levels already come from the same report.
final class SystemProfilerBluetoothPairedDeviceWorker: @unchecked Sendable, BluetoothPairedDeviceReading {
    typealias OutputProvider = @Sendable () -> Data?
    private static let queueLabel = "StatusTrio.SystemProfilerBluetoothPairedDeviceWorker"

    /// Guards `queue`, `queueGeneration` and `hasOutstandingRead`. `read` is
    /// called from the controller's main-actor context while a retired queue's
    /// block may still be running, so the retirement state is read and written
    /// under this lock rather than on whatever thread happens to call in.
    private let stateLock = NSLock()
    private var queue = DispatchQueue(label: queueLabel, qos: .utility)
    private var queueGeneration: UInt64 = 0
    private var hasOutstandingRead = false
    private let outputProvider: OutputProvider
    private let reportCache: BluetoothProfilerReportCache

    init(
        outputProvider: @escaping OutputProvider = SystemProfilerBluetoothPairedDeviceWorker.readSystemProfilerOutput,
        reportCache: BluetoothProfilerReportCache = .shared
    ) {
        self.outputProvider = outputProvider
        self.reportCache = reportCache
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        // A read that never returned would block this one behind it on the same
        // serial queue for the lifetime of the process, so retire that queue and
        // give this read a fresh one. The abandoned block keeps the old queue
        // alive until it eventually returns, which is what lets the controller's
        // watchdog retry a hung `/usr/sbin/system_profiler` at all.
        let generation: UInt64
        let currentQueue: DispatchQueue
        (generation, currentQueue) = stateLock.withLock {
            if hasOutstandingRead {
                queueGeneration &+= 1
                queue = DispatchQueue(label: Self.queueLabel, qos: .utility)
            }
            hasOutstandingRead = true
            return (queueGeneration, queue)
        }

        let outputProvider = self.outputProvider
        currentQueue.async { [weak self] in
            let result: BluetoothWorkerResult
            if let data = outputProvider(),
               let devices = BluetoothPairedDeviceReader.parse(json: data) {
                // The battery reader reuses these exact bytes instead of spawning a
                // second profiler moments later.
                self?.reportCache.store(data)
                result = .success(devices)
            } else {
                result = .failed
            }
            if let self {
                self.stateLock.withLock {
                    // Only the read on the current queue may clear the flag; a
                    // late completion from a retired queue must not, or the next
                    // read would queue behind a block that is still hung.
                    if generation == self.queueGeneration {
                        self.hasOutstandingRead = false
                    }
                }
            }
            completion(result)
        }
    }

    static func readSystemProfilerOutput() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPBluetoothDataType"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }
}

enum BluetoothPairedDeviceReader {
    /// `nil` means the report could not be read at all; an empty array means the
    /// machine has no paired devices. The two stay distinct so a read failure is
    /// never displayed as an empty device list.
    static func parse(json: Data) -> [BluetoothDevice]? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              // The profiler wraps the sections in one more level, which JSON
              // reports as an array. A bare section is accepted too, so a
              // wrapped-versus-unwrapped change can never read as "no devices".
              let value = root["SPBluetoothDataType"] else {
            return nil
        }
        let sections: [[String: Any]]
        if let list = value as? [[String: Any]] {
            sections = list
        } else if let single = value as? [String: Any] {
            sections = [single]
        } else {
            return nil
        }

        var devices: [BluetoothDevice] = []
        for section in sections {
            for (collectionKey, isConnected) in [
                ("device_connected", true),
                ("device_not_connected", false)
            ] {
                for entry in entries(from: section[collectionKey]) {
                    guard let properties = entry.properties,
                          let address = properties["device_address"] as? String,
                          !address.isEmpty,
                          !entry.name.isEmpty else {
                        continue
                    }
                    devices.append(BluetoothDevice(
                        id: address,
                        name: entry.name,
                        kind: kind(properties: properties),
                        isConnected: isConnected,
                        airPodsModel: AirPodsModel(
                            productIDText: properties["device_productID"] as? String,
                            vendorIDText: properties["device_vendorID"] as? String
                        )
                    ))
                }
            }
        }
        return devices
    }

    /// Each collection is a list whose entries map a device name to its
    /// properties. A single bare entry is accepted as well.
    private static func entries(from value: Any?) -> [(name: String, properties: [String: Any]?)] {
        let rawEntries: [Any]
        if let list = value as? [Any] {
            rawEntries = list
        } else if let single = value as? [String: Any], !single.isEmpty {
            rawEntries = [single]
        } else {
            return []
        }

        return rawEntries.flatMap { rawEntry -> [(name: String, properties: [String: Any]?)] in
            guard let entry = rawEntry as? [String: Any] else { return [] }
            return entry.map { (name: $0.key, properties: $0.value as? [String: Any]) }
        }
    }

    /// The minor type is the precise classification; the major type is the
    /// fallback. Unknown wording stays generic rather than being guessed as
    /// audio, which would make the device eligible for a battery level.
    private static func kind(properties: [String: Any]) -> BluetoothDeviceKind {
        switch properties["device_minorType"] as? String {
        case "Headphones", "Headset", "Speaker":
            return .audio
        case "Keyboard", "Mouse", "Trackpad", "Gamepad":
            return .peripheral
        case "Computer":
            return .computer
        case "Phone":
            return .phone
        default:
            break
        }

        switch properties["device_majorType"] as? String {
        case "Audio", "Wearable":
            return .audio
        case "Peripheral", "Input":
            return .peripheral
        case "Computer":
            return .computer
        case "Phone":
            return .phone
        default:
            return .unknown
        }
    }
}

/// CoreBluetooth supplies the app authorization and the asynchronous adapter
/// lifecycle; it is never used to enumerate devices. The paired-device database
/// comes from the system profiler above instead.
@MainActor
final class CoreBluetoothStateMonitor: NSObject, @preconcurrency CBCentralManagerDelegate, BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    private var centralManager: CBCentralManager?

    var authorization: BluetoothAuthorizationStatus {
        switch CBManager.authorization {
        case .notDetermined: .notDetermined
        case .allowedAlways: .allowed
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    func start() {
        guard centralManager == nil else {
            publishState()
            return
        }
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
        publishState()
    }

    func stop() {
        centralManager?.delegate = nil
        centralManager = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        publishState()
    }

    private func publishState() {
        onStateChange?(authorization, managerState())
    }

    private func managerState() -> BluetoothManagerState {
        switch centralManager?.state ?? .unknown {
        case .unknown: .unknown
        case .resetting: .resetting
        case .unsupported: .unsupported
        case .unauthorized: .unauthorized
        case .poweredOff: .poweredOff
        case .poweredOn: .poweredOn
        @unknown default: .unknown
        }
    }
}

@MainActor
final class BluetoothDeviceController: ObservableObject {
    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var availability: BluetoothAvailability = .idle
    @Published private(set) var batteryLevels: [String: BluetoothBatteryLevel] = [:]
    /// Whether the last level read failed outright.
    ///
    /// `batteryLevels` cannot say it: an empty dictionary is also what a report
    /// without any readable level looks like.
    @Published private(set) var batteryLevelsReadFailed = false

    private let worker: any BluetoothPairedDeviceReading
    /// The state monitor is teardown-owned storage: `deinit` is nonisolated, so
    /// it is held `nonisolated(unsafe)` for that one read. `BluetoothStateMonitoring`
    /// is `@MainActor`, and `stop()` runs on the main actor through the hop in
    /// `deinit` rather than being called off the queue CoreBluetooth was created on.
    nonisolated(unsafe) private let stateMonitor: any BluetoothStateMonitoring
    private let batteryReader: any BluetoothBatteryReading
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    /// The AppKit and workspace registrations, kept in teardown-owned storage so
    /// a nonisolated `deinit` can release them.
    private let systemObservers: SystemEventObserverBag

    /// How often the safety net re-reads the paired-device database while a
    /// Bluetooth surface is visible. Connection notifications deliver the
    /// interesting changes, so this is deliberately slow.
    private let safetyNetInterval: Duration
    private let safetyNetSleep: @Sendable (Duration) async throws -> Void
    /// The connect/disconnect source for the safety net. Optional so a test can
    /// build a controller that never touches the system's Bluetooth service.
    /// Teardown-owned storage: `deinit` is nonisolated and reads it directly.
    nonisolated(unsafe) private let connectionEvents: (any BluetoothConnectionEventMonitoring)?
    private let connectionEventDebounceInterval: Duration
    private let connectionEventDebounceSleep: @Sendable (Duration) async throws -> Void
    /// Invalidates a debounce that a later stop or deactivate superseded, the
    /// same way `AsyncRequestGate` guards the other asynchronous paths here.
    private var connectionEventGate = AsyncRequestGate()
    private var isConnectionEventReadScheduled = false
    /// Set from the registration result, so "monitoring" means the system
    /// accepted the registration rather than that it was merely attempted.
    private var isMonitoringConnectionEventNotifications = false
    private(set) var isActive = false
    private var batteryRequestGate = AsyncRequestGate()
    /// One device read at a time, with at most one coalesced follow-up. Without
    /// this, every trigger started its own `/usr/sbin/system_profiler` process.
    private var isDeviceReadInFlight = false
    private var isRefreshPending = false
    /// Identifies the current device read. A completion that belongs to a
    /// superseded token — invalidated, or abandoned by the watchdog — is
    /// discarded, so it can neither publish devices nor release the latch of the
    /// read that replaced it.
    private var readToken: UInt64 = 0
    /// Declares a read stuck once it has been outstanding for too long, so a
    /// hung `/usr/sbin/system_profiler` — a subprocess, so it can hang — cannot
    /// freeze the device row for the rest of the session. The worker moves the
    /// retry to a fresh queue, so the follow-up does not land behind the hung
    /// block on the queue it stalled.
    private let readWatchdog: ReadWatchdog
    private var batteryLevelsEnabled = false
    private var periodicRefreshTask: Task<Void, Never>?
    /// Identifies the current safety-net task. A cancelled task's `defer` only
    /// clears the reference while it is still the current generation, so a
    /// stop/start pair in one main-actor turn cannot leave the new task
    /// untracked and uncancellable.
    private var periodicRefreshGeneration: UInt64 = 0

    /// The action in flight, or the failure still on screen, keyed by normalized
    /// address. No entry means the row reports the device's own state.
    @Published private(set) var deviceActionStates: [String: BluetoothDeviceActionState] = [:]

    private let actionPerformer: any BluetoothDeviceActionPerforming
    private let actionTimeout: Duration
    private let actionTimeoutSleep: @Sendable (Duration) async throws -> Void
    private let failureVisibleDuration: Duration
    private let failureVisibleSleep: @Sendable (Duration) async throws -> Void
    private var actionTimeouts: [String: Task<Void, Never>] = [:]
    private var failureClearTasks: [String: Task<Void, Never>] = [:]
    /// Identifies the current request per device. A late completion from a
    /// superseded request must not decide the outcome of the one that replaced
    /// it — an action's result comes from its own request and report pair only.
    private var deviceActionTokens: [String: UInt64] = [:]
    /// Monotonic across the controller, so clearing the map can never hand an old
    /// token to a new request (a per-address gate would restart at zero).
    private var deviceActionTokenCounter: UInt64 = 0

    init(
        worker: any BluetoothPairedDeviceReading = SystemProfilerBluetoothPairedDeviceWorker(),
        stateMonitor: any BluetoothStateMonitoring = CoreBluetoothStateMonitor(),
        batteryReader: any BluetoothBatteryReading = SystemProfilerBluetoothBatteryWorker(),
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        safetyNetInterval: Duration = .seconds(30),
        safetyNetSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        systemObservers: SystemEventObserverBag? = nil,
        connectionEvents: (any BluetoothConnectionEventMonitoring)? = nil,
        connectionEventDebounceInterval: Duration = .milliseconds(750),
        connectionEventDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        readTimeout: Duration = .seconds(5),
        readTimeoutSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        actionPerformer: any BluetoothDeviceActionPerforming = IOBluetoothDeviceActionPerformer(),
        actionTimeout: Duration = .seconds(10),
        actionTimeoutSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        failureVisibleDuration: Duration = .seconds(4),
        failureVisibleSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.worker = worker
        self.stateMonitor = stateMonitor
        self.batteryReader = batteryReader
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.safetyNetInterval = safetyNetInterval
        self.safetyNetSleep = safetyNetSleep
        // The default bag reaches the same centers the controller was given, so
        // an injected `NotificationCenter` keeps driving the controller.
        self.systemObservers = systemObservers ?? SystemEventObserverBag(
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
        self.connectionEvents = connectionEvents
        self.connectionEventDebounceInterval = connectionEventDebounceInterval
        self.connectionEventDebounceSleep = connectionEventDebounceSleep
        readWatchdog = ReadWatchdog(
            baseTimeout: readTimeout,
            maxTimeout: .seconds(60),
            sleep: readTimeoutSleep
        )
        self.actionPerformer = actionPerformer
        self.actionTimeout = actionTimeout
        self.actionTimeoutSleep = actionTimeoutSleep
        self.failureVisibleDuration = failureVisibleDuration
        self.failureVisibleSleep = failureVisibleSleep
        stateMonitor.onStateChange = { [weak self] authorization, managerState in
            self?.receiveSystemState(authorization: authorization, managerState: managerState)
        }
    }

    deinit {
        periodicRefreshTask?.cancel()
        // Releasing the registrations here is the whole point: an observer token
        // that is never removed keeps the center's block alive for the life of
        // the process.
        systemObservers.removeAll()
        connectionEvents?.stop()
        // `CBCentralManager` retains its delegate, so the state monitor is never
        // deallocated while it is running. `stop()` has to run on the main actor,
        // which is the queue the manager was created with, so the reference is
        // captured and handed over instead of `self` being used after death.
        let stateMonitor = stateMonitor
        Task { @MainActor in stateMonitor.stop() }
    }


    var connectedDevices: [BluetoothDevice] {
        BluetoothDevicePresentation.grouped(devices).connected
    }

    /// Whether the controller has an event source at all.
    var hasConnectionEventSource: Bool {
        connectionEvents != nil
    }

    /// Whether connection notifications are being delivered right now.
    var isMonitoringConnectionEvents: Bool {
        isMonitoringConnectionEventNotifications
    }

    /// The app's current CoreBluetooth grant. Reading it never prompts; only
    /// starting the state monitor does.
    var authorization: BluetoothAuthorizationStatus {
        stateMonitor.authorization
    }

    func prepareForPresentation() {
        guard !isActive else { return }
        switch stateMonitor.authorization {
        case .notDetermined:
            availability = .authorizationNotDetermined
        case .denied:
            availability = .authorizationDenied
        case .restricted:
            availability = .authorizationRestricted
        case .allowed:
            availability = .idle
        }
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        systemObservers.install(
            applicationActivated: { [weak self] in
                Task { @MainActor in self?.refreshAfterSystemEvent() }
            },
            didWake: { [weak self] in
                Task { @MainActor in self?.refreshAfterSystemEvent() }
            }
        )
        stateMonitor.start()
        schedulePeriodicRefresh()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        invalidateDeviceRead()
        batteryLevelRequests.removeAll()
        updateBatteryLevelRequests()
        stopPeriodicRefresh()
        systemObservers.removeAll()
        stateMonitor.stop()
        clearDeviceActions()
        availability = .idle
    }

    func refresh() {
        guard isActive, availability == .available else { return }
        // Coalesce bursts: at most one read and one follow-up are retained,
        // whatever order the triggers arrive in.
        guard !isDeviceReadInFlight else {
            isRefreshPending = true
            return
        }
        isDeviceReadInFlight = true
        readToken &+= 1
        let token = readToken
        readWatchdog.arm { [weak self] in
            self?.abandonTimedOutRead(token: token)
        }
        worker.read { [weak self] result in
            Task { @MainActor [weak self] in
                // A completion that arrives after the read was declared stuck,
                // or after a later trigger superseded it, belongs to a retired
                // token: it must not release the latch of the read that
                // replaced it, let alone publish over it.
                guard let self, token == self.readToken else { return }
                self.readWatchdog.cancel()
                self.readWatchdog.recordSuccess()
                self.isDeviceReadInFlight = false
                guard self.isActive else { return }
                switch result {
                case let .success(devices):
                    self.devices = devices
                    self.reconcileDeviceActions()
                    self.availability = .available
                    self.refreshBatteryLevels()
                case .poweredOff:
                    self.availability = .poweredOff
                    self.clearBatteryLevels()
                    self.stopPeriodicRefresh()
                case .unavailable:
                    self.availability = .unavailable
                    self.clearBatteryLevels()
                    self.stopPeriodicRefresh()
                case .failed:
                    self.availability = .failed
                    self.clearBatteryLevels()
                    // No poll can succeed while the read is failing, so the
                    // connection-event registration goes with it: otherwise the
                    // controller would hold a live event registration with no
                    // poll behind it, which is a state no other branch leaves.
                    self.stopPeriodicRefresh()
                }
                if self.isRefreshPending {
                    self.isRefreshPending = false
                    self.refresh()
                }
            }
        }
    }

    /// A system read never returned. Ignore its late completion, release the
    /// single-read latch so the controller is not stuck forever, and start the
    /// coalesced follow-up. The worker moves that retry to a fresh queue, which
    /// is what makes this recovery actually run instead of landing behind the
    /// block that is still hung.
    private func abandonTimedOutRead(token: UInt64) {
        guard token == readToken else { return }
        readToken &+= 1
        isDeviceReadInFlight = false
        // The follow-up started below consumes the coalesced trigger, so the
        // flag has to be cleared here. Leaving it set made the replacement read
        // consume an already-consumed trigger and run one extra profiler pass
        // after every timeout.
        isRefreshPending = false
        refresh()
    }

    /// Invalidates any in-flight device read. The completion that belongs to the
    /// invalidated read is discarded, so the latch has to be released here or no
    /// later refresh could ever start. The watchdog is disarmed for the same
    /// reason: nothing is outstanding any more, and its timeout would otherwise
    /// abandon a read that is already gone. Recording a success with the
    /// cancellation resets the backoff, so a session that deactivated after a
    /// timeout starts again from the 5 s base instead of the previous penalty.
    private func invalidateDeviceRead() {
        readToken &+= 1
        readWatchdog.cancel()
        readWatchdog.recordSuccess()
        isDeviceReadInFlight = false
        isRefreshPending = false
    }

    /// Surfaces that need battery levels, by token. Two of them share this need
    /// — the summary row (for the AirPods it reports) and the detail page (for
    /// every device) — and SwiftUI may run the outgoing surface's disappear hook
    /// either before or after the incoming surface's appear hook. A count makes
    /// the outcome independent of that order, where a single boolean let the
    /// last writer win and left the detail page reading nothing.
    private var batteryLevelRequests: Set<String> = []

    /// Claims battery levels for a surface. The read starts when the first
    /// claim arrives and stops when the last one is released.
    func requestBatteryLevels(_ token: String) {
        guard batteryLevelRequests.insert(token).inserted else {
            // The claim is already held: keep the reading warm.
            refreshBatteryLevels()
            return
        }
        updateBatteryLevelRequests()
    }

    /// Releases a surface's claim, whatever the order it arrives in.
    func releaseBatteryLevels(_ token: String) {
        guard batteryLevelRequests.remove(token) != nil else { return }
        updateBatteryLevelRequests()
    }

    private func updateBatteryLevelRequests() {
        let enabled = !batteryLevelRequests.isEmpty
        guard batteryLevelsEnabled != enabled else {
            if enabled { refreshBatteryLevels() }
            return
        }
        batteryLevelsEnabled = enabled
        // Levels read for a released claim must not outlive it.
        clearBatteryLevels()
        if enabled {
            refreshBatteryLevels()
        }
    }

    /// Whether a visible surface has asked for battery levels.
    var isBatteryLevelsRequested: Bool {
        batteryLevelsEnabled
    }

    /// Surfaces that show Bluetooth device state, by token. Every claim is
    /// recorded so insertion and removal stay order-independent, but only the
    /// popover-level claim sustains the safety-net poll.
    private var visibleSurfaces: Set<String> = []

    /// The popover-level claim. `SystemStatusStore` holds it while the popover is
    /// open and releases it on close, so it is the only claim that can start the
    /// poll. The view-level claims (`"bluetooth.summary.surface"` and
    /// `"bluetooth.detail.surface"` in `BluetoothDeviceListView`) are released
    /// only from SwiftUI `onDisappear`, and the popover's content view
    /// controller is retained after close: a skipped `onDisappear` would
    /// otherwise leave the claim set non-empty and restart a 30 s poll for the
    /// life of the process. A view claim may only narrow this one, never
    /// sustain the poll on its own.
    static let popoverSurfaceToken = "bluetooth.popover"

    /// Whether the popover is showing Bluetooth device state. A leaked view
    /// claim cannot make this true.
    var hasVisibleSurface: Bool {
        visibleSurfaces.contains(Self.popoverSurfaceToken)
    }

    /// Whether the safety-net poll is running.
    var isSafetyNetPolling: Bool {
        periodicRefreshTask != nil
    }

    /// Claims the safety net for a visible Bluetooth surface.
    func holdVisibleSurface(_ token: String) {
        guard visibleSurfaces.insert(token).inserted else { return }
        schedulePeriodicRefresh()
    }

    /// Releases a surface's claim, whatever order it arrives in. Releasing the
    /// popover claim stops the poll even while a view claim is still held.
    func releaseVisibleSurface(_ token: String) {
        guard visibleSurfaces.remove(token) != nil else { return }
        guard !hasVisibleSurface else { return }
        stopPeriodicRefresh()
    }

    private func receiveSystemState(
        authorization: BluetoothAuthorizationStatus,
        managerState: BluetoothManagerState
    ) {
        guard isActive else { return }
        let mappedAvailability = BluetoothAvailabilityMapper.preliminary(
            authorization: authorization,
            managerState: managerState
        )
        availability = mappedAvailability

        if mappedAvailability == .available {
            schedulePeriodicRefresh()
            refresh()
        } else {
            invalidateDeviceRead()
            clearBatteryLevels()
            stopPeriodicRefresh()
        }
    }

    private func refreshBatteryLevels() {
        guard isActive, batteryLevelsEnabled, availability == .available else { return }
        let request = batteryRequestGate.advance()
        batteryReader.read { [weak self] levels in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isActive,
                      self.batteryLevelsEnabled,
                      self.availability == .available,
                      self.batteryRequestGate.accepts(request) else {
                    return
                }
                // `nil` is a report that could not be read, which is a different
                // state from a report that carries no level for any device: the
                // detail page reports it once instead of staying silent.
                self.batteryLevelsReadFailed = levels == nil
                self.batteryLevels = levels ?? [:]
            }
        }
    }

    private func clearBatteryLevels() {
        _ = batteryRequestGate.advance()
        batteryLevelsReadFailed = false
        batteryLevels = [:]
    }

    private func refreshAfterSystemEvent() {
        guard isActive else { return }
        stateMonitor.start()
    }

    private func schedulePeriodicRefresh() {
        guard isActive, hasVisibleSurface, availability == .available else { return }
        startConnectionEvents()
        guard periodicRefreshTask == nil else { return }
        let interval = safetyNetInterval
        let sleep = safetyNetSleep
        periodicRefreshGeneration &+= 1
        let generation = periodicRefreshGeneration
        periodicRefreshTask = Task { @MainActor [weak self] in
            defer {
                // Only the task that is still current may clear the reference.
                // A stop can cancel this task and start a replacement in the
                // same main-actor turn, before this `defer` runs; clearing
                // unconditionally would leave the replacement untracked and
                // uncancellable.
                if let self, self.periodicRefreshGeneration == generation {
                    self.periodicRefreshTask = nil
                }
            }
            while !Task.isCancelled {
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard let self, self.isActive, self.hasVisibleSurface, self.availability == .available else {
                    return
                }
                self.refresh()
            }
        }
    }

    private func stopPeriodicRefresh() {
        // Invalidate the running task before cancelling it, so its `defer` can
        // tell that it has been superseded.
        periodicRefreshGeneration &+= 1
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        stopConnectionEvents()
    }

    /// Connection notifications only matter while a Bluetooth surface is on
    /// screen: nothing else displays device state, and the registration is a
    /// system resource the app should not hold for its whole lifetime.
    private func startConnectionEvents() {
        guard !isMonitoringConnectionEventNotifications, let connectionEvents else { return }
        // The handler arrives on IOBluetooth's own thread, so it hops to the
        // main actor before touching controller state.
        isMonitoringConnectionEventNotifications = connectionEvents.start { [weak self] in
            Task { @MainActor in self?.receiveConnectionEvent() }
        }
    }

    private func stopConnectionEvents() {
        _ = connectionEventGate.advance()
        isConnectionEventReadScheduled = false
        // Unconditional: a refused registration (`start` returned `false`) can
        // still have stored the handler, so the monitor is told to stop either
        // way and the teardown path has one shape. `stop()` is lock-guarded and
        // idempotent.
        isMonitoringConnectionEventNotifications = false
        connectionEvents?.stop()
    }

    // MARK: - Device actions

    /// Asks the system to toggle a device. The row's state changes when the
    /// report does, never because this call returned: the request only starts a
    /// wait that ends in the report changing or in a visible failure.
    func performDeviceAction(for device: BluetoothDevice) {
        guard isActive, availability == .available else { return }
        let address = BluetoothBatteryReader.normalizedAddress(device.id)
        switch deviceActionStates[address] {
        case .none, .failed:
            // Free, or a retry of a failure that is still on screen. The
            // superseded failure's clear no longer has anything to clear, so it
            // goes with the state it was armed for.
            failureClearTasks[address]?.cancel()
            failureClearTasks[address] = nil
        case .connecting, .disconnecting:
            // One action per device at a time.
            return
        }

        let action = BluetoothDeviceActionPolicy.action(for: device)
        deviceActionTokenCounter &+= 1
        let token = deviceActionTokenCounter
        deviceActionTokens[address] = token
        deviceActionStates[address] = action.inFlightState
        armActionTimeout(for: action, address: address, token: token)
        actionPerformer.setConnected(action == .connect, forAddress: address) { [weak self] accepted in
            guard !accepted else { return }
            Task { @MainActor [weak self] in
                guard let self, self.deviceActionTokens[address] == token else { return }
                self.failDeviceAction(action, address: address)
            }
        }
    }

    /// Clears the actions whose target state the report now shows. This is the
    /// only way an action succeeds.
    private func reconcileDeviceActions() {
        guard !deviceActionStates.isEmpty else { return }
        for device in devices {
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            guard let state = deviceActionStates[address] else { continue }
            let reachedTarget = switch state {
            case .connecting: device.isConnected
            case .disconnecting: !device.isConnected
            case .failed: false
            }
            if reachedTarget {
                finishDeviceAction(address: address)
            }
        }
    }

    private func armActionTimeout(for action: BluetoothDeviceAction, address: String, token: UInt64) {
        actionTimeouts[address]?.cancel()
        let timeout = actionTimeout
        let sleep = actionTimeoutSleep
        actionTimeouts[address] = Task { @MainActor [weak self] in
            do {
                try await sleep(timeout)
            } catch {
                return
            }
            guard let self,
                  self.deviceActionTokens[address] == token,
                  self.deviceActionStates[address] == action.inFlightState else { return }
            self.failDeviceAction(action, address: address)
        }
    }

    private func failDeviceAction(_ action: BluetoothDeviceAction, address: String) {
        actionTimeouts[address]?.cancel()
        actionTimeouts[address] = nil
        deviceActionStates[address] = .failed(action)

        failureClearTasks[address]?.cancel()
        let visible = failureVisibleDuration
        let sleep = failureVisibleSleep
        failureClearTasks[address] = Task { @MainActor [weak self] in
            do {
                try await sleep(visible)
            } catch {
                return
            }
            guard let self, case .failed = self.deviceActionStates[address] else { return }
            self.deviceActionStates[address] = nil
            self.failureClearTasks[address] = nil
        }
    }

    private func finishDeviceAction(address: String) {
        actionTimeouts[address]?.cancel()
        actionTimeouts[address] = nil
        failureClearTasks[address]?.cancel()
        failureClearTasks[address] = nil
        deviceActionStates[address] = nil
    }

    private func clearDeviceActions() {
        for task in actionTimeouts.values { task.cancel() }
        for task in failureClearTasks.values { task.cancel() }
        actionTimeouts.removeAll()
        failureClearTasks.removeAll()
        deviceActionTokens.removeAll()
        deviceActionStates.removeAll()
    }

    /// One read per burst of connect/disconnect notifications. macOS connects
    /// several devices at once (AirPods plus a Watch, say), and each
    /// notification would otherwise start its own profiler run.
    private func receiveConnectionEvent() {
        guard isActive, isMonitoringConnectionEventNotifications else { return }
        guard !isConnectionEventReadScheduled else { return }
        isConnectionEventReadScheduled = true
        let request = connectionEventGate.advance()
        let interval = connectionEventDebounceInterval
        let sleep = connectionEventDebounceSleep
        Task { @MainActor [weak self] in
            do {
                try await sleep(interval)
            } catch {
                guard let self, self.connectionEventGate.accepts(request) else { return }
                self.isConnectionEventReadScheduled = false
                return
            }
            guard let self, self.connectionEventGate.accepts(request) else { return }
            self.isConnectionEventReadScheduled = false
            guard self.isActive else { return }
            self.refresh()
        }
    }
}
