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
    private let queue = DispatchQueue(label: "StatusTrio.SystemProfilerBluetoothPairedDeviceWorker")
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
        queue.async {
            guard let data = self.outputProvider(),
                  let devices = BluetoothPairedDeviceReader.parse(json: data) else {
                completion(.failed)
                return
            }
            // The battery reader reuses these exact bytes instead of spawning a
            // second profiler moments later.
            self.reportCache.store(data)
            completion(.success(devices))
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

    private let worker: any BluetoothPairedDeviceReading
    private let stateMonitor: any BluetoothStateMonitoring
    private let batteryReader: any BluetoothBatteryReading
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter

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
    private var requestGate = AsyncRequestGate()
    private var batteryRequestGate = AsyncRequestGate()
    /// One device read at a time, with at most one coalesced follow-up. Without
    /// this, every trigger started its own `/usr/sbin/system_profiler` process.
    private var isDeviceReadInFlight = false
    private var isRefreshPending = false
    private var batteryLevelsEnabled = false
    private var periodicRefreshTask: Task<Void, Never>?
    /// Identifies the current safety-net task. A cancelled task's `defer` only
    /// clears the reference while it is still the current generation, so a
    /// stop/start pair in one main-actor turn cannot leave the new task
    /// untracked and uncancellable.
    private var periodicRefreshGeneration: UInt64 = 0
    private var applicationObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

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
        connectionEvents: (any BluetoothConnectionEventMonitoring)? = nil,
        connectionEventDebounceInterval: Duration = .milliseconds(750),
        connectionEventDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
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
        self.connectionEvents = connectionEvents
        self.connectionEventDebounceInterval = connectionEventDebounceInterval
        self.connectionEventDebounceSleep = connectionEventDebounceSleep
        stateMonitor.onStateChange = { [weak self] authorization, managerState in
            self?.receiveSystemState(authorization: authorization, managerState: managerState)
        }
    }

    deinit {
        periodicRefreshTask?.cancel()
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
        registerSystemObservers()
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
        removeSystemObservers()
        stateMonitor.stop()
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
        let request = requestGate.advance()
        worker.read { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.requestGate.accepts(request) else { return }
                self.isDeviceReadInFlight = false
                guard self.isActive else { return }
                switch result {
                case let .success(devices):
                    self.devices = devices
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
                }
                if self.isRefreshPending {
                    self.isRefreshPending = false
                    self.refresh()
                }
            }
        }
    }

    /// Invalidates any in-flight device read. The completion that belongs to the
    /// invalidated read is discarded, so the latch has to be released here or no
    /// later refresh could ever start.
    private func invalidateDeviceRead() {
        _ = requestGate.advance()
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

    /// Surfaces that show Bluetooth device state, by token. The safety-net poll
    /// runs only while at least one is held, so a closed popover costs nothing.
    /// A count, not a boolean: the summary row and the detail page can appear in
    /// either order, and the last writer must not decide for both.
    private var visibleSurfaces: Set<String> = []

    /// Whether a visible surface is showing Bluetooth device state.
    var hasVisibleSurface: Bool {
        !visibleSurfaces.isEmpty
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

    /// Releases a surface's claim, whatever order it arrives in.
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
                self.batteryLevels = levels
            }
        }
    }

    private func clearBatteryLevels() {
        _ = batteryRequestGate.advance()
        batteryLevels = [:]
    }

    private func registerSystemObservers() {
        guard applicationObserver == nil, wakeObserver == nil else { return }
        applicationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAfterSystemEvent()
            }
        }
        wakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAfterSystemEvent()
            }
        }
    }

    private func removeSystemObservers() {
        if let applicationObserver {
            notificationCenter.removeObserver(applicationObserver)
        }
        if let wakeObserver {
            workspaceNotificationCenter.removeObserver(wakeObserver)
        }
        applicationObserver = nil
        wakeObserver = nil
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
        guard isMonitoringConnectionEventNotifications else { return }
        isMonitoringConnectionEventNotifications = false
        connectionEvents?.stop()
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
