import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BluetoothNearbyBatteryLifecycleTests: XCTestCase {
    func testScannerRequiresActiveControllerPopoverRequestAndAvailableBluetooth() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeController(scanner: scanner, monitor: monitor)

        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        XCTAssertEqual(scanner.startCount, 0, "a claim cannot start an inactive controller")

        controller.activate()
        monitor.emit(authorization: .allowed, state: .poweredOff)
        XCTAssertEqual(scanner.startCount, 0, "Bluetooth off must keep the scanner stopped")

        monitor.emit(authorization: .allowed, state: .poweredOn)
        XCTAssertEqual(scanner.startCount, 1)

        controller.deactivate()
    }

    func testSettingsDiscoveryStartsWithoutPopoverButViewClaimDoesNotAuthorizeReads() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeController(scanner: scanner, monitor: monitor)
        controller.activate()
        monitor.emit(authorization: .allowed, state: .poweredOn)

        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        XCTAssertEqual(scanner.startCount, 1, "settings discovery can run without a popover")
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "discovery does not grant reads")
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "a view claim cannot substitute for the popover claim")

        controller.deactivate()
    }

    func testReleasingPopoverStopsImmediatelyAndRejectsOldCallbacks() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        XCTAssertEqual(scanner.startCount, 1)

        let device = nearbyDevice(name: "Sensor", level: 52)
        scanner.publish([device])
        await Task.yield()
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty, "passive discovery results never become battery readings")

        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.releaseNearbyBLEDiscovery("settings")
        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertFalse(scanner.isRunning)

        var lateDevice = device
        lateDevice.batteryLevel = 91
        lateDevice.lastUpdated = Date().addingTimeInterval(1)
        let callbackFromStoppedScan = scanner.onDevicesChanged
        callbackFromStoppedScan?([lateDevice])
        await Task.yield()
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty, "nearby BLE callbacks never populate battery readings")

        controller.deactivate()
    }

    func testLeavingBluetoothSummaryStopsNearbyScanWhilePopoverRemainsOpen() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        let device = nearbyDevice(name: "Sensor", level: 52)
        scanner.publish([device])
        await Task.yield()

        controller.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.releaseNearbyBLEDiscovery("settings")

        XCTAssertTrue(controller.hasVisibleSurface, "the overall popover remains open")
        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertFalse(scanner.isRunning)
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty, "passive discovery never caches battery readings")
        controller.deactivate()
    }

    /// Turning off nearby discovery stops scanning; there is no BLE battery cache to retain.
    func testReleasingLastNearbyRequestClearsCacheAndStopsScanner() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        scanner.publish([nearbyDevice(name: "Scale", level: 0)])

        controller.configureNearbyBLEDevices(enabled: false, selectedIDs: [], hiddenIDs: [])

        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        controller.deactivate()
    }

    /// Reopening a panel may rediscover nearby devices, but cannot request BLE battery reads.
    func testReopeningThePanelNeverRetainsNearbyBLEBatteryReadings() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        let device = nearbyDevice(name: "Ling's iPhone", level: 31)
        scanner.publish([device])
        await Task.yield()
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)

        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.releaseNearbyBLEDiscovery("settings")

        XCTAssertEqual(scanner.stopCount, 1, "the radio still stops with the panel")
        XCTAssertFalse(scanner.isRunning)
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty, "no nearby BLE reading survives panel closure")
        controller.deactivate()
    }

    /// Bluetooth availability only controls discovery; it never exposes BLE battery readings.
    func testUnavailableBluetoothStopsScannerAndClearsNearbyResults() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        scanner.publish([nearbyDevice(name: "Sensor", level: 61)])

        monitor.emit(authorization: .allowed, state: .poweredOff)

        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        controller.deactivate()
    }

    func testDeactivateStopsScannerAndClearsNearbyResults() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        scanner.publish([nearbyDevice(name: "Sensor", level: 73)])

        controller.deactivate()

        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
    }

    func testDeactivateClearsReadingsButKeepsTheFeatureOptInForReopen() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        let device = nearbyDevice(name: "Sensor", level: 68)
        scanner.publish([device])
        await Task.yield()
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)

        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.deactivate()
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)

        controller.activate()
        monitor.emit(authorization: .allowed, state: .poweredOn)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)

        XCTAssertEqual(scanner.startCount, 2, "the still-enabled feature should restart on the next authorized popover")
        controller.deactivate()
    }

    func testDeinitWithoutDeactivateStopsNearbyScanner() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        var controller: BluetoothDeviceController? = makeController(scanner: scanner, monitor: monitor)
        controller?.activate()
        monitor.emit(authorization: .allowed, state: .poweredOn)
        controller?.configureNearbyBLEDevices(enabled: true, selectedIDs: [], hiddenIDs: [])
        controller?.requestNearbyBLEDiscovery("settings")
        controller?.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller?.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        XCTAssertTrue(scanner.isRunning)

        testController = nil
        controller = nil
        await waitUntil { scanner.stopCount == 1 }
    }

    func testManualRefreshUsesNearbyScannerSeparately() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let worker = NearbyBatteryPairedReaderSpy()
        let controller = makeController(scanner: scanner, monitor: monitor, worker: worker)
        controller.activate()
        monitor.emit(authorization: .allowed, state: .poweredOn)
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)

        controller.refreshFromUser()

        XCTAssertEqual(scanner.refreshCount, 1)
        XCTAssertGreaterThanOrEqual(worker.readCount, 1)
        controller.deactivate()
    }

    private func makeReadyController(
        scanner: NearbyBatteryScannerSpy,
        monitor: NearbyBatteryStateMonitorSpy,
    ) -> BluetoothDeviceController {
        let controller = makeController(scanner: scanner, monitor: monitor)
        controller.activate()
        monitor.emit(authorization: .allowed, state: .poweredOn)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        return controller
    }

    private func makeController(
        scanner: NearbyBatteryScannerSpy,
        monitor: NearbyBatteryStateMonitorSpy,
        worker: NearbyBatteryPairedReaderSpy = NearbyBatteryPairedReaderSpy(),
    ) -> BluetoothDeviceController {
        let controller = BluetoothDeviceController(
            worker: worker,
            stateMonitor: monitor,
            batteryReader: NearbyBatteryLevelReaderSpy(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            nearbyBatteryScanner: scanner
        )
        testController = controller
        return controller
    }

    private var testSelectedIDs: Set<UUID> = []
    private var testController: BluetoothDeviceController?

    private func nearbyDevice(name: String, level: Int) -> NearbyBluetoothBatteryDevice {
        let id = UUID()
        testSelectedIDs.insert(id)
        testController?.configureNearbyBLEDevices(enabled: true, selectedIDs: testSelectedIDs, hiddenIDs: [])
        testController?.setVisibleNearbyBLEDevices(testSelectedIDs, for: "panel")
        return NearbyBluetoothBatteryDevice(
            id: id,
            name: name,
            batteryLevel: level,
            model: nil,
            manufacturer: nil,
            lastUpdated: Date()
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "Timed out waiting for Nearby scanner state")
    }
}


