import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class NearbyBLEControllerDemandTests: XCTestCase {
    func testSettingsDiscoveryRunsWithoutPopoverAndNeverGrantsReadAccess() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [id], hiddenIDs: [])

        controller.requestNearbyBLEDiscovery("settings")

        XCTAssertTrue(scanner.isRunning)
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        controller.releaseNearbyBLEDiscovery("settings")
        XCTAssertFalse(scanner.isRunning)
        controller.deactivate()
    }

    func testSelectedNearbyAppleRowNeverAuthorizesOrAcceptsBLEBatteryReads() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let selected = UUID()
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [selected], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([selected], for: "panel")

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        scanner.publish([device(selected)])
        await Task.yield()
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        XCTAssertTrue(controller.nearbyBLEReadFailures.isEmpty)
        controller.deactivate()
    }

    func testSelectedVisibleRowsNeverReceiveNearbyBLEReadPermission() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [id], hiddenIDs: [])
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "popover without the Bluetooth summary is insufficient")
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "selection and panel visibility never authorize BLE battery reads")

        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [id], hiddenIDs: [id])
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        controller.deactivate()
    }

    func testPanelCloseLeavesOnlySettingsDiscoveryRunning() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [id], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "selection and panel visibility never authorize BLE battery reads")

        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertTrue(scanner.isRunning, "settings still owns a discovery-only request")
        controller.releaseNearbyBLEDiscovery("settings")
        XCTAssertFalse(scanner.isRunning)
        controller.deactivate()
    }

    func testGeneralBatteryToggleOffDoesNotStopSettingsDiscoveryOrEnableReads() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [id], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "selection and panel visibility never authorize BLE battery reads")

        // The panel's general battery-level setting removes the read demand.
        controller.setVisibleNearbyBLEDevices([], for: "panel")

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertTrue(scanner.isRunning, "Settings discovery is independent of panel battery visibility")
        controller.releaseNearbyBLEDiscovery("settings")
        XCTAssertFalse(scanner.isRunning)
        controller.deactivate()
    }

    func testHidingRowsNeverGrantsNearbyBLEReadPermission() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let visible = UUID()
        let offLimit = UUID()
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [visible, offLimit], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([visible], for: "panel")
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "selection and panel visibility never authorize BLE battery reads")

        controller.configureNearbyBLEDevices(
            enabled: true,
            selectedIDs: [visible, offLimit],
            hiddenIDs: [offLimit]
        )

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "selection and panel visibility never authorize BLE battery reads")

        controller.configureNearbyBLEDevices(
            enabled: true,
            selectedIDs: [visible],
            hiddenIDs: []
        )
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "deselecting off-limit B does not authorize BLE battery reads")
        controller.deactivate()
    }

    func testFeatureOffAndBluetoothUnavailableKeepNearbyBLEReadsDisabled() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [id], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "selection and panel visibility never authorize BLE battery reads")

        controller.configureNearbyBLEDevices(enabled: false, selectedIDs: [id], hiddenIDs: [])
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertFalse(scanner.isRunning)

        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [id], hiddenIDs: [])
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "selection and panel visibility never authorize BLE battery reads")
        monitor.emit(.poweredOff)
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertFalse(scanner.isRunning)
        controller.deactivate()
    }

    func testNearbyBLECallbacksNeverAddBatteryReadings() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let selected = UUID()
        let stranger = UUID()
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [selected], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([selected], for: "panel")
        scanner.publish([device(selected), device(stranger)])
        await Task.yield()

        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty, "passive BLE results never populate battery readings")
        controller.setVisibleNearbyBLEDevices([], for: "panel")
        scanner.publish([device(selected)])
        await Task.yield()
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty, "callbacks cannot create readings even for selected visible devices")
        controller.deactivate()
    }

    func testDeselectAndReselectNeverAcceptsNearbyBLEBatteryCallbacks() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [id], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")

        scanner.publish([device(id)])
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [], hiddenIDs: [])
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [id], hiddenIDs: [])
        await Task.yield()

        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        scanner.publish([device(id)])
        await Task.yield()
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty, "passive BLE results never populate battery readings")
        controller.deactivate()
    }

    func testCandidateDiscoveryNeverAddsUUIDToReadPermit() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        let candidate = NearbyBLEDeviceCandidate(id: UUID(), name: "Broadcast", vendor: .apple, lastSeen: Date())

        scanner.onCandidatesChanged?([candidate])

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        controller.deactivate()
    }

    private func makeController() -> (BluetoothDeviceController, DemandScannerSpy, DemandStateMonitorSpy) {
        let scanner = DemandScannerSpy()
        let monitor = DemandStateMonitorSpy()
        let controller = BluetoothDeviceController(
            stateMonitor: monitor,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            nearbyBatteryScanner: scanner
        )
        return (controller, scanner, monitor)
    }

    private func device(_ id: UUID) -> NearbyBluetoothBatteryDevice {
        NearbyBluetoothBatteryDevice(
            id: id, name: "Device", batteryLevel: 42, model: nil, manufacturer: nil, lastUpdated: Date()
        )
    }
}

@MainActor
private final class DemandScannerSpy: BluetoothLEBatteryScanning {
    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)?
    var onCandidatesChanged: (([NearbyBLEDeviceCandidate]) -> Void)?
    var onReadFailures: ((Set<UUID>) -> Void)?
    var onIsScanningChanged: ((Bool) -> Void)?
    private(set) var isRunning = false
    private(set) var isScanning = false
    private(set) var allowedReadDeviceIDs: Set<UUID> = []

    func setAllowedReadDeviceIDs(_ ids: Set<UUID>) { allowedReadDeviceIDs = ids }
    func start() { isRunning = true }
    func refresh() {}
    func stop() { isRunning = false; isScanning = false }
    func publish(_ devices: [NearbyBluetoothBatteryDevice]) { onDevicesChanged?(devices) }
}

@MainActor
private final class DemandStateMonitorSpy: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed
    func start() { onStateChange?(.allowed, .poweredOff) }
    func stop() {}
    func emit(_ state: BluetoothManagerState) { onStateChange?(.allowed, state) }
}
