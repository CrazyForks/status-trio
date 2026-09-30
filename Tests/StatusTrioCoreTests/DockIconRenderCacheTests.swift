import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct DockIconRenderCacheTests {
    @Test func commitsOnlySuccessfulSceneAndSurfaceIdentity() {
        var cache = DockIconRenderCache()
        let baseScene = makeScene(rssi: -50)
        let dark = DockIconRenderKey(scene: baseScene, backgroundStyle: .dark, pixelLength: 512)
        let light = DockIconRenderKey(scene: baseScene, backgroundStyle: .light, pixelLength: 512)
        let preview = DockIconRenderKey(scene: baseScene, backgroundStyle: .dark, pixelLength: 256)
        let changedScene = DockIconRenderKey(
            scene: makeScene(rssi: -80), backgroundStyle: .dark, pixelLength: 512
        )

        #expect(cache.needsRender(dark))
        #expect(cache.needsRender(dark))
        cache.recordSuccessfulRender(dark)
        #expect(cache.needsRender(dark) == false)
        #expect(cache.needsRender(light))
        #expect(cache.needsRender(preview))
        #expect(cache.needsRender(changedScene))
    }

    @Test func resetAllowsTheSameSceneToRenderAgain() {
        var cache = DockIconRenderCache()
        let key = DockIconRenderKey(scene: makeScene(), backgroundStyle: .dark, pixelLength: 512)
        cache.recordSuccessfulRender(key)

        cache.reset()

        #expect(cache.needsRender(key))
    }

    @Test func imageCacheReusesAndEvictsLeastRecentlyUsedRaster() {
        let cache = DockIconImageCache(limit: 2)
        let first = key(rssi: -50)
        let second = key(rssi: -65)
        let third = key(rssi: -80)
        let firstImage = NSImage(size: NSSize(width: 512, height: 512))
        let secondImage = NSImage(size: NSSize(width: 512, height: 512))
        let thirdImage = NSImage(size: NSSize(width: 512, height: 512))

        cache.store(firstImage, for: first)
        cache.store(secondImage, for: second)
        #expect(cache.image(for: first) === firstImage)
        cache.store(thirdImage, for: third)

        #expect(cache.image(for: second) == nil)
        #expect(cache.image(for: first) === firstImage)
        #expect(cache.image(for: third) === thirdImage)
    }

    private func key(rssi: Int = -50) -> DockIconRenderKey {
        DockIconRenderKey(scene: makeScene(rssi: rssi), backgroundStyle: .dark, pixelLength: 512)
    }

    private func makeScene(rssi: Int = -50) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: PresentationFixtures.snapshot(rssi: rssi),
                audioIcon: nil
            ),
            configuration: .standard
        )
    }
}
