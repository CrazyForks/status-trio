@preconcurrency import CoreBluetooth
import Foundation

struct BluetoothLEBatteryScanPolicy {
    static let scanWindow: Duration = .seconds(5)
    static let automaticScanInterval: TimeInterval = 60
    static let successfulConnectionCooldown: TimeInterval = 60
    static let failedConnectionCooldown: TimeInterval = 30
    /// How long a reading stays usable, in the scanner's own results and in the
    /// panel's cache of them behind a closed panel.
    ///
    /// It only decides whether the reading may still draw a row: every panel open
    /// starts a fresh scan, and what it reads replaces the cached level the moment
    /// it lands. So the number on screen is always the last one read, and this
    /// governs the other thing — whether a device known a moment ago is drawn at
    /// once or has to be re-discovered, re-connected and re-read before it can
    /// appear. Half an hour covers a working session of opening and closing the
    /// panel; in exchange, a device that leaves the room keeps its row, with the
    /// level it last answered, until the reading expires.
    static let resultLifetime: TimeInterval = 1800
    static let maxQueuedCandidates = 8
    static let maxConcurrentConnections = 2
    static let connectionTimeout: Duration = .seconds(4)

    private(set) var generation: UInt64 = 0
    private(set) var queuedCandidateCount = 0
    private(set) var inFlightConnectionCount = 0

    private var lastScanStartedAt: Date?
    private var discoveredCandidates: Set<UUID> = []
    private var queuedCandidates: [UUID] = []
    private var inFlightConnections: Set<UUID> = []
    private var retryAfter: [UUID: Date] = [:]

    mutating func beginScan(at date: Date, manual: Bool) -> Bool {
        if !manual,
           let lastScanStartedAt,
           date.timeIntervalSince(lastScanStartedAt) < Self.automaticScanInterval {
            return false
        }

        lastScanStartedAt = date
        retryAfter = retryAfter.filter { $0.value > date }
        discoveredCandidates.removeAll(keepingCapacity: true)
        queuedCandidates.removeAll(keepingCapacity: true)
        queuedCandidateCount = 0
        return true
    }

    mutating func enqueueCandidate(_ id: UUID, at date: Date) -> Bool {
        guard !discoveredCandidates.contains(id),
              !inFlightConnections.contains(id),
              discoveredCandidates.count < Self.maxQueuedCandidates else {
            return false
        }
        discoveredCandidates.insert(id)

        if let retryDate = retryAfter[id], date < retryDate {
            return false
        }

        queuedCandidates.append(id)
        queuedCandidateCount = queuedCandidates.count
        return true
    }

    mutating func startQueuedConnections() -> [UUID] {
        let availableSlots = max(0, Self.maxConcurrentConnections - inFlightConnections.count)
        guard availableSlots > 0 else { return [] }

        let count = min(availableSlots, queuedCandidates.count)
        let candidates = Array(queuedCandidates.prefix(count))
        queuedCandidates.removeFirst(count)
        inFlightConnections.formUnion(candidates)
        queuedCandidateCount = queuedCandidates.count
        inFlightConnectionCount = inFlightConnections.count
        return candidates
    }

    mutating func discardQueuedCandidates() {
        queuedCandidates.removeAll(keepingCapacity: false)
        queuedCandidateCount = 0
    }

    mutating func completeConnection(_ id: UUID, succeeded: Bool, at date: Date) {
        guard inFlightConnections.remove(id) != nil else { return }
        let cooldown = succeeded ? Self.successfulConnectionCooldown : Self.failedConnectionCooldown
        retryAfter[id] = date.addingTimeInterval(cooldown)
        inFlightConnectionCount = inFlightConnections.count
    }

    func acceptsCallback(from generation: UInt64) -> Bool {
        self.generation == generation
    }

