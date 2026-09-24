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

    @Test func dockCacheDeduplicatesStaticState() {
        var cache = DockIconRenderCache()
        let first = dockKey()
        let second = dockKey()

        let rendersFirst = cache.shouldRender(first)
        let suppressesDuplicate = cache.shouldRender(second)
        #expect(rendersFirst)
        #expect(!suppressesDuplicate)
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

    private func dockKey() -> DockIconRenderKey {
        DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark
        )
    }
}
