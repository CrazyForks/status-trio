import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct BluetoothBatteryControllerTests {
    @Test func batteryReadsOnlyWhileEnabledAndControllerIsActive() async {
        let deviceReader = BluetoothPairedDeviceReaderStub(result: .success([
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods", kind: .audio, isConnected: true)
        ]))
        let batteryReader = BluetoothBatteryReaderStub(result: [
            BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): BluetoothBatteryLevel(
                deviceAddress: "AC:90:85:C2:9C:1F",
                main: nil,
                left: 85,
                right: 80,
                caseLevel: 70
            )
        ])
        let monitor = BluetoothBatteryStateMonitorStub()
        let controller = BluetoothDeviceController(
            worker: deviceReader,
            stateMonitor: monitor,
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        controller.setBatteryLevelsEnabled(true)
        controller.activate()
        await waitUntil { batteryReader.readCount == 1 && controller.batteryLevels.isEmpty == false }

        #expect(controller.batteryLevels.count == 1)
        #expect(controller.batteryLevels[BluetoothBatteryReader.normalizedAddress("ac9085c29c1f")]?.summary == "L 85% · R 80% · Case 70%")
        #expect(batteryReader.readCount == 1)

        controller.setBatteryLevelsEnabled(false)
        #expect(controller.batteryLevels.isEmpty)
        #expect(batteryReader.readCount == 1)

        controller.deactivate()
        controller.setBatteryLevelsEnabled(true)
        await Task.yield()

        #expect(batteryReader.readCount == 1)
    }

    @Test func disablingBatteryLevelsDiscardsAnInFlightResult() async {
        let deviceReader = BluetoothPairedDeviceReaderStub(result: .success([]))
        let batteryReader = BlockingBluetoothBatteryReader()
        let monitor = BluetoothBatteryStateMonitorStub()
        let controller = BluetoothDeviceController(
            worker: deviceReader,
            stateMonitor: monitor,
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        controller.setBatteryLevelsEnabled(true)
        controller.activate()
        await waitUntil { batteryReader.readCount == 1 }

        controller.setBatteryLevelsEnabled(false)
        batteryReader.finish(with: [
            BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): BluetoothBatteryLevel(
                deviceAddress: "AC:90:85:C2:9C:1F",
                main: 90,
                left: nil,
                right: nil,
                caseLevel: nil
            )
        ])
        await Task.yield()

        #expect(controller.batteryLevels.isEmpty)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for Bluetooth battery state")
    }
}

private final class BluetoothPairedDeviceReaderStub: BluetoothPairedDeviceReading {
    private let result: BluetoothWorkerResult
    private(set) var readCount = 0

    init(result: BluetoothWorkerResult) {
        self.result = result
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        readCount += 1
        completion(result)
    }
}

private final class BluetoothBatteryReaderStub: BluetoothBatteryReading {
    let result: [String: BluetoothBatteryLevel]
    private(set) var readCount = 0

    init(result: [String: BluetoothBatteryLevel]) {
        self.result = result
    }

    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]) -> Void) {
        readCount += 1
        completion(result)
    }
}

private final class BlockingBluetoothBatteryReader: BluetoothBatteryReading {
    private(set) var readCount = 0
    private var completion: (@Sendable ([String: BluetoothBatteryLevel]) -> Void)?

    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]) -> Void) {
        readCount += 1
        self.completion = completion
    }

    func finish(with levels: [String: BluetoothBatteryLevel]) {
        completion?(levels)
    }
}

@MainActor
private final class BluetoothBatteryStateMonitorStub: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() {
        onStateChange?(authorization, .poweredOn)
    }

    func stop() {}
}
