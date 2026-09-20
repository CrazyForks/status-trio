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
    private(set) var isActive = false
    private var requestGate = AsyncRequestGate()
    private var batteryRequestGate = AsyncRequestGate()
    private var batteryLevelsEnabled = false
    private var periodicRefreshTask: Task<Void, Never>?
    private var applicationObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    init(
        worker: any BluetoothPairedDeviceReading = SystemProfilerBluetoothPairedDeviceWorker(),
        stateMonitor: any BluetoothStateMonitoring = CoreBluetoothStateMonitor(),
        batteryReader: any BluetoothBatteryReading = SystemProfilerBluetoothBatteryWorker(),
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.worker = worker
        self.stateMonitor = stateMonitor
        self.batteryReader = batteryReader
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
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
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        _ = requestGate.advance()
        batteryLevelRequests.removeAll()
        updateBatteryLevelRequests()
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        removeSystemObservers()
        stateMonitor.stop()
        availability = .idle
    }

    func refresh() {
        guard isActive, availability == .available else { return }
        let request = requestGate.advance()
        worker.read { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.requestGate.accepts(request) else { return }
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
            }
        }
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
            _ = requestGate.advance()
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
        guard periodicRefreshTask == nil else { return }
        periodicRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
                guard let self, self.isActive, self.availability == .available else { return }
                self.refresh()
            }
        }
    }

    private func stopPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
    }
}
