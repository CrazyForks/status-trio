@preconcurrency import CoreBluetooth
import Foundation

struct BluetoothLEBatteryScanPolicy {
    static let scanWindow: Duration = .seconds(5)
    static let automaticScanInterval: TimeInterval = 60
    /// Retained for presentation-cache compatibility. Passive discovery does not
    /// produce readings, so no nearby battery value is cached by the scanner.
    static let resultLifetime: TimeInterval = 1800

    private(set) var generation: UInt64 = 0
    private var lastScanStartedAt: Date?

    mutating func beginScan(at date: Date, manual: Bool) -> Bool {
        if !manual,
           let lastScanStartedAt,
           date.timeIntervalSince(lastScanStartedAt) < Self.automaticScanInterval {
            return false
        }
        lastScanStartedAt = date
        return true
    }

    func acceptsCallback(from generation: UInt64) -> Bool {
        self.generation == generation
    }

    mutating func stop() {
        generation &+= 1
        lastScanStartedAt = nil
    }
}

@MainActor
protocol BluetoothLEBatteryScanning: AnyObject {
    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)? { get set }
    var onCandidatesChanged: (([NearbyBLEDeviceCandidate]) -> Void)? { get set }
    var onReadFailures: ((Set<UUID>) -> Void)? { get set }
    var onIsScanningChanged: ((Bool) -> Void)? { get set }
    var isRunning: Bool { get }
    var isScanning: Bool { get }

    func setAllowedReadDeviceIDs(_ ids: Set<UUID>)
    func start()
    func refresh()
    func stop()
}

/// Passive discovery deliberately has no CBPeripheral delegate and no GATT
/// path. Nearby Apple devices can be listed from advertisements, but battery
/// data is read only by the trusted USB/Wi-Fi helper paths.
@MainActor
final class CoreBluetoothLEBatteryScanner: NSObject,
    BluetoothLEBatteryScanning,
    @preconcurrency CBCentralManagerDelegate {

    private static let batteryServiceUUID = CBUUID(string: "180F")

    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)?
    var onCandidatesChanged: (([NearbyBLEDeviceCandidate]) -> Void)?
    var onReadFailures: ((Set<UUID>) -> Void)?
    var onIsScanningChanged: ((Bool) -> Void)?
    private(set) var isRunning = false
    private(set) var isScanning = false

    private var centralManager: CBCentralManager?
    private var scanWindowTask: Task<Void, Never>?
    private var automaticRefreshTask: Task<Void, Never>?
    private var candidateExpiryTask: Task<Void, Never>?
    private var policy = BluetoothLEBatteryScanPolicy()
    private var candidateCache = NearbyBLECandidateCache()
    private var currentScanGeneration: UInt64 = 0

    deinit {
        scanWindowTask?.cancel()
        automaticRefreshTask?.cancel()
        candidateExpiryTask?.cancel()
        let manager = centralManager
        Task { @MainActor in
            manager?.stopScan()
            manager?.delegate = nil
        }
    }

    func start() {
        guard !isRunning, CBManager.authorization == .allowedAlways else { return }
        isRunning = true
        ensureCentralManager()
        if centralManager?.state == .poweredOn { startScanWindow(manual: true) }
        publishNoBatteryReadings()
    }

    /// Legacy controller hook retained for compatibility. Selection never
    /// authorizes a Bluetooth connection or battery read.
    func setAllowedReadDeviceIDs(_ ids: Set<UUID>) {}

    func refresh() {
        guard isRunning else {
            start()
            return
        }
        guard !isScanning else { return }
        startScanWindow(manual: true)
    }

    func stop() {
        isRunning = false
        stopActiveWork(clearCandidates: true)
        releaseCentralIfIdle()
        publishNoBatteryReadings()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === centralManager, isRunning else { return }
        switch central.state {
        case .poweredOn:
            startScanWindow(manual: true)
        case .unauthorized, .unsupported:
            stop()
        case .unknown, .resetting, .poweredOff:
            stopActiveWork()
        @unknown default:
            stopActiveWork()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard central === centralManager,
              isRunning,
              isScanning,
              policy.acceptsCallback(from: currentScanGeneration) else { return }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard BluetoothLEBatteryAdvertisement.isCandidate(
            serviceUUIDs: advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            name: advertisedName ?? peripheral.name,
            batteryService: Self.batteryServiceUUID
        ) else { return }

        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        publishCandidate(
            id: peripheral.identifier,
            name: advertisedName ?? peripheral.name ?? "",
            vendor: NearbyBLEVendor.fromManufacturerData(manufacturerData)
        )
    }

    private func ensureCentralManager() {
        guard centralManager == nil, CBManager.authorization == .allowedAlways else { return }
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    private func startScanWindow(manual: Bool) {
        guard isRunning,
              !isScanning,
              let centralManager,
              centralManager.state == .poweredOn,
              policy.beginScan(at: Date(), manual: manual) else { return }

        candidateCache.beginScan()
        setScanning(true)
        currentScanGeneration = policy.generation
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        let generation = policy.generation
        scanWindowTask?.cancel()
        scanWindowTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: BluetoothLEBatteryScanPolicy.scanWindow)
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  self.policy.acceptsCallback(from: generation),
                  self.isRunning,
                  self.isScanning else { return }
            self.finishScanWindow()
        }
    }

    private func finishScanWindow() {
        scanWindowTask?.cancel()
        scanWindowTask = nil
        centralManager?.stopScan()
        setScanning(false)
        onCandidatesChanged?(candidateCache.finishScan(at: Date()))
        scheduleCandidateExpiry()
        scheduleAutomaticRefresh()
    }

    private func scheduleAutomaticRefresh() {
        automaticRefreshTask?.cancel()
        guard isRunning else { return }
        automaticRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(Int(BluetoothLEBatteryScanPolicy.automaticScanInterval)))
            } catch {
                return
            }
            guard let self, self.isRunning else { return }
            self.startScanWindow(manual: false)
        }
    }

    private func scheduleCandidateExpiry() {
        candidateExpiryTask?.cancel()
        guard let expiration = candidateCache.nextExpiration else { return }
        candidateExpiryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, expiration.timeIntervalSinceNow)))
            } catch {
                return
            }
            guard let self else { return }
            self.onCandidatesChanged?(self.candidateCache.expire(at: Date()))
            self.scheduleCandidateExpiry()
        }
    }

    private func publishCandidate(id: UUID, name: String, vendor: NearbyBLEVendor) {
        candidateCache.record(NearbyBLEDeviceCandidate(id: id, name: name, vendor: vendor, lastSeen: Date()))
        onCandidatesChanged?(candidateCache.candidates)
        scheduleCandidateExpiry()
    }

    private func publishNoBatteryReadings() {
        onDevicesChanged?([])
        onReadFailures?([])
    }

    private func setScanning(_ scanning: Bool) {
        guard isScanning != scanning else { return }
        isScanning = scanning
        onIsScanningChanged?(scanning)
    }

    private func stopActiveWork(clearCandidates: Bool = false) {
        scanWindowTask?.cancel()
        scanWindowTask = nil
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        centralManager?.stopScan()
        setScanning(false)
        policy.stop()
        if clearCandidates {
            candidateExpiryTask?.cancel()
            candidateExpiryTask = nil
            onCandidatesChanged?(candidateCache.clear())
        }
    }

    private func releaseCentralIfIdle() {
        guard !isRunning, let manager = centralManager else { return }
        manager.stopScan()
        manager.delegate = nil
        centralManager = nil
    }
}
