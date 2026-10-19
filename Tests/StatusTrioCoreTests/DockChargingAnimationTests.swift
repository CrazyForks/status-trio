import AppKit
import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct DockChargingAnimationClockTests {
    @Test func dockSurfaceStartsTheSameClockWithoutADuplicateTick() async {
        let time = ManualDockChargingDate()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let battery = BatteryStatus(
            rawPercentage: 61,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )

        clock.update(
            battery: battery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false,
            menuBarVisible: false
        )
        #expect(!clock.isRunning)

        clock.setDockAnimationActive(true)
        clock.setDockAnimationActive(true)
        #expect(clock.isRunning)
        // The hidden-menu-bar update already recorded this charge, so claiming
        // the surface resumes steady instead of replaying the plug-in burst.
        #expect(clock.phase?.kind == .steady)
        await sleeper.waitForCallCount(1)
        #expect(sleeper.callCount == 1)

        clock.setDockAnimationActive(false)
        #expect(!clock.isRunning)
        #expect(clock.phase == nil)
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(1)
    }

    @Test func bothSurfacesShareOneTickAndReleasingOneKeepsTheClockAlive() async {
        let time = ManualDockChargingDate()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let battery = BatteryStatus(
            rawPercentage: 61,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )

        clock.update(
            battery: battery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )
        clock.setDockAnimationActive(true)
        await sleeper.waitForCallCount(1)

        clock.update(
            battery: battery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false,
            menuBarVisible: false
        )
        #expect(clock.isRunning)
        #expect(sleeper.callCount == 1)

        clock.setDockAnimationActive(false)
        #expect(!clock.isRunning)
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(1)
    }

    @Test func reducedMotionAndSleepStopADockOnlyClock() async {
        let time = ManualDockChargingDate()
        let sleeper = ManualEventSleeper()
        let clock = makeClock(time: time, sleeper: sleeper)
        let battery = BatteryStatus(
            rawPercentage: 61,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        clock.update(
            battery: battery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: false,
            menuBarVisible: false
        )
        clock.setDockAnimationActive(true)
        await sleeper.waitForCallCount(1)

        clock.update(
            battery: battery,
            enabled: true,
            reduceMotion: true,
            displayAsleep: false,
            menuBarVisible: false
        )
        #expect(!clock.isRunning)
        clock.update(
            battery: battery,
            enabled: true,
            reduceMotion: false,
            displayAsleep: true,
            menuBarVisible: false
        )
        #expect(!clock.isRunning)
        sleeper.releaseAll()
    }

    private func makeClock(
        time: ManualDockChargingDate,
        sleeper: ManualEventSleeper
    ) -> ChargingEffectClock {
        ChargingEffectClock(
            now: { time.now },
            sleep: { await sleeper.sleep($0) }
        )
    }
}

@MainActor
struct DockChargingFrameCacheTests {
    @Test func buildsThirtySixFramesOnceAndReusesThemAcrossTicks() {
        let cache = DockChargingFrameCache()
        let key = makeKey()
        var renderedSteps: [Int] = []
        var frames: [CGImage] = []

        let first = cache.image(for: steadyPhase(4), key: key) { phase in
            renderedSteps.append(phase.step)
            let image = frameImage()
            frames.append(image)
            return image
        }

        #expect(renderedSteps == Array(0..<36))
        #expect(first === frames[4])

        let second = cache.image(for: steadyPhase(5), key: key) { _ in
            Issue.record("A cached frame must not be rasterized twice.")
            return nil
        }
        #expect(second === frames[5])
        #expect(cache.rebuildCount == 1)
        #expect(cache.rasterizedFrameCount == 36)
    }

    @Test func keepsTheBoostedHeartbeatVariantAndDropsOldScenes() {
        let cache = DockChargingFrameCache()
        let key = makeKey()
        var renders = 0
        let render: (ChargingEffectPhase) -> CGImage? = { _ in
            renders += 1
            return frameImage()
        }

        _ = cache.image(for: steadyPhase(0), key: key, renderFrame: render)
        _ = cache.image(for: steadyPhase(0, multiplier: 1.35), key: key, renderFrame: render)
        #expect(renders == 72)
        #expect(cache.variantCount == 2)

        // A new scene retires the oldest set instead of growing without bound.
        let changedKey = makeKey(scalar: 0.8)
        _ = cache.image(for: steadyPhase(0), key: changedKey, renderFrame: render)
        #expect(renders == 108)
        #expect(cache.variantCount == 2)
        #expect(cache.residentByteCount > 0)
    }

    @Test func burstAndFailedSetsDoNotEnterTheCache() {
        let cache = DockChargingFrameCache()
        let key = makeKey()
        var renders = 0
        let burst = ChargingEffectPhase(step: 0, stepsPerCycle: 12, kind: .burst)
        #expect(cache.image(for: burst, key: key) { _ in
            renders += 1
            return frameImage()
        } == nil)
        #expect(renders == 0)

        let failed = cache.image(for: steadyPhase(0), key: key) { _ in nil }
        #expect(failed == nil)
        #expect(cache.needsFrames(for: steadyPhase(1), key: key) == false)

        cache.reset()
        #expect(cache.needsFrames(for: steadyPhase(1), key: key))
    }

    /// A 512-px reference costs about 18 MiB per set, so the byte ceiling must
    /// keep only the newest one instead of holding both heartbeat variants.
    /// (A single set is always kept: a frame set is indivisible.)
    @Test func keepsOnlyOneSetWhenBothWouldExceedTheByteCeiling() {
        let cache = DockChargingFrameCache()
        let key = makeKey(pixelLength: 512)
        var renders = 0
        let render: (ChargingEffectPhase) -> CGImage? = { _ in
            renders += 1
            return self.bigFrameImage()
        }

        _ = cache.image(for: steadyPhase(0), key: key, renderFrame: render)
        let firstSetBytes = cache.residentByteCount
        #expect(firstSetBytes > DockChargingFrameCache.maximumResidentBytes / 2)

        _ = cache.image(for: steadyPhase(0, multiplier: 1.35), key: key, renderFrame: render)

        #expect(renders == 72)
        #expect(cache.variantCount == 1)
        #expect(cache.residentByteCount == firstSetBytes)
    }

    private func makeKey(scalar: Double = 0.5, pixelLength: Int = 512) -> DockIconRenderKey {
        DockIconRenderKey(
            scene: chargingScene(scalar: scalar),
            backgroundStyle: .dark,
            pixelLength: pixelLength
        )
    }

    private func chargingScene(scalar: Double) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: StatusSnapshot(
                    battery: BatteryStatus(
                        rawPercentage: 62,
                        isPresent: true,
                        isCharging: true,
                        isLowPowerMode: false,
                        isConnectedToPower: true
                    ),
                    wifi: WiFiStatus(state: .connected, rssi: -50),
                    connection: .wifi,
                    volume: VolumeStatus(scalar: scalar, isMuted: false, deviceName: "Output")
                ),
                audioIcon: nil
            ),
            configuration: .standard
        )
    }

    private func steadyPhase(_ step: Int, multiplier: Double = 1) -> ChargingEffectPhase {
        ChargingEffectPhase(
            step: step,
            stepsPerCycle: 36,
            kind: .steady,
            heartbeatMultiplier: multiplier
        )
    }

    private func frameImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    private func bigFrameImage() -> CGImage {
        let width = 512
        let context = CGContext(
            data: nil,
            width: width,
            height: width,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}

@MainActor
struct DockChargingAnimationPresenterTests {
    @Test func installsOneContentViewAndSkipsADuplicateFrame() {
        let fixture = DockChargingPresenterFixture()
        let phase = steadyPhase(3)

        #expect(fixture.presenter.present(
            phase: phase,
            scene: fixture.scene,
            backgroundStyle: .dark,
            pixelLength: 512
        ))
        #expect(fixture.dockTile.contentView != nil)
        #expect(fixture.presenter.isInstalled)
        #expect(fixture.dockTile.displayCount == 1)

        #expect(fixture.presenter.present(
            phase: phase,
            scene: fixture.scene,
            backgroundStyle: .dark,
            pixelLength: 512
        ))
        #expect(fixture.dockTile.displayCount == 1)
        #expect(fixture.presenter.rasterRequestCount == 1)
    }

    @Test func clearRestoresTheStaticDockTile() {
        let fixture = DockChargingPresenterFixture()
        _ = fixture.presenter.present(
            phase: steadyPhase(0),
            scene: fixture.scene,
            backgroundStyle: .dark,
            pixelLength: 512
        )

        fixture.presenter.clear()

        #expect(fixture.dockTile.contentView == nil)
        #expect(!fixture.presenter.isInstalled)
        #expect(fixture.dockTile.displayCount == 2)
        #expect(fixture.presenter.cachedFrameCount == 0)
    }

    @Test func aSceneChangeRebuildsTheBaseAndTheFrames() {
        let fixture = DockChargingPresenterFixture()
        _ = fixture.presenter.present(
            phase: steadyPhase(0),
            scene: fixture.scene,
            backgroundStyle: .dark,
            pixelLength: 512
        )
        let oldFrameCount = fixture.presenter.rasterizedFrameCount

        let changed = fixture.sceneWithScalar(0.9)
        _ = fixture.presenter.present(
            phase: steadyPhase(0),
            scene: changed,
            backgroundStyle: .light,
            pixelLength: 512
        )

        #expect(fixture.presenter.rasterRequestCount == 2)
        #expect(fixture.presenter.rasterizedFrameCount == oldFrameCount + 36)
        #expect(fixture.dockTile.contentView === fixture.contentView)
    }

    /// The static Dock key intentionally erases `outerRing.effect`. The
    /// animation must not: a real "not charging" scene and the development
    /// test-preview scene are equal by that key but need different rasters.
    @Test func aChargingEffectOnlyChangeStillRepaintsTheDock() {
        let fixture = DockChargingPresenterFixture()
        let previewScene = fixture.scene
        let idleRing = previewScene.outerRing
        let idleScene = IconSceneState(
            outerRing: OuterRingState(
                segments: idleRing?.segments ?? [],
                gap: idleRing?.gap ?? .closed,
                accessory: idleRing?.accessory,
                effect: nil,
                strokeScale: idleRing?.strokeScale ?? 1
            ),
            center: previewScene.center,
            footer: previewScene.footer
        )

        #expect(DockIconRenderKey(
            scene: idleScene,
            backgroundStyle: .dark,
            pixelLength: 128
        ) == DockIconRenderKey(
            scene: previewScene,
            backgroundStyle: .dark,
            pixelLength: 128
        ))

        _ = fixture.presenter.present(
            phase: steadyPhase(0),
            scene: idleScene,
            backgroundStyle: .dark,
            pixelLength: 512
        )
        #expect(fixture.presenter.isInstalled == false)

        #expect(fixture.presenter.present(
            phase: steadyPhase(0),
            scene: previewScene,
            backgroundStyle: .dark,
            pixelLength: 512
        ))
        #expect(fixture.presenter.isInstalled)
        #expect(fixture.dockTile.displayCount > 0)
    }

    @Test func failedEffectFallsBackWithoutInstallingAContentView() {
        let fixture = DockChargingPresenterFixture(failEffects: true)

        #expect(!fixture.presenter.present(
            phase: steadyPhase(0),
            scene: fixture.scene,
            backgroundStyle: .dark,
            pixelLength: 512
        ))
        #expect(fixture.dockTile.contentView == nil)
        #expect(fixture.presenter.isInstalled == false)
    }

    /// The rasters follow the tile the Dock actually draws, quantized so a
    /// magnification sweep cannot rebuild them per pixel.
    @Test func pixelLengthFollowsTheTileSizeAndStaysBounded() {
        let resolved = DockChargingAnimationPresenter.resolvedPixelLength(
            requested: 512,
            tileSize: CGSize(width: 64, height: 64),
            displayScale: 2
        )
        #expect(resolved == 128)

        let magnified = DockChargingAnimationPresenter.resolvedPixelLength(
            requested: 512,
            tileSize: CGSize(width: 72, height: 72),
            displayScale: 2
        )
        #expect(magnified == resolved, "A small size change must not churn the cache.")

        // Nonsense tile sizes fall back to the requested length, never above it.
        let fallback = DockChargingAnimationPresenter.resolvedPixelLength(
            requested: 512,
            tileSize: .zero,
            displayScale: 0
        )
        #expect(fallback == 512)
        #expect(
            DockChargingAnimationPresenter.resolvedPixelLength(
                requested: 512,
                tileSize: CGSize(width: 4000, height: 4000),
                displayScale: 2
            ) == 512
        )
    }

    private func steadyPhase(_ step: Int) -> ChargingEffectPhase {
        ChargingEffectPhase(
            step: step,
            stepsPerCycle: 36,
            kind: .steady
        )
    }
}

