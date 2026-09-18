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

        controller.requestBatteryLevels("test")
        controller.activate()
        await waitUntil { batteryReader.readCount == 1 && controller.batteryLevels.isEmpty == false }

        #expect(controller.batteryLevels.count == 1)
        #expect(controller.batteryLevels[BluetoothBatteryReader.normalizedAddress("ac9085c29c1f")]?.summary == "L 85% · R 80% · Case 70%")
        #expect(batteryReader.readCount == 1)

        controller.releaseBatteryLevels("test")
        #expect(controller.batteryLevels.isEmpty)
        #expect(batteryReader.readCount == 1)

        controller.deactivate()
        controller.requestBatteryLevels("test")
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

        controller.requestBatteryLevels("test")
        controller.activate()
        await waitUntil { batteryReader.readCount == 1 }

        controller.releaseBatteryLevels("test")
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

    /// The summary only reports AirPods levels, so a non-AirPods session must
    /// stay on the cached connected-device read.
    @Test func batteryReadsStayOffWhenNoAirPodsAreConnected() async {
        let deviceReader = BluetoothPairedDeviceReaderStub(result: .success([
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "MX Master 3", kind: .peripheral, isConnected: true)
        ]))
        let batteryReader = BluetoothBatteryReaderStub(result: [:])
        let controller = BluetoothDeviceController(
            worker: deviceReader,
            stateMonitor: BluetoothBatteryStateMonitorStub(),
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        controller.releaseBatteryLevels("test")
        controller.activate()
        await waitUntil { deviceReader.readCount == 1 }

        #expect(batteryReader.readCount == 0)
        #expect(controller.batteryLevels.isEmpty)
    }

    /// A connected AirPods entry is what enables the level read, and leaving
    /// the summary turns it back off.
    @Test func batteryReadsFollowConnectedAirPods() async {
        let deviceReader = BluetoothPairedDeviceReaderStub(result: .success([
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true)
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
        let controller = BluetoothDeviceController(
            worker: deviceReader,
            stateMonitor: BluetoothBatteryStateMonitorStub(),
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        controller.requestBatteryLevels("test")
        controller.activate()
        await waitUntil { !controller.batteryLevels.isEmpty }

        #expect(batteryReader.readCount == 1)
        #expect(controller.batteryLevels[BluetoothBatteryReader.normalizedAddress("ac9085c29c1f")]?.summary == "L 85% · R 80% · Case 70%")

        controller.releaseBatteryLevels("test")

        #expect(controller.batteryLevels.isEmpty)
        #expect(batteryReader.readCount == 1)
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

/// The summary row and the detail page both need battery levels, and SwiftUI
/// may run their hooks in either order. A claim count makes the outcome the
/// same either way; the boolean it replaced let the last writer win, which
/// left the detail page showing "Unavailable" for every device.
@MainActor
struct BluetoothBatteryLevelClaimTests {
    private func makeController() -> (BluetoothDeviceController, BluetoothBatteryReaderStub) {
        let batteryReader = BluetoothBatteryReaderStub(result: [
            BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): BluetoothBatteryLevel(
                deviceAddress: "AC:90:85:C2:9C:1F", main: nil, left: 85, right: 80, caseLevel: 70)
        ])
        let controller = BluetoothDeviceController(
            worker: BluetoothPairedDeviceReaderStub(result: .success([
                BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true)
            ])),
            stateMonitor: BluetoothBatteryStateMonitorStub(),
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        return (controller, batteryReader)
    }

    /// Incoming appears first, then the outgoing releases: the claim must hold.
    @Test func detailClaimSurvivesTheSummaryReleasingAfterwards() {
        let (controller, _) = makeController()
        controller.activate()

        controller.requestBatteryLevels("summary")
        controller.requestBatteryLevels("detail")
        controller.releaseBatteryLevels("summary")

        #expect(controller.isBatteryLevelsRequested)
        controller.deactivate()
    }

    /// The outgoing releases first, then the incoming claims: same outcome.
    @Test func detailClaimSurvivesTheSummaryReleasingFirst() {
        let (controller, _) = makeController()
        controller.activate()

        controller.requestBatteryLevels("summary")
        controller.releaseBatteryLevels("summary")
        controller.requestBatteryLevels("detail")

        #expect(controller.isBatteryLevelsRequested)
        controller.deactivate()
    }

    /// Two summary appearances (returning from the detail page) must not leak
    /// a claim that outlives the view.
    @Test func repeatedClaimsReleaseOnTheSingleOwner() {
        let (controller, _) = makeController()
        controller.activate()

        controller.requestBatteryLevels("summary")
        controller.requestBatteryLevels("summary")
        controller.releaseBatteryLevels("summary")

        #expect(controller.isBatteryLevelsRequested == false)
        controller.deactivate()
    }

    /// Closing the popover drops every outstanding claim.
    @Test func deactivatingReleasesEveryClaim() {
        let (controller, _) = makeController()
        controller.activate()
        controller.requestBatteryLevels("summary")
        controller.requestBatteryLevels("detail")

        controller.deactivate()

        #expect(controller.isBatteryLevelsRequested == false)
    }
}
