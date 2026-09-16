import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct DockIconRenderCacheTests {
    @Test func skipsEqualKeysAndRendersAfterReset() {
        var cache = DockIconRenderCache()
        let key = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark
        )

        let rendersFirstTime = cache.shouldRender(key)
        let rendersSameStatusAgain = cache.shouldRender(key)
        #expect(rendersFirstTime)
        #expect(rendersSameStatusAgain == false)
        cache.reset()
        let rendersAfterReset = cache.shouldRender(key)
        #expect(rendersAfterReset)
    }

    @Test func rendersAgainWhenStatusChanges() {
        var cache = DockIconRenderCache()
        let first = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark
        )
        let second = DockIconRenderKey(
            status: MenuBarStatus(snapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: .connected, rssi: -50),
                volume: .placeholder
            )),
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark
        )

        let rendersFirst = cache.shouldRender(first)
        let rendersSecond = cache.shouldRender(second)
        let rendersSecondAgain = cache.shouldRender(second)
        #expect(rendersFirst)
        #expect(rendersSecond)
        #expect(rendersSecondAgain == false)
    }

    @Test func rendersAgainWhenOptionsChange() {
        var cache = DockIconRenderCache()
        let base = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark
        )
        let changedOptions = DockIconRenderKey(
            status: .placeholder,
            options: BatteryIconOptions(
                showsPercentage: false,
                showsChargingIndicator: false,
                usesStatusColors: false,
                criticalThreshold: 30
            ),
            connectionOptions: .standard,
            backgroundStyle: .dark
        )

        let rendersBase = cache.shouldRender(base)
        let rendersChangedOptions = cache.shouldRender(changedOptions)
        #expect(rendersBase)
        #expect(rendersChangedOptions)
    }

    @Test func rendersAgainWhenVolumeDisplayStyleChanges() {
        var cache = DockIconRenderCache()
        let dots = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            volumeOptions: VolumeIconOptions(displayStyle: .dots),
            backgroundStyle: .dark
        )
        let arc = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            volumeOptions: VolumeIconOptions(displayStyle: .arc),
            backgroundStyle: .dark
        )

        let rendersDots = cache.shouldRender(dots)
        let rendersArc = cache.shouldRender(arc)
        #expect(rendersDots)
        #expect(rendersArc)
    }

    @Test func rendersAgainWhenContinuousVolumeChangesWithinSameStep() {
        var cache = DockIconRenderCache()
        let lower = DockIconRenderKey(
            status: volumeStatus(0.1),
            options: .standard,
            connectionOptions: .standard,
            volumeOptions: VolumeIconOptions(displayStyle: .arc),
            backgroundStyle: .dark
        )
        let higher = DockIconRenderKey(
            status: volumeStatus(0.2),
            options: .standard,
            connectionOptions: .standard,
            volumeOptions: VolumeIconOptions(displayStyle: .arc),
            backgroundStyle: .dark
        )

        #expect(StatusMappings.volumeSteps(scalar: 0.1, isMuted: false) == 1)
        #expect(StatusMappings.volumeSteps(scalar: 0.2, isMuted: false) == 1)
        let rendersLower = cache.shouldRender(lower)
        let rendersHigher = cache.shouldRender(higher)
        #expect(rendersLower)
        #expect(rendersHigher)
    }

    @Test func rendersAgainWhenBackgroundStyleChanges() {
        var cache = DockIconRenderCache()
        let darkKey = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark
        )
        let lightKey = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .light
        )

        let rendersDark = cache.shouldRender(darkKey)
        let rendersLight = cache.shouldRender(lightKey)
        let rendersDarkAgain = cache.shouldRender(darkKey)

        #expect(rendersDark)
        #expect(rendersLight)
        #expect(rendersDarkAgain)
    }

    @Test func reusesTheImageForARepeatedState() {
        let cache = DockIconImageCache()
        let key = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark
        )
        let image = NSImage(size: NSSize(width: 256, height: 256))

        #expect(cache.image(for: key) == nil)
        cache.store(image, for: key)
        #expect(cache.image(for: key) === image)
    }

    @Test func evictsTheOldestImageWhenFull() {
        let cache = DockIconImageCache(limit: 2)
        let keys = [0, 1, 2].map { percentage in
            DockIconRenderKey(
                status: MenuBarStatus(snapshot: StatusSnapshot(
                    battery: BatteryStatus(
                        rawPercentage: percentage,
                        isPresent: true,
                        isCharging: false,
                        isLowPowerMode: false,
                        isConnectedToPower: false
                    ),
                    wifi: .placeholder,
                    volume: .placeholder
                )),
                options: .standard,
                connectionOptions: .standard,
                backgroundStyle: .dark
            )
        }

        for key in keys {
            cache.store(NSImage(size: NSSize(width: 256, height: 256)), for: key)
        }

        #expect(cache.image(for: keys[0]) == nil)
        #expect(cache.image(for: keys[1]) != nil)
        #expect(cache.image(for: keys[2]) != nil)
    }

    private func volumeStatus(_ scalar: Double) -> MenuBarStatus {
        MenuBarStatus(snapshot: StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            volume: VolumeStatus(scalar: scalar, isMuted: false, deviceName: nil)
        ))
    }
}
