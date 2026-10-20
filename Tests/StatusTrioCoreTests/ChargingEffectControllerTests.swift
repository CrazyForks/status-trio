import AppKit
import Testing
@testable import StatusTrioCore

@Suite(.serialized)
@MainActor
struct ChargingEffectControllerTests {
    @Test func menuBarTestModeDoesNotChangeDockArtworkOrRealBattery() throws {
        let battery = dockTestBattery(46, charging: false)
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            initialBattery: battery
        )
        harness.controller.start()
        defer {
            harness.controller.stop()
            harness.cleanUp()
        }
        let originalImage = try #require(harness.application.applicationIconImage)
        let originalRenderCount = harness.log.renderCount

        harness.settings.setChargingEffectTestEnabled(true)

        #expect(harness.store.snapshot.battery == battery)
        #expect(harness.log.lastScene != nil)
        #expect(harness.log.renderCount == originalRenderCount)
        #expect(harness.application.applicationIconImage === originalImage)
    }

    @Test func batteryLevelChangesStillUpdateStaticDockArtwork() async throws {
        let snapshotScheduler = ManualIconPresentationScheduler()
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            initialBattery: dockTestBattery(60, charging: true),
            snapshotScheduler: snapshotScheduler
        )
        harness.controller.start()
        defer {
            harness.controller.stop()
            harness.cleanUp()
        }

        let increasedBattery = dockTestBattery(61, charging: true)
        let initialRenderCount = harness.log.renderCount
        harness.publishBattery(increasedBattery)
        let didReachStore = try await waitForStoreBattery(increasedBattery, in: harness)
        try #require(didReachStore, "The battery update must reach the status store.")
        try #require(
            snapshotScheduler.hasPendingAction,
            "The battery update must schedule the presentation debounce."
        )
        snapshotScheduler.runScheduled()
        #expect(harness.iconPresentation.output.scene.outerRing?.segments.first?.progress == 0.61)
        harness.controller.flushPendingPresentationForTesting()

        #expect(harness.log.renderCount > initialRenderCount)
        #expect(harness.log.lastScene != nil)
    }

    private func waitForStoreBattery(
        _ battery: BatteryStatus,
        in harness: AppIconControllerHarness
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if harness.store.snapshot.battery == battery { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func dockTestBattery(_ percentage: Int, charging: Bool) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: charging,
            isLowPowerMode: false,
            isConnectedToPower: charging
        )
    }
}