@MainActor
final class NearbyBatteryScannerSpy: BluetoothLEBatteryScanning {
    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)?
    var onCandidatesChanged: (([NearbyBLEDeviceCandidate]) -> Void)?
    var onReadFailures: ((Set<UUID>) -> Void)?
    var onIsScanningChanged: ((Bool) -> Void)?
    private(set) var allowedReadDeviceIDs: Set<UUID> = []
    private(set) var isRunning = false
    private(set) var isScanning = false
    private(set) var startCount = 0
    private(set) var refreshCount = 0
    private(set) var stopCount = 0

    func setAllowedReadDeviceIDs(_ ids: Set<UUID>) {
        allowedReadDeviceIDs = ids
    }

    func start() {
        startCount += 1
        isRunning = true
    }

    func refresh() {
        refreshCount += 1
    }

    func stop() {
        stopCount += 1
        isRunning = false
        isScanning = false
    }

    func publish(_ devices: [NearbyBluetoothBatteryDevice]) {
        onDevicesChanged?(devices)
    }
}


@MainActor
private final class NearbyBatteryStateMonitorSpy: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    var authorization: BluetoothAuthorizationStatus = .allowed

    func start() {}
    func stop() {}

    func emit(authorization: BluetoothAuthorizationStatus, state: BluetoothManagerState) {
        self.authorization = authorization
        onStateChange?(authorization, state)
    }
}

private final class NearbyBatteryPairedReaderSpy: BluetoothPairedDeviceReading {
    private let lock = NSLock()
    private var storedReadCount = 0

    var readCount: Int { lock.withLock { storedReadCount } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock { storedReadCount += 1 }
        completion(.success([]))
    }
}

private final class NearbyBatteryLevelReaderSpy: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}
