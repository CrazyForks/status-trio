import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BluetoothPermissionTimingTests: XCTestCase {
    func testBluetoothStartsOnlyWhenDetailsPanelIsActivated() {
        let stateMonitor = BluetoothStateMonitorSpy()
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

        store.activateBluetoothPanel()
        XCTAssertEqual(stateMonitor.startCount, 1)
    }
}

@MainActor
private final class BluetoothStateMonitorSpy: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    private(set) var startCount = 0

    func start() {
        startCount += 1
    }

    func stop() {}
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
