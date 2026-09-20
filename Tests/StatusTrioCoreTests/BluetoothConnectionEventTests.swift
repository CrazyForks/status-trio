import Foundation
import XCTest
@testable import StatusTrioCore

/// A device connecting or disconnecting is the event that matters, and it
/// arrives once per device: several at a time must collapse into one read.
@MainActor
final class BluetoothConnectionEventTests: XCTestCase {
    func testConnectEventsCoalesceIntoOneDebouncedRefresh() async {
        let reader = CountingBluetoothDeviceReader()
        let events = FakeBluetoothConnectionEventMonitor(isAvailable: true)
        let sleeper = ManualEventSleeper()
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: ConnectionEventStateMonitor(),
            batteryReader: ConnectionEventBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            connectionEvents: events,
            connectionEventDebounceInterval: .milliseconds(750),
            connectionEventDebounceSleep: { duration in await sleeper.sleep(duration) }
        )

        controller.activate()
        await waitUntil { reader.readCount == 1 }
        // The event registration lives and dies with the popover that shows
        // device state, so the popover claim comes first: a view token only
        // narrows the poll and never starts it (rider 1 of the lifetime task).
        controller.holdVisibleSurface("bluetooth.popover")
        XCTAssertTrue(events.isRunning)
        XCTAssertTrue(controller.isMonitoringConnectionEvents)

        events.emit()
        events.emit()
        events.emit()
        _ = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertEqual(sleeper.durations.first, .milliseconds(750))
        XCTAssertEqual(reader.readCount, 1, "the debounce must hold the read until it fires")

        sleeper.releaseAll()
        await waitUntil { reader.readCount == 2 }

        controller.deactivate()
        XCTAssertFalse(events.isRunning)
    }

    /// The event source is optional: without it the safety-net poll is the only
    /// source, and holding a surface must not crash or spin.
    func testAnUnavailableEventSourceLeavesTheSafetyNetAsTheOnlySource() async {
        let reader = CountingBluetoothDeviceReader()
        let events = FakeBluetoothConnectionEventMonitor(isAvailable: false)
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: ConnectionEventStateMonitor(),
            batteryReader: ConnectionEventBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            connectionEvents: events
        )

        controller.activate()
        await waitUntil { reader.readCount == 1 }
        controller.holdVisibleSurface("bluetooth.popover")

        XCTAssertFalse(controller.isMonitoringConnectionEvents)
        XCTAssertTrue(controller.isSafetyNetPolling)

        controller.deactivate()
        XCTAssertFalse(controller.isSafetyNetPolling)
    }

    /// Without an injected source the controller must not reach for the system
    /// on its own; the app wires the IOBluetooth monitor through `makeStore`.
    func testADefaultControllerHasNoSystemEventSource() {
        let controller = BluetoothDeviceController(
            stateMonitor: ConnectionEventStateMonitor(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        XCTAssertFalse(controller.hasConnectionEventSource)
    }

    /// Production must hand the controller a real event source: the default is
    /// `nil` so unit tests never touch the system's Bluetooth service.
    func testAppEnvironmentWiresTheIOBluetoothEventSource() {
        let store = AppEnvironment.makeStore(
            batteryMonitor: ConnectionEventBatteryMonitor(),
            wifiMonitor: ConnectionEventWiFiMonitor(),
            volumeMonitor: ConnectionEventVolumeMonitor()
        )
        XCTAssertTrue(store.bluetoothDevices.hasConnectionEventSource)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the Bluetooth controller")
    }
}

private final class CountingBluetoothDeviceReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var readCount: Int { lock.withLock { count } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock { count += 1 }
        completion(.success([
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true)
        ]))
    }
}

private final class ConnectionEventBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]) -> Void) {
        completion([:])
    }
}

@MainActor
private final class ConnectionEventStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() { onStateChange?(.allowed, .poweredOn) }
    func stop() {}
}

private final class FakeBluetoothConnectionEventMonitor: BluetoothConnectionEventMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private let isAvailable: Bool
    private var handler: (@Sendable () -> Void)?
    private var running = false

    init(isAvailable: Bool) {
        self.isAvailable = isAvailable
    }

    var isRunning: Bool { lock.withLock { running } }

    @discardableResult
    func start(handler: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock {
            self.handler = handler
            running = isAvailable
            return isAvailable
        }
    }

    func stop() {
        lock.withLock {
            handler = nil
            running = false
        }
    }

    func emit() {
        let handler = lock.withLock { self.handler }
        handler?()
    }
}

@MainActor
private final class ConnectionEventBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class ConnectionEventWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() {}
}

@MainActor
private final class ConnectionEventVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
