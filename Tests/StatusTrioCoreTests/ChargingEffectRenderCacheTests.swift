import Testing
@testable import StatusTrioCore

struct ChargingEffectRenderCacheTests {
    @Test func menuBarCacheInvalidatesForEachSteadyPhase() {
        var cache = StatusBarRenderCache()
        let first = menuBarKey(phase: .init(step: 2, stepsPerCycle: 36, kind: .steady))
        let second = menuBarKey(phase: .init(step: 3, stepsPerCycle: 36, kind: .steady))

        let rendersFirst = cache.shouldRender(first)
        let rendersSecond = cache.shouldRender(second)
        let suppressesRepeatedSecond = cache.shouldRender(second)
        #expect(rendersFirst)
        #expect(rendersSecond)
        #expect(suppressesRepeatedSecond == false)
    }

    @Test func nilMenuBarPhasePreservesStaticKeyDeduplication() {
        var cache = StatusBarRenderCache()
        let omittedPhase = menuBarKey()
        let explicitNilPhase = menuBarKey(phase: nil)

        let rendersStaticKey = cache.shouldRender(omittedPhase)
        let suppressesDuplicateStaticKey = cache.shouldRender(explicitNilPhase)
        #expect(omittedPhase == explicitNilPhase)
        #expect(rendersStaticKey)
        #expect(suppressesDuplicateStaticKey == false)
    }

    @Test func dockCacheIgnoresEverySteadyPhase() {
        var cache = DockIconRenderCache()
        let first = dockKey(phase: .init(step: 2, stepsPerCycle: 36, kind: .steady))
        let second = dockKey(phase: .init(step: 3, stepsPerCycle: 36, kind: .steady))

        let rendersSteadyKey = cache.shouldRender(first)
        let suppressesDifferentSteadyPhase = cache.shouldRender(second)
        #expect(first == second)
        #expect(rendersSteadyKey)
        #expect(suppressesDifferentSteadyPhase == false)
    }

    @Test func dockCacheRetainsPlugInBurstFrames() {
        let first = dockKey(phase: .init(step: 0, stepsPerCycle: 12, kind: .burst))
        let second = dockKey(phase: .init(step: 2, stepsPerCycle: 12, kind: .burst))

        #expect(first != second)
    }

    @Test func dockCacheRetainsLevelAdvanceBurstFrames() {
        let first = dockKey(phase: .init(step: 0, stepsPerCycle: 6, kind: .burst))
        let second = dockKey(phase: .init(step: 2, stepsPerCycle: 6, kind: .burst))

        #expect(first != second)
    }

    private func menuBarKey(phase: ChargingEffectPhase? = nil) -> StatusBarRenderKey {
        StatusBarRenderKey(
            status: .placeholder,
            iconSize: 28,
            options: .standard,
            connectionOptions: .standard,
            appearanceName: "darkAqua",
            phase: phase
        )
    }

    private func dockKey(phase: ChargingEffectPhase? = nil) -> DockIconRenderKey {
        DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark,
            phase: phase
        )
    }
}
