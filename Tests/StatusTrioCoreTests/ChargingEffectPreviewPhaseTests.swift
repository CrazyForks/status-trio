import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct ChargingEffectPreviewPhaseTests {
    @Test func liveChargePreviewUsesTheSharedClockPhase() throws {
        let clock = ChargingEffectClock(now: { Date(timeIntervalSince1970: 1_000) })
        let battery = BatteryStatus(
            rawPercentage: 62,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        defer { clock.stop() }
        let phase = try #require(clock.phase)

        #expect(StatusIconPreviewCard.livePhase(
            battery: battery,
            enabled: true,
            reduceMotion: false,
            phase: phase
        ) == phase)
    }

    @Test func liveChargePreviewHonorsSettingMotionAndChargingGates() {
        let phase = ChargingEffectPhase(step: 9, stepsPerCycle: 36, kind: .steady)
        let battery = BatteryStatus(
            rawPercentage: 62,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        let notCharging = BatteryStatus(
            rawPercentage: 62,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )

        #expect(StatusIconPreviewCard.livePhase(
            battery: battery,
            enabled: false,
            reduceMotion: false,
            phase: phase
        ) == nil)
        #expect(StatusIconPreviewCard.livePhase(
            battery: battery,
            enabled: true,
            reduceMotion: true,
            phase: phase
        ) == nil)
        #expect(StatusIconPreviewCard.livePhase(
            battery: notCharging,
            enabled: true,
            reduceMotion: false,
            phase: phase
        ) == nil)
    }
}