@MainActor
private final class DockChargingPresenterFixture {
    let dockTile = FakeDockTile()
    let presenter: DockChargingAnimationPresenter
    let scene: IconSceneState

    init(failEffects: Bool = false) {
        scene = DockChargingTestScene.make(scalar: 0.5)
        let dockTile = self.dockTile
        presenter = DockChargingAnimationPresenter(
            dockTile: dockTile,
            renderBase: { _, _, _ in Self.image() },
            renderEffect: { _, _, _, _ in
                failEffects ? nil : Self.image()
            },
            effectRect: { _, _ in CGRect(x: 100, y: 100, width: 120, height: 120) }
        )
    }

    func sceneWithScalar(_ scalar: Double) -> IconSceneState {
        DockChargingTestScene.make(scalar: scalar)
    }

    var contentView: NSView? { dockTile.contentView }

    private static func image() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}

@MainActor
private final class FakeDockTile: DockTilePresenting {
    private var strongContentView: NSView?
    private(set) var displayCount = 0
    var size = CGSize(width: 64, height: 64)

    var contentView: NSView? {
        get { strongContentView }
        set { strongContentView = newValue }
    }

    func display() {
        displayCount += 1
    }
}

private enum DockChargingTestScene {
    static func make(
        scalar: Double,
        isCharging: Bool = true
    ) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: StatusSnapshot(
                    battery: BatteryStatus(
                        rawPercentage: 62,
                        isPresent: true,
                        isCharging: isCharging,
                        isLowPowerMode: false,
                        isConnectedToPower: isCharging
                    ),
                    wifi: WiFiStatus(state: .connected, rssi: -50),
                    connection: .wifi,
                    volume: VolumeStatus(scalar: scalar, isMuted: false, deviceName: "Output")
                ),
                audioIcon: nil
            ),
            configuration: .standard
        )
    }
}

@MainActor
private final class ManualDockChargingDate {
    private let start = Date(timeIntervalSince1970: 2_000)
    private(set) var elapsed: TimeInterval = 0
    var now: Date { start.addingTimeInterval(elapsed) }
}
