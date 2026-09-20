import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BluetoothPermissionTimingTests: XCTestCase {
    func testOpeningPopoverExposesBluetoothAuthorizationWithoutStartingMonitor() {
        let stateMonitor = BluetoothStateMonitorSpy(authorization: .notDetermined)
        let bluetoothController = BluetoothDeviceController(
            stateMonitor: stateMonitor,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let store = SystemStatusStore(
            batteryMonitor: EmptyBatteryMonitorForBluetoothTiming(),
            wifiMonitor: EmptyWiFiMonitorForBluetoothTiming(),
            volumeMonitor: EmptyVolumeMonitorForBluetoothTiming(),
            bluetoothDevices: bluetoothController
        )

        store.setPopoverVisible(true)

        XCTAssertEqual(bluetoothController.availability, .authorizationNotDetermined)
        XCTAssertEqual(stateMonitor.startCount, 0)
    }

    func testRequestingBluetoothAuthorizationStartsStateMonitor() {
        let stateMonitor = BluetoothStateMonitorSpy(authorization: .notDetermined)
        let bluetoothController = BluetoothDeviceController(
            stateMonitor: stateMonitor,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let store = SystemStatusStore(
            batteryMonitor: EmptyBatteryMonitorForBluetoothTiming(),
            wifiMonitor: EmptyWiFiMonitorForBluetoothTiming(),
            volumeMonitor: EmptyVolumeMonitorForBluetoothTiming(),
            bluetoothDevices: bluetoothController
        )

        store.requestBluetoothAuthorization()

        XCTAssertEqual(stateMonitor.startCount, 1)
    }

    func testBluetoothSettingControlsStateMonitorLifecycle() {
        let stateMonitor = BluetoothStateMonitorSpy(authorization: .notDetermined)
        let bluetoothController = BluetoothDeviceController(
            stateMonitor: stateMonitor,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let store = SystemStatusStore(
            batteryMonitor: EmptyBatteryMonitorForBluetoothTiming(),
            wifiMonitor: EmptyWiFiMonitorForBluetoothTiming(),
            volumeMonitor: EmptyVolumeMonitorForBluetoothTiming(),
            bluetoothDevices: bluetoothController
        )

        store.setBluetoothEnabled(true)
        XCTAssertEqual(stateMonitor.startCount, 1)

        store.setBluetoothEnabled(false)
        XCTAssertEqual(stateMonitor.stopCount, 1)
    }

    func testEnabledBluetoothMonitorSurvivesPopupClose() {
        let stateMonitor = BluetoothStateMonitorSpy(authorization: .notDetermined)
        let bluetoothController = BluetoothDeviceController(
            stateMonitor: stateMonitor,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let store = SystemStatusStore(
            batteryMonitor: EmptyBatteryMonitorForBluetoothTiming(),
            wifiMonitor: EmptyWiFiMonitorForBluetoothTiming(),
            volumeMonitor: EmptyVolumeMonitorForBluetoothTiming(),
            bluetoothDevices: bluetoothController
        )

        store.setBluetoothEnabled(true)
        XCTAssertEqual(stateMonitor.startCount, 1)

        store.setPopoverVisible(true)
        store.setPopoverVisible(false)
        store.closePopoverDetails()

        XCTAssertEqual(stateMonitor.stopCount, 0)
        XCTAssertFalse(store.hasOpenPopoverPanel)

        store.setBluetoothEnabled(false)
        XCTAssertEqual(stateMonitor.stopCount, 1)
    }

    /// An authorized app has nothing left to ask for, so opening the popover
    /// refreshes the connected device names the summary reports. This is what
    /// makes the row show device names instead of "open details" after launch.
    func testOpeningThePopoverActivatesBluetoothWhenAlreadyAuthorized() {
        let stateMonitor = BluetoothStateMonitorSpy(authorization: .allowed)
        let bluetoothController = BluetoothDeviceController(
            stateMonitor: stateMonitor,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let store = SystemStatusStore(
            batteryMonitor: EmptyBatteryMonitorForBluetoothTiming(),
            wifiMonitor: EmptyWiFiMonitorForBluetoothTiming(),
            volumeMonitor: EmptyVolumeMonitorForBluetoothTiming(),
            bluetoothDevices: bluetoothController
        )

        store.setPopoverVisible(true)
        XCTAssertEqual(stateMonitor.startCount, 1)
        // Monitoring survives the popover, so its device names stay warm.
        XCTAssertTrue(bluetoothController.isActive)

        store.closePopoverDetails()
        XCTAssertEqual(stateMonitor.stopCount, 0)
    }

    /// Permission is only ever requested by the user's tap, never by the
    /// popover appearing.
    func testOpeningThePopoverKeepsUnauthorizedBluetoothIdle() {
        let expected: [(BluetoothAuthorizationStatus, BluetoothAvailability)] = [
            (.denied, .authorizationDenied),
            (.restricted, .authorizationRestricted)
        ]
        for (authorization, availability) in expected {
            let stateMonitor = BluetoothStateMonitorSpy(authorization: authorization)
            let bluetoothController = BluetoothDeviceController(
                stateMonitor: stateMonitor,
                notificationCenter: NotificationCenter(),
                workspaceNotificationCenter: NotificationCenter()
            )
            let store = SystemStatusStore(
                batteryMonitor: EmptyBatteryMonitorForBluetoothTiming(),
                wifiMonitor: EmptyWiFiMonitorForBluetoothTiming(),
                volumeMonitor: EmptyVolumeMonitorForBluetoothTiming(),
                bluetoothDevices: bluetoothController
            )

            store.setPopoverVisible(true)

            XCTAssertEqual(stateMonitor.startCount, 0)
            XCTAssertFalse(bluetoothController.isActive)
            XCTAssertEqual(bluetoothController.availability, availability)
            store.stop()
        }
    }

    /// Holding a surface only allows polling; it never starts the state monitor,
    /// so the row cannot raise the permission prompt on its own.
    func testHoldingASurfaceDoesNotStartTheStateMonitor() {
        let stateMonitor = BluetoothStateMonitorSpy(authorization: .notDetermined)
        let bluetoothController = BluetoothDeviceController(
            stateMonitor: stateMonitor,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        bluetoothController.holdVisibleSurface("bluetooth.summary")

        XCTAssertEqual(stateMonitor.startCount, 0)
        XCTAssertFalse(bluetoothController.isActive)
        XCTAssertFalse(bluetoothController.isSafetyNetPolling)
    }

    /// The popover is what holds the Bluetooth surface, and closing it must stop
    /// the poll while the already-running state monitor stays warm: the summary
    /// row still reports device state the next time it opens, and starting the
    /// monitor is what raises the permission prompt.
    func testClosingThePopoverStopsTheSafetyNetPoll() {
        let stateMonitor = BluetoothStateMonitorSpy(authorization: .allowed)
        let bluetoothController = BluetoothDeviceController(
            worker: PermissionTimingBluetoothReader(),
            stateMonitor: stateMonitor,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let store = SystemStatusStore(
            batteryMonitor: EmptyBatteryMonitorForBluetoothTiming(),
            wifiMonitor: EmptyWiFiMonitorForBluetoothTiming(),
            volumeMonitor: EmptyVolumeMonitorForBluetoothTiming(),
            bluetoothDevices: bluetoothController
        )

        store.setPopoverVisible(true)
        XCTAssertTrue(bluetoothController.hasVisibleSurface)

        // The adapter reports ready: the poll may now run, and it is the surface
        // claim that allows it.
        stateMonitor.emit(authorization: .allowed, managerState: .poweredOn)
        XCTAssertTrue(bluetoothController.isSafetyNetPolling)

        store.setPopoverVisible(false)
        XCTAssertFalse(bluetoothController.hasVisibleSurface)
        XCTAssertFalse(bluetoothController.isSafetyNetPolling)

        store.setPopoverVisible(true)
        stateMonitor.emit(authorization: .allowed, managerState: .poweredOn)
        XCTAssertTrue(bluetoothController.isSafetyNetPolling)
        store.closePopoverDetails()
        XCTAssertFalse(bluetoothController.hasVisibleSurface)
        XCTAssertFalse(bluetoothController.isSafetyNetPolling)
        XCTAssertEqual(stateMonitor.stopCount, 0, "the state monitor is not what the popover owns")
    }
}

@MainActor
private final class BluetoothStateMonitorSpy: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    let authorization: BluetoothAuthorizationStatus

    init(authorization: BluetoothAuthorizationStatus = .notDetermined) {
        self.authorization = authorization
    }

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func emit(authorization: BluetoothAuthorizationStatus, managerState: BluetoothManagerState) {
        onStateChange?(authorization, managerState)
    }
}

/// The default worker runs `/usr/sbin/system_profiler`; a unit test that makes
/// the adapter report ready must not.
private final class PermissionTimingBluetoothReader: BluetoothPairedDeviceReading {
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(.success([]))
    }
}

@MainActor
private final class EmptyBatteryMonitorForBluetoothTiming: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { continuation in
        continuation.finish()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class EmptyWiFiMonitorForBluetoothTiming: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { continuation in
        continuation.finish()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() {}
}

@MainActor
private final class EmptyVolumeMonitorForBluetoothTiming: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { continuation in
        continuation.finish()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