    mutating func stop() {
        generation &+= 1
        discoveredCandidates.removeAll(keepingCapacity: false)
        queuedCandidates.removeAll(keepingCapacity: false)
        inFlightConnections.removeAll(keepingCapacity: false)
        // The cooldowns belong to the session that earned them. A session ends
        // when the panel closes or the radio goes away, and the next one starts
        // with nothing to stay away from: without this, a panel reopened a moment
        // after it closed would skip every device it read the last time and come
        // up empty until the cooldown ran out — a minute of showing nothing for
        // the devices the user had just seen.
        retryAfter.removeAll(keepingCapacity: false)
        queuedCandidateCount = 0
        inFlightConnectionCount = 0
    }
}

/// When a session's reading is settled enough to publish.
///
/// A battery byte on its own is the whole answer for a device that advertises
/// `180F` and nothing else, so it goes out as soon as it arrives. It is not the
/// whole answer for a device that also answers with a model string: that string
/// is what decides which list the row belongs in — a model the app draws is
/// folded onto the row the device already has in the paired list, and a model it
/// does not draw leaves the device in the nearby list. Publishing the level
/// first showed the phone in the nearby list for the tenth of a second the model
/// read needs and then moved it into the paired list, which put the panel's
/// "paired devices" header on screen and took it off again in the same moment.
///
/// The wait is bounded by the session, not by the read: a device that stops
/// answering the model characteristic still publishes what it did answer when
/// the session ends.
enum BluetoothLEBatteryPublishGate {
    static func shouldPublish(
        batteryLevel: Int?,
        modelReadPending: Bool,
        sessionIsEnding: Bool
    ) -> Bool {
        guard batteryLevel != nil else { return false }
        return sessionIsEnding || !modelReadPending
    }
}

@MainActor
protocol BluetoothLEBatteryScanning: AnyObject {
    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)? { get set }
    var isRunning: Bool { get }
    var isScanning: Bool { get }

    func start()
    func refresh()
    func stop()
}

