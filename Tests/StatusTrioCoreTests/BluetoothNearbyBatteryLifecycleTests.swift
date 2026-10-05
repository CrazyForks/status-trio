import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BluetoothNearbyBatteryLifecycleTests: XCTestCase {
    func testScannerRequiresActiveControllerPopoverRequestAndAvailableBluetooth() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeController(scanner: scanner, monitor: monitor)

        controller.requestNearbyBatteryDevices("settings")
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

    func testRequestAndViewClaimAloneDoNotStartScanner() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeController(scanner: scanner, monitor: monitor)
        controller.activate()
        monitor.emit(authorization: .allowed, state: .poweredOn)

        controller.requestNearbyBatteryDevices("settings")
        XCTAssertEqual(scanner.startCount, 0, "a request without a visible popover must not scan")
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        XCTAssertEqual(scanner.startCount, 0, "a view claim cannot substitute for the popover claim")

        controller.deactivate()
    }

    func testReleasingPopoverStopsImmediatelyAndRejectsOldCallbacks() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.requestNearbyBatteryDevices("settings")
        XCTAssertEqual(scanner.startCount, 1)

        let device = nearbyDevice(name: "Sensor", level: 52)
        scanner.publish([device])
        await waitUntil { controller.nearbyBatteryDevices == [device] }
        XCTAssertEqual(controller.nearbyBatteryDevices, [device])

        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertFalse(scanner.isRunning)

        var lateDevice = device
        lateDevice.batteryLevel = 91
        lateDevice.lastUpdated = Date().addingTimeInterval(1)
        let callbackFromStoppedScan = scanner.onDevicesChanged
        callbackFromStoppedScan?([lateDevice])
        await Task.yield()
        XCTAssertEqual(controller.nearbyBatteryDevices, [device], "a callback from the stopped generation must be ignored")

        controller.deactivate()
    }

    func testLeavingBluetoothSummaryStopsNearbyScanWhilePopoverRemainsOpen() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.requestNearbyBatteryDevices("settings")
        let device = nearbyDevice(name: "Sensor", level: 52)
        scanner.publish([device])
        await waitUntil { controller.nearbyBatteryDevices == [device] }

        controller.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)

        XCTAssertTrue(controller.hasVisibleSurface, "the overall popover remains open")
        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertFalse(scanner.isRunning)
        XCTAssertEqual(controller.nearbyBatteryDevices, [device], "fresh cache remains available if the summary is reopened")
        controller.deactivate()
    }

    /// Switching the feature off is the one release that also drops what the
    /// scan read: the surface is no longer entitled to it.
    func testReleasingLastNearbyRequestClearsCacheAndStopsScanner() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.requestNearbyBatteryDevices("settings")
        scanner.publish([nearbyDevice(name: "Scale", level: 0)])

        controller.releaseNearbyBatteryDevices("settings")

        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        controller.deactivate()
    }

    /// Closing the panel is not switching the feature off. The reading is the
    /// only thing that can draw an iPhone row — the report has no entry for the
    /// phone at all — so dropping it here made every reopen wait out a scan, a
    /// connect and a GATT read before the row could exist, while the paired rows
    /// appeared at once off a report that survives the close.
    func testReopeningThePanelKeepsTheLastReadingInsteadOfRescanningFromScratch() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.requestNearbyBatteryDevices("settings")
        let device = nearbyDevice(name: "Ling's iPhone", level: 31)
        scanner.publish([device])
        await waitUntil { controller.nearbyBatteryDevices == [device] }

        controller.releaseNearbyBatteryDevices("settings", keepingResults: true)

        XCTAssertEqual(scanner.stopCount, 1, "the radio still stops with the panel")
        XCTAssertFalse(scanner.isRunning)
        XCTAssertEqual(
            controller.nearbyBatteryDevices,
            [device],
            "the reading outlives the panel for its own lifetime"
        )
        controller.deactivate()
    }

    /// Kept is not kept forever: the cache's lifetime still takes it, so a panel
    /// left shut does not leave a reading behind.
    func testAReadingKeptForAReopenStillExpiresOnItsOwnLifetime() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(
            scanner: scanner,
            monitor: monitor,
            cacheLifetime: 0.1
        )
        controller.requestNearbyBatteryDevices("settings")
        scanner.publish([nearbyDevice(name: "Ling's iPhone", level: 31)])
        await waitUntil { controller.nearbyBatteryDevices.count == 1 }

        controller.releaseNearbyBatteryDevices("settings", keepingResults: true)

        await waitUntil(timeout: .seconds(1)) { controller.nearbyBatteryDevices.isEmpty }
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        controller.deactivate()
    }

    func testUnavailableBluetoothStopsScannerAndClearsNearbyResults() {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.requestNearbyBatteryDevices("settings")
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
        controller.requestNearbyBatteryDevices("settings")
        scanner.publish([nearbyDevice(name: "Sensor", level: 73)])

        controller.deactivate()

        XCTAssertEqual(scanner.stopCount, 1)
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
    }

    func testDeactivateClearsReadingsButKeepsTheFeatureOptInForReopen() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor)
        controller.requestNearbyBatteryDevices("settings")
        let device = nearbyDevice(name: "Sensor", level: 68)
        scanner.publish([device])
        await waitUntil { controller.nearbyBatteryDevices == [device] }

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
        controller?.requestNearbyBatteryDevices("settings")
        controller?.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller?.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        XCTAssertTrue(scanner.isRunning)

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
        controller.requestNearbyBatteryDevices("settings")
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)

        controller.refreshFromUser()

        XCTAssertEqual(scanner.refreshCount, 1)
        XCTAssertGreaterThanOrEqual(worker.readCount, 1)
        controller.deactivate()
    }

    func testNearbyResultsExpireFromTheInMemoryCache() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(
            scanner: scanner,
            monitor: monitor,
            cacheLifetime: 0.1
        )
        controller.requestNearbyBatteryDevices("settings")
        scanner.publish([nearbyDevice(name: "Sensor", level: 41)])
        await waitUntil { controller.nearbyBatteryDevices.count == 1 }
        XCTAssertEqual(controller.nearbyBatteryDevices.count, 1)

        await waitUntil(timeout: .seconds(1)) { controller.nearbyBatteryDevices.isEmpty }

        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        controller.deactivate()
    }

    func testPartialScanRefreshPreservesOtherFreshCachedDevices() async {
        let scanner = NearbyBatteryScannerSpy()
        let monitor = NearbyBatteryStateMonitorSpy()
        let controller = makeReadyController(scanner: scanner, monitor: monitor, cacheLifetime: 1.5)
        controller.requestNearbyBatteryDevices("settings")

        let first = nearbyDevice(name: "Sensor A", level: 40)
        var second = nearbyDevice(name: "Sensor B", level: 55)
        second.lastUpdated = Date().addingTimeInterval(-0.75)
        scanner.publish([first, second])
        await waitUntil { controller.nearbyBatteryDevices.count == 2 }

        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)

        var refreshedFirst = first
        refreshedFirst.batteryLevel = 70
        refreshedFirst.lastUpdated = Date()
        scanner.publish([refreshedFirst])
        await waitUntil {
            controller.nearbyBatteryDevices.contains { $0.id == first.id && $0.batteryLevel == 70 }
        }

        XCTAssertEqual(Set(controller.nearbyBatteryDevices.map(\.id)), Set([first.id, second.id]))
        XCTAssertEqual(
            controller.nearbyBatteryDevices.first { $0.id == second.id }?.batteryLevel,
            second.batteryLevel,
            "a partial scan must retain another still-fresh cached reading"
        )

        await waitUntil(timeout: .seconds(2)) {
            controller.nearbyBatteryDevices.count == 1
                && controller.nearbyBatteryDevices.first?.id == first.id
                && controller.nearbyBatteryDevices.first?.batteryLevel == 70
        }
        XCTAssertEqual(
            controller.nearbyBatteryDevices.map(\.id),
            [first.id],
            "the retained reading expires on its own timestamp while the refreshed row stays visible"
        )
        controller.deactivate()
    }

    private func makeReadyController(
        scanner: NearbyBatteryScannerSpy,
        monitor: NearbyBatteryStateMonitorSpy,
        cacheLifetime: TimeInterval = 120
    ) -> BluetoothDeviceController {
        let controller = makeController(scanner: scanner, monitor: monitor, cacheLifetime: cacheLifetime)
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
        cacheLifetime: TimeInterval = 120
    ) -> BluetoothDeviceController {
        BluetoothDeviceController(
            worker: worker,
            stateMonitor: monitor,
            batteryReader: NearbyBatteryLevelReaderSpy(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            nearbyBatteryScanner: scanner,
            nearbyBatteryCacheLifetime: cacheLifetime
        )
    }

    private func nearbyDevice(name: String, level: Int) -> NearbyBluetoothBatteryDevice {
        NearbyBluetoothBatteryDevice(
            id: UUID(),
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
