import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct ChargingEffectTestModeTests {
    @Test func testModeUsesAChargingBatteryForIconAndClockButLeavesTheSnapshotUntouched() {
        let battery = BatteryStatus(
            rawPercentage: 46,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
        let original = MenuBarStatus(
            battery: battery,
            wifi: .placeholder,
            connection: .unknown,
            volume: MenuBarVolumeStatus(volume: .placeholder)
        )

        let animated = ChargingEffectTestMode.status(original, enabled: true)
        #expect(animated.battery.percentage == 46)
        #expect(animated.battery.isCharging)
        #expect(animated.battery.isConnectedToPower)
        #expect(!animated.battery.isCharged)
        #expect(animated.wifi == original.wifi)
        #expect(animated.volume == original.volume)
        #expect(!original.battery.isCharging)
        #expect(ChargingEffectTestMode.status(original, enabled: false) == original)
        #expect(ChargingEffectPolicy.shouldAnimate(
            battery: animated.battery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        ))
    }

    @Test func absentBatteryGetsAVisibleTestArcOnlyInTheDevBundle() {
        let simulated = ChargingEffectTestMode.battery(
            BatteryStatus(
                rawPercentage: nil,
                isPresent: false,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            enabled: true
        )
        #expect(simulated.isPresent)
        #expect(simulated.percentage == 62)
        #expect(ChargingEffectTestMode.isAvailable(bundleIdentifier: "com.lingsmbp.StatusTrio.dev.feature-charging-effects"))
        #expect(!ChargingEffectTestMode.isAvailable(bundleIdentifier: "com.lingsmbp.StatusTrio"))
    }

    @Test func testBatteryStartsAndStopsTheProductionClockWhenUnplugged() {
        let clock = ChargingEffectClock()
        let realBattery = BatteryStatus(
            rawPercentage: 46,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
        clock.update(
            battery: ChargingEffectTestMode.battery(realBattery, enabled: true),
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )
        #expect(clock.isRunning)
        #expect(clock.phase != nil)

        clock.update(battery: realBattery, enabled: true, reduceMotion: false, displayAsleep: false)
        #expect(!clock.isRunning)
        #expect(clock.phase == nil)
    }
}