/// Scans only for peripherals that advertise the standard Battery Service.
/// CoreBluetooth is created on first authorized start, never at construction.
@MainActor
final class CoreBluetoothLEBatteryScanner: NSObject,
    BluetoothLEBatteryScanning,
    @preconcurrency CBCentralManagerDelegate,
    @preconcurrency CBPeripheralDelegate {

    private struct PeripheralSession {
        let peripheral: CBPeripheral
        let generation: UInt64
        let advertisedName: String?
        var timeoutTask: Task<Void, Never>?
        var pendingCharacteristicDiscoveries = 0
        var pendingReads: Set<CBUUID> = []
        var batteryLevel: Int?
        var model: String?
        var manufacturer: String?
    }

    private static let batteryServiceUUID = CBUUID(string: "180F")
    private static let batteryLevelUUID = CBUUID(string: "2A19")
    private static let deviceInformationServiceUUID = CBUUID(string: "180A")
    private static let modelNumberUUID = CBUUID(string: "2A24")
    private static let manufacturerNameUUID = CBUUID(string: "2A29")

    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)?
    private(set) var isRunning = false
    private(set) var isScanning = false

    /// These references are mutated only on the main actor. `deinit` is
    /// nonisolated, so it reads them only to cancel tasks and hand CoreBluetooth
    /// cleanup back to the main actor, following the controller's teardown rule.
    nonisolated(unsafe) private var centralManager: CBCentralManager?
    nonisolated(unsafe) private var sessions: [UUID: PeripheralSession] = [:]
    nonisolated(unsafe) private var scanWindowTask: Task<Void, Never>?
    nonisolated(unsafe) private var automaticRefreshTask: Task<Void, Never>?

    private var policy = BluetoothLEBatteryScanPolicy()
    private var candidatePeripherals: [UUID: CBPeripheral] = [:]
    private var candidateNames: [UUID: String] = [:]
    private var nearbyDevices: [UUID: NearbyBluetoothBatteryDevice] = [:]
    private var currentScanGeneration: UInt64 = 0

    deinit {
        scanWindowTask?.cancel()
        automaticRefreshTask?.cancel()
        let manager = centralManager
        let peripherals = sessions.values.map(\.peripheral)
        sessions.values.forEach { $0.timeoutTask?.cancel() }
        guard manager != nil || !peripherals.isEmpty else { return }

        // CoreBluetooth delegates and peripheral teardown run on the manager's
        // main queue. The captured references outlive this scanner only until
        // the teardown block has stopped scans and cancelled its GATT sessions.
        Task { @MainActor in
            manager?.stopScan()
            for peripheral in peripherals {
                peripheral.delegate = nil
                manager?.cancelPeripheralConnection(peripheral)
            }
            manager?.delegate = nil
        }
    }

    func start() {
        guard !isRunning,
              CBManager.authorization == .allowedAlways else {
            return
        }

        isRunning = true
        ensureCentralManager()
        if centralManager?.state == .poweredOn {
            startScanWindow(manual: true)
        }
    }

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
        stopActiveWork(clearResults: true)
        centralManager?.delegate = nil
        centralManager = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard isRunning else { return }
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
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard isRunning,
              isScanning,
              BluetoothLEBatteryAdvertisement.isCandidate(
                  serviceUUIDs: advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
                  manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
                  name: advertisedName ?? peripheral.name,
                  batteryService: Self.batteryServiceUUID
              ),
              policy.acceptsCallback(from: currentScanGeneration) else {
            return
        }

        let identifier = peripheral.identifier
        guard policy.enqueueCandidate(identifier, at: Date()) else { return }
        candidatePeripherals[identifier] = peripheral
        // The advertisement name is transient, kept only in this in-memory
        // session and never logged or persisted.
        candidateNames[identifier] = advertisedName
        startQueuedConnections()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let identifier = peripheral.identifier
        guard var session = currentSession(for: identifier) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }

        peripheral.delegate = self
        session.pendingCharacteristicDiscoveries = 1
        sessions[identifier] = session
        peripheral.discoverServices([
            Self.batteryServiceUUID,
            Self.deviceInformationServiceUUID
        ])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        completeSession(for: peripheral.identifier, succeeded: false)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        let succeeded = sessions[peripheral.identifier]?.batteryLevel != nil
        completeSession(for: peripheral.identifier, succeeded: succeeded)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        let identifier = peripheral.identifier
        guard var session = currentSession(for: identifier) else { return }
        guard error == nil else {
            completeSession(for: identifier, succeeded: false)
            return
        }

        let services = (peripheral.services ?? []).filter { service in
            isUUID(service.uuid, Self.batteryServiceUUID)
                || isUUID(service.uuid, Self.deviceInformationServiceUUID)
        }
        guard services.contains(where: { isUUID($0.uuid, Self.batteryServiceUUID) }) else {
            completeSession(for: identifier, succeeded: false)
            return
        }

        session.pendingCharacteristicDiscoveries = services.count
        sessions[identifier] = session
        for service in services {
            let characteristics: [CBUUID]
            if isUUID(service.uuid, Self.batteryServiceUUID) {
                characteristics = [Self.batteryLevelUUID]
            } else {
                characteristics = [Self.modelNumberUUID, Self.manufacturerNameUUID]
            }
            peripheral.discoverCharacteristics(characteristics, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        let identifier = peripheral.identifier
        guard var session = currentSession(for: identifier) else { return }
        guard error == nil else {
            if isUUID(service.uuid, Self.batteryServiceUUID) {
                completeSession(for: identifier, succeeded: false)
                return
            }
            session.pendingCharacteristicDiscoveries = max(0, session.pendingCharacteristicDiscoveries - 1)
            sessions[identifier] = session
            finishSessionIfReady(identifier)
            return
        }

        let characteristics = service.characteristics ?? []
        var valuesToRead: [CBCharacteristic] = []
        if isUUID(service.uuid, Self.batteryServiceUUID) {
            guard let batteryCharacteristic = characteristics.first(where: {
                isUUID($0.uuid, Self.batteryLevelUUID)
            }) else {
                completeSession(for: identifier, succeeded: false)
                return
            }
            session.pendingReads.insert(Self.batteryLevelUUID)
            valuesToRead.append(batteryCharacteristic)
        } else if isUUID(service.uuid, Self.deviceInformationServiceUUID) {
            for characteristic in characteristics where
                isUUID(characteristic.uuid, Self.modelNumberUUID)
                    || isUUID(characteristic.uuid, Self.manufacturerNameUUID) {
                session.pendingReads.insert(characteristic.uuid)
                valuesToRead.append(characteristic)
            }
        }

        session.pendingCharacteristicDiscoveries = max(0, session.pendingCharacteristicDiscoveries - 1)
        sessions[identifier] = session
        for characteristic in valuesToRead {
            peripheral.readValue(for: characteristic)
        }
        finishSessionIfReady(identifier)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        let identifier = peripheral.identifier
        guard var session = currentSession(for: identifier),
              session.pendingReads.remove(characteristic.uuid) != nil else {
            return
        }

        if error == nil, let value = characteristic.value {
            if isUUID(characteristic.uuid, Self.batteryLevelUUID) {
                guard let batteryLevel = BluetoothLEBatteryParsing.percentage(value) else {
                    completeSession(for: identifier, succeeded: false)
                    return
                }
                session.batteryLevel = batteryLevel
            } else if isUUID(characteristic.uuid, Self.modelNumberUUID) {
                session.model = BluetoothLEBatteryParsing.deviceInfo(value)
            } else if isUUID(characteristic.uuid, Self.manufacturerNameUUID) {
                session.manufacturer = BluetoothLEBatteryParsing.deviceInfo(value)
            }
        }

        sessions[identifier] = session
        if BluetoothLEBatteryPublishGate.shouldPublish(
            batteryLevel: session.batteryLevel,
            modelReadPending: session.pendingReads.contains(Self.modelNumberUUID),
            sessionIsEnding: false
        ) {
            publishDeviceIfAvailable(session)
        }
        finishSessionIfReady(identifier)
    }

    private func ensureCentralManager() {
        guard centralManager == nil,
              CBManager.authorization == .allowedAlways else {
            return
        }

        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    private func scheduleAutomaticRefresh() {
        automaticRefreshTask?.cancel()
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

    private func startScanWindow(manual: Bool) {
        guard isRunning,
              !isScanning,
              let centralManager,
              centralManager.state == .poweredOn,
              policy.beginScan(at: Date(), manual: manual) else {
            return
        }

        candidatePeripherals.removeAll(keepingCapacity: true)
        candidateNames.removeAll(keepingCapacity: true)
        isScanning = true
        currentScanGeneration = policy.generation
        // The scan is unfiltered on purpose. `withServices` is applied by the
        // stack, not by this delegate: an advertisement that does not name the
        // service is never delivered at all, so a `180F`-filtered scan cannot
        // see a device that reveals its Battery Service only after the
        // connection — which is every iOS device, and every iPhone row the
        // nearby list is meant to show. CoreBluetooth therefore hands over
        // everything and `BluetoothLEBatteryAdvertisement` decides, in
        // `didDiscover`, which of those are worth a connection.
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scheduleAutomaticRefresh()

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
                  self.isScanning else {
                return
            }
            self.finishScanWindow()
        }
    }

    private func finishScanWindow() {
        scanWindowTask?.cancel()
        scanWindowTask = nil
        centralManager?.stopScan()
        isScanning = false
        startQueuedConnections()
        // The scan window is the full discovery budget. Only connections
        // started within it may continue afterward; the remaining candidates
        // are dropped instead of being connected serially as slots open.
        policy.discardQueuedCandidates()
        candidatePeripherals.removeAll(keepingCapacity: false)
        candidateNames.removeAll(keepingCapacity: false)
    }

    private func startQueuedConnections() {
        // Discovery and GATT work share the five-second window. A free slot can
        // start another queued candidate as soon as it opens without waiting
        // for the scanner to stop listening.
        guard isRunning, let centralManager, centralManager.state == .poweredOn else { return }
        let candidates = policy.startQueuedConnections()
        for identifier in candidates {
            guard let peripheral = candidatePeripherals.removeValue(forKey: identifier) else {
                policy.completeConnection(identifier, succeeded: false, at: Date())
                continue
            }

            var session = PeripheralSession(
                peripheral: peripheral,
                generation: policy.generation,
                advertisedName: candidateNames.removeValue(forKey: identifier) ?? peripheral.name,
                timeoutTask: nil
            )
            let generation = session.generation
            session.timeoutTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: BluetoothLEBatteryScanPolicy.connectionTimeout)
                } catch {
                    return
                }
                guard let self,
                      let current = self.currentSession(for: identifier),
                      current.generation == generation else {
                    return
                }
                self.completeSession(for: identifier, succeeded: current.batteryLevel != nil)
            }
            sessions[identifier] = session
            centralManager.connect(peripheral, options: nil)
        }
    }

    private func finishSessionIfReady(_ identifier: UUID) {
        guard let session = sessions[identifier],
              session.pendingCharacteristicDiscoveries == 0,
              session.pendingReads.isEmpty else {
            return
        }
        completeSession(for: identifier, succeeded: session.batteryLevel != nil)
    }

    private func completeSession(for identifier: UUID, succeeded: Bool) {
        guard let session = sessions.removeValue(forKey: identifier) else { return }
        // The session ending is the last chance to publish: a read that never
        // answered must not take the level that did with it.
        if BluetoothLEBatteryPublishGate.shouldPublish(
            batteryLevel: session.batteryLevel,
            modelReadPending: false,
            sessionIsEnding: true
        ) {
            publishDeviceIfAvailable(session)
        }
        session.timeoutTask?.cancel()
        session.peripheral.delegate = nil
        centralManager?.cancelPeripheralConnection(session.peripheral)
        candidatePeripherals.removeValue(forKey: identifier)
        candidateNames.removeValue(forKey: identifier)
        policy.completeConnection(identifier, succeeded: succeeded, at: Date())
        startQueuedConnections()
    }

    private func publishDeviceIfAvailable(_ session: PeripheralSession) {
        guard let batteryLevel = session.batteryLevel else { return }
        let now = Date()
        nearbyDevices = nearbyDevices.filter {
            now.timeIntervalSince($0.value.lastUpdated) <= BluetoothLEBatteryScanPolicy.resultLifetime
        }
        let name = session.advertisedName ?? session.peripheral.name ?? ""
        nearbyDevices[session.peripheral.identifier] = NearbyBluetoothBatteryDevice(
            id: session.peripheral.identifier,
            name: name,
            batteryLevel: batteryLevel,
            model: session.model,
            manufacturer: session.manufacturer,
            lastUpdated: now
        )
        onDevicesChanged?(nearbyDevices.values.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    private func currentSession(for identifier: UUID) -> PeripheralSession? {
        guard let session = sessions[identifier],
              policy.acceptsCallback(from: session.generation) else {
            return nil
        }
        return session
    }

    private func stopActiveWork(clearResults: Bool = false) {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        scanWindowTask?.cancel()
        scanWindowTask = nil
        centralManager?.stopScan()
        isScanning = false
        candidatePeripherals.removeAll(keepingCapacity: false)
        candidateNames.removeAll(keepingCapacity: false)

        let activeSessions = Array(sessions.values)
        sessions.removeAll(keepingCapacity: false)
        for session in activeSessions {
            session.timeoutTask?.cancel()
            session.peripheral.delegate = nil
            centralManager?.cancelPeripheralConnection(session.peripheral)
        }
        policy.stop()
        if clearResults {
            nearbyDevices.removeAll(keepingCapacity: false)
        }
    }

    private func isUUID(_ lhs: CBUUID, _ rhs: CBUUID) -> Bool {
        lhs.uuidString.caseInsensitiveCompare(rhs.uuidString) == .orderedSame
    }
}
