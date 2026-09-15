import Testing
@testable import StatusTrioCore

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
}
