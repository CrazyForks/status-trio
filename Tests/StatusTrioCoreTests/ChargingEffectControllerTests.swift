import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct ChargingEffectControllerTests {
    @Test func steadyClockPhasesDoNotRedrawTheVisibleDockTile() async throws {
        let time = ChargingEffectTestTime()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let battery = chargingBattery(60)
        clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        time.setElapsed(0.6)
        clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        let clockStarted = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        #expect(clockStarted)
        #expect(clock.phase?.kind == .steady)

        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            chargingEffectClock: clock,
            initialBattery: battery
        )
        harness.controller.start()
        harness.log.reset()
        defer {
            clock.stop()
            sleeper.releaseAll()
            harness.controller.stop()
            harness.cleanUp()
        }

        for elapsed in [0.65, 0.7, 0.75, 0.8] {
            time.setElapsed(elapsed)
            clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        }

        #expect(harness.log.renderCount == 0)
        await stopClock(clock, sleeper: sleeper)
    }

    @Test func hiddenDockDoesNotRenderPlugInBurstPhases() async throws {
        let time = ChargingEffectTestTime()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let battery = chargingBattery(60)
        let harness = try AppIconControllerHarness(
            initialPlacement: .menuBar,
            chargingEffectClock: clock,
            initialBattery: battery
        )
        harness.controller.start()
        harness.log.reset()
        defer {
            clock.stop()
            sleeper.releaseAll()
            harness.controller.stop()
            harness.cleanUp()
        }

        clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        let clockStarted = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        #expect(clockStarted)
        for frame in 1...11 {
            time.setElapsed(Double(frame) * 0.05)
            clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        }

        #expect(harness.log.renderCount == 0)
        await stopClock(clock, sleeper: sleeper)
    }

    @Test func plugInBurstRendersExactlySixDockFramesAtTenHertz() async throws {
        let time = ChargingEffectTestTime()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let battery = chargingBattery(60)
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            chargingEffectClock: clock,
            initialBattery: battery
        )
        harness.controller.start()
        harness.log.reset()
        defer {
            clock.stop()
            sleeper.releaseAll()
            harness.controller.stop()
            harness.cleanUp()
        }

        clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        let clockStarted = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        #expect(clockStarted)
        for frame in 1...11 {
            time.setElapsed(Double(frame) * 0.05)
            clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        }
        time.setElapsed(0.6)
        clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)

        let dockBurstFrames = harness.log.renderedPhases.compactMap { $0 }
        #expect(dockBurstFrames.count == 6)
        #expect(dockBurstFrames.map(\.step) == [0, 2, 4, 6, 8, 10])
        #expect(dockBurstFrames.allSatisfy { $0.kind == .burst && $0.stepsPerCycle == 12 })
        #expect(harness.log.renderCount == 6)
        await stopClock(clock, sleeper: sleeper)
    }

    @Test func enablingAfterDisabledLaunchRendersTheDockPlugInBurstWithTheCurrentOption() async throws {
        let time = ChargingEffectTestTime()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let unpluggedBattery = chargingBattery(60, charging: false)
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            chargingEffectClock: clock,
            initialBattery: unpluggedBattery,
            initialShowsChargingEffect: false
        )
        harness.controller.start()
        harness.log.reset()
        defer {
            clock.stop()
            sleeper.releaseAll()
            harness.controller.stop()
            harness.cleanUp()
        }

        clock.update(
            battery: unpluggedBattery,
            enabled: false,
            reduceMotion: false,
            displayAsleep: false
        )
        harness.settings.showsChargingEffect = true
        clock.update(
            battery: unpluggedBattery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )

        let pluggedBattery = chargingBattery(60)
        harness.publishBattery(pluggedBattery)
        await waitForBattery(pluggedBattery, in: harness)
        clock.update(
            battery: pluggedBattery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )
        let clockStarted = await sleeper.waitForCallCount(1, timeout: .seconds(1))

        #expect(clockStarted)
        #expect(harness.log.renderedPhases.compactMap { $0 }.first?.kind == .burst)
        #expect(harness.log.batteryOptions.last?.showsChargingEffect == true)

        time.setElapsed(0.6)
        clock.update(
            battery: pluggedBattery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )
        let increasedBattery = chargingBattery(61)
        harness.publishBattery(increasedBattery)
        await waitForBattery(increasedBattery, in: harness)
        clock.update(
            battery: increasedBattery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )

        #expect(clock.dockPhase?.stepsPerCycle == 6)
        #expect(harness.log.renderedPhases.compactMap { $0 }.last?.stepsPerCycle == 6)
        #expect(harness.log.batteryOptions.last?.showsChargingEffect == true)
        await stopClock(clock, sleeper: sleeper)
    }

    @Test func levelAdvanceBurstRendersExactlyThreeFramesThenRestoresStaticIcon() async throws {
        let time = ChargingEffectTestTime()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let initialBattery = chargingBattery(60)
        clock.update(
            battery: initialBattery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )
        time.setElapsed(0.6)
        clock.update(
            battery: initialBattery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )
        let clockStarted = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        #expect(clockStarted)
        #expect(clock.phase?.kind == .steady)

        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            chargingEffectClock: clock,
            initialBattery: initialBattery
        )
        harness.controller.start()
        let staticImage = try #require(harness.application.applicationIconImage)
        harness.log.reset()
        defer {
            clock.stop()
            sleeper.releaseAll()
            harness.controller.stop()
            harness.cleanUp()
        }

        let increasedBattery = chargingBattery(61)
        harness.publishBattery(increasedBattery)
        await waitForBattery(increasedBattery, in: harness)
        clock.update(
            battery: increasedBattery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )
        #expect(clock.phase?.kind == .steady, "Level changes must not interrupt the menu-bar timeline.")
        #expect(clock.dockPhase?.kind == .burst)
        #expect(clock.dockPhase?.stepsPerCycle == 6)
        for frame in 1...4 {
            time.setElapsed(0.6 + Double(frame) * 0.05)
            clock.update(
                battery: increasedBattery,
                enabled: true,
                reduceMotion: false,
                displayAsleep: false
            )
            #expect(clock.dockPhase?.step == frame)
            #expect(clock.phase?.kind == .steady)
        }
        time.setElapsed(0.9)
        clock.update(
            battery: increasedBattery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )
        #expect(clock.phase?.kind == .steady)
        #expect(clock.dockPhase == nil)

        let dockBurstFrames = harness.log.renderedPhases.compactMap { $0 }
        #expect(dockBurstFrames.count == 3)
        #expect(dockBurstFrames.map(\.step) == [0, 2, 4])
        #expect(dockBurstFrames.allSatisfy { $0.kind == .burst && $0.stepsPerCycle == 6 })
        let restoredPhase = try #require(harness.log.renderedPhases.last)
        #expect(restoredPhase == nil, "The static Dock icon is refreshed after the level change.")
        #expect(harness.log.renderCount == 4, "Three animation frames are followed by one static restore render.")
        #expect(harness.application.applicationIconImage !== staticImage)
        await stopClock(clock, sleeper: sleeper)
    }

    @Test(arguments: StopCondition.allCases)
    func stoppingAnEventBurstRestoresTheStaticDockImage(_ condition: StopCondition) async throws {
        let time = ChargingEffectTestTime()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let battery = chargingBattery(60)
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            chargingEffectClock: clock,
            initialBattery: battery
        )
        harness.controller.start()
        let staticImage = try #require(harness.application.applicationIconImage)
        harness.log.reset()
        defer {
            clock.stop()
            sleeper.releaseAll()
            harness.controller.stop()
            harness.cleanUp()
        }

        clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        let clockStarted = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        #expect(clockStarted)
        let animatedImage = try #require(harness.application.applicationIconImage)
        #expect(animatedImage !== staticImage)

        switch condition {
        case .settingDisabled:
            clock.update(battery: battery, enabled: false, reduceMotion: false, displayAsleep: false)
        case .unplugged:
            clock.update(
                battery: chargingBattery(60, charging: false),
                enabled: true,
                reduceMotion: false,
                displayAsleep: false
            )
        case .displayAsleep:
            clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: true)
        }

        #expect(harness.application.applicationIconImage === staticImage)
        clock.stop()
        #expect(harness.application.applicationIconImage === staticImage)
        #expect(harness.log.renderCount == 1)
        await stopClock(clock, sleeper: sleeper)
    }

    private func waitForBattery(
        _ expected: BatteryStatus,
        in harness: AppIconControllerHarness
    ) async {
        let deadline = Date().addingTimeInterval(1)
        while harness.store.snapshot.battery != expected, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(harness.store.snapshot.battery == expected)
    }

    private func makeClock(
        time: ChargingEffectTestTime,
        sleeper: ManualEventSleeper
    ) -> ChargingEffectClock {
        ChargingEffectClock(
            now: { time.now },
            sleep: { await sleeper.sleep($0) }
        )
    }

    private func chargingBattery(_ percentage: Int, charging: Bool = true) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: charging,
            isLowPowerMode: false,
            isConnectedToPower: charging
        )
    }

    private func stopClock(
        _ clock: ChargingEffectClock,
        sleeper: ManualEventSleeper
    ) async {
        let sleepCount = sleeper.callCount
        clock.stop()
        sleeper.releaseAll()
        if sleepCount > 0 {
            await sleeper.waitForCompletionCount(sleepCount)
        }
    }
}

enum StopCondition: CaseIterable, Sendable {
    case settingDisabled
    case unplugged
    case displayAsleep
}

@MainActor
private final class ChargingEffectTestTime {
    private let start = Date(timeIntervalSince1970: 2_000)
    private(set) var elapsed: TimeInterval = 0

    var now: Date { start.addingTimeInterval(elapsed) }

    func setElapsed(_ value: TimeInterval) {
        elapsed = value
    }
}
