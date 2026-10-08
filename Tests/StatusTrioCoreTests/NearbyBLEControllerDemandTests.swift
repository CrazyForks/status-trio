import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class NearbyBLEControllerDemandTests: XCTestCase {
    func testBackgroundScannerStopsDuringSystemSleepAndResumesOnWake() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let selected = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [selected], hiddenIDs: [])
        controller.setNearbyBLEBackgroundRefresh(enabled: true, selectedIDs: [selected], interval: .seconds(120))
        XCTAssertTrue(scanner.isRunning)

        controller.setSystemSleeping(true)
        XCTAssertFalse(scanner.isRunning)

        controller.setSystemSleeping(false)
        XCTAssertTrue(scanner.isRunning)
        controller.deactivate()
    }

    func testGlobalBatteryOffRevokesPermitWithoutRemovingConsentOrSettingsDiscovery() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])
        scanner.publish([device(id)])
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [], batteryLevelsEnabled: false)
        await Task.yield()
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty, "queued callback is rejected after global off")
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertTrue(scanner.isRunning)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])
        controller.configureNearbyBLEDevices(enabled: false, knownIDs: [id], hiddenIDs: [])
        XCTAssertFalse(scanner.isRunning)
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        controller.deactivate()
    }

    func testSettingsDiscoveryTokenDoesNotStartScannerWithoutPopoverOrBackgroundPreference() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])

        controller.requestNearbyBLEDiscovery("settings")

        XCTAssertFalse(scanner.isRunning)
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "Settings does not request ongoing visible-row reads")
        controller.releaseNearbyBLEDiscovery("settings")
        XCTAssertFalse(scanner.isRunning)
        controller.deactivate()
    }

    func testAnyVisibleBLEUUIDAuthorizesAndAcceptsBatteryReads() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let selected = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [selected], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([selected], for: "panel")

        XCTAssertEqual(scanner.allowedReadDeviceIDs, [selected])
        scanner.publish([device(selected)])
        await Task.yield()
        XCTAssertEqual(controller.nearbyBatteryDevices.map(\.id), [selected])
        controller.setVisibleNearbyBLEDevices([], for: "panel")
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        controller.deactivate()
    }

    func testSelectedVisibleRowsNeverReceiveNearbyBLEReadPermission() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "popover without the Bluetooth summary is insufficient")
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])

        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [id])
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        controller.deactivate()
    }

    func testPanelCloseStopsBLEScannerWhenBackgroundRefreshIsOff() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])

        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertFalse(scanner.isRunning, "Settings must not keep BLE discovery active")
        controller.releaseNearbyBLEDiscovery("settings")
        XCTAssertFalse(scanner.isRunning)
        controller.deactivate()
    }

    func testGeneralBatteryToggleOffStopsBLEScannerWithoutBackgroundOwner() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        controller.requestNearbyBLEDiscovery("settings")
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])

        // The panel's general battery-level setting removes the read demand.
        controller.setVisibleNearbyBLEDevices([], for: "panel")

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertTrue(scanner.isRunning, "open popover still owns bounded discovery")
        controller.releaseNearbyBLEDiscovery("settings")
        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        XCTAssertFalse(scanner.isRunning)
        controller.deactivate()
    }

    func testHidingRowsNeverGrantsNearbyBLEReadPermission() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let visible = UUID()
        let offLimit = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [visible, offLimit], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([visible], for: "panel")
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [visible])

        controller.configureNearbyBLEDevices(
            enabled: true,
            knownIDs: [visible, offLimit],
            hiddenIDs: [offLimit]
        )

        XCTAssertEqual(scanner.allowedReadDeviceIDs, [visible])

        controller.configureNearbyBLEDevices(
            enabled: true,
            knownIDs: [visible],
            hiddenIDs: []
        )
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [visible], "deselecting off-limit B preserves visible A's permit")
        controller.deactivate()
    }

    func testFeatureOffAndBluetoothUnavailableKeepNearbyBLEReadsDisabled() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])

        controller.configureNearbyBLEDevices(enabled: false, knownIDs: [id], hiddenIDs: [])
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertFalse(scanner.isRunning)

        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        XCTAssertEqual(scanner.allowedReadDeviceIDs, [id])
        monitor.emit(.poweredOff)
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertFalse(scanner.isRunning)
        controller.deactivate()
    }

    func testNearbyBLECallbacksAcceptOnlyCurrentlyVisibleUUIDs() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let selected = UUID()
        let stranger = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [selected], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([selected], for: "panel")
        scanner.publish([device(selected), device(stranger)])
        await Task.yield()

        XCTAssertEqual(controller.nearbyBatteryDevices.map(\.id), [selected])
        controller.setVisibleNearbyBLEDevices([], for: "panel")
        scanner.publish([device(selected)])
        await Task.yield()
        XCTAssertEqual(controller.nearbyBatteryDevices.map(\.id), [selected], "late callbacks cannot add a stranger after viewport release")
        controller.deactivate()
    }

    func testHideAndUnhideRejectsOldQueuedCallbackButAcceptsNewCallback() async {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        let id = UUID()
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        controller.setVisibleNearbyBLEDevices([id], for: "panel")

        scanner.publish([device(id)])
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [id])
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [id], hiddenIDs: [])
        await Task.yield()

        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        scanner.publish([device(id)])
        await Task.yield()
        XCTAssertEqual(controller.nearbyBatteryDevices.map(\.id), [id])
        controller.deactivate()
    }

    func testSettingsDiscoveryNeverAddsUUIDToReadPermit() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        let candidate = NearbyBLEDeviceCandidate(id: UUID(), name: "Broadcast", vendor: .apple, lastSeen: Date())

        scanner.onCandidatesChanged?([candidate])

        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty)
        XCTAssertTrue(controller.nearbyBatteryDevices.isEmpty)
        controller.deactivate()
    }

    func testSettingsDiscoveryInitialReadsOnlyNewNonHiddenCandidatesAndRevokesOnBatteryOff() {
        let (controller, scanner, monitor) = makeController()
        controller.activate()
        monitor.emit(.poweredOn)
        controller.configureNearbyBLEDevices(enabled: true, knownIDs: [], hiddenIDs: [])
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)

        let candidateID = UUID(uuidString: "00000000-0000-0000-0000-000000000121")!
        let freshID = UUID(uuidString: "00000000-0000-0000-0000-000000000122")!
        let hiddenID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let expiredID = UUID(uuidString: "00000000-0000-0000-0000-000000000124")!
        let now = Date()
        scanner.discoveredCandidates = [
            .init(id: candidateID, name: "New phone", vendor: .apple, lastSeen: now),
            .init(id: freshID, name: "Fresh phone", vendor: .apple, lastSeen: now),
            .init(id: hiddenID, name: "Hidden phone", vendor: .apple, lastSeen: now),
            .init(id: expiredID, name: "Expired phone", vendor: .apple, lastSeen: now)
        ]
        controller.configureNearbyBLEDevices(
            enabled: true,
            knownIDs: [freshID, expiredID, hiddenID],
            hiddenIDs: [hiddenID],
            batteryLevelsEnabled: true,
            listVisible: true,
            persistedSelections: [NearbyBLEDeviceSelection(
                id: freshID, name: "Fresh phone", vendor: .apple, model: nil,
                batteryLevel: 77, batteryLastUpdated: now
            ), NearbyBLEDeviceSelection(
                id: expiredID, name: "Expired phone", vendor: .apple, model: nil,
                batteryLevel: 48, batteryLastUpdated: now.addingTimeInterval(-1201)
            )]
        )
        scanner.onCandidatesChanged?(scanner.discoveredCandidates)

        XCTAssertEqual(scanner.initialReadDeviceIDs, [candidateID, expiredID])
        XCTAssertTrue(scanner.allowedReadDeviceIDs.isEmpty, "unrendered rows are not visible permits")

        controller.setNearbyBLEBackgroundRefresh(enabled: true, selectedIDs: [freshID], interval: .seconds(120))
        XCTAssertTrue(scanner.allowedReadDeviceIDs.contains(freshID), "background cadence refreshes even a still-fresh verified UUID")

        controller.configureNearbyBLEDevices(
            enabled: true,
            knownIDs: [freshID, hiddenID],
            hiddenIDs: [hiddenID],
            batteryLevelsEnabled: false,
            listVisible: true,
            persistedSelections: [NearbyBLEDeviceSelection(
                id: freshID, name: "Fresh phone", vendor: .apple, model: nil,
                batteryLevel: 77, batteryLastUpdated: now
            )]
        )
        XCTAssertTrue(scanner.initialReadDeviceIDs.isEmpty)
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
    private(set) var initialReadDeviceIDs: Set<UUID> = []
    var discoveredCandidates: [NearbyBLEDeviceCandidate] = []

    func setAllowedReadDeviceIDs(_ ids: Set<UUID>) { allowedReadDeviceIDs = ids }
    func setInitialReadCandidateIDs(_ ids: Set<UUID>) { initialReadDeviceIDs = ids }
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
