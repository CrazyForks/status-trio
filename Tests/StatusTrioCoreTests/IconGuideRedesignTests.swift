import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconGuideRedesignTests: XCTestCase {
    func testGuideProvidesEightDistinctStateExamples() {
        XCTAssertEqual(IconGuideState.all.count, 8)
        XCTAssertEqual(Set(IconGuideState.all.map(\.id)).count, 8)

        XCTAssertTrue(IconGuideState.charging.status.battery.isCharging)
        XCTAssertEqual(IconGuideState.lowBattery.status.battery.percentage, 12)
        XCTAssertEqual(IconGuideState.ethernet.status.connection, .ethernet)
        XCTAssertEqual(IconGuideState.noInternetMuted.status.wifi.state, .noInternet)
        XCTAssertTrue(IconGuideState.noInternetMuted.status.volume.isMuted)
        XCTAssertTrue(IconGuideState.hotspotLowPower.status.battery.isLowPowerMode)
        XCTAssertEqual(IconGuideState.weakWiFi.status.wifi.state, .connected)
        XCTAssertEqual(IconGuideState.weakWiFi.status.wifi.rssi, -86)
    }

    /// The two Bluetooth cards must show their mode even on a fresh install,
    /// where both Bluetooth options are still at their defaults.
    func testBluetoothGuideStatesForceTheModeTheyDemonstrate() {
        let configured = BluetoothAudioIconOptions.standard

        let headphones = IconGuideState.bluetoothHeadphones.bluetoothAudioOptions(
            configuring: configured
        )
        XCTAssertTrue(headphones.replacesNetworkIcon)
        XCTAssertFalse(headphones.usesVolumeColor)

        let tintedVolume = IconGuideState.bluetoothVolumeTint.bluetoothAudioOptions(
            configuring: configured
        )
        XCTAssertFalse(
            tintedVolume.replacesNetworkIcon,
            "The blue volume card keeps Wi-Fi in the middle so only the bottom row changes."
        )
        XCTAssertTrue(tintedVolume.usesVolumeColor)

        // Unrelated Bluetooth cards keep following the user's configuration.
        XCTAssertEqual(
            IconGuideState.ethernet.bluetoothAudioOptions(configuring: configured),
            configured
        )
    }

    func testBluetoothGuideStatesKeepTheConfiguredBluetoothPreferences() {
        let configured = BluetoothAudioIconOptions(
            replacesNetworkIcon: false,
            usesVolumeColor: false,
            prioritizesNetworkErrors: false,
            symbolScale: 1.35
        )

        for state in [IconGuideState.bluetoothHeadphones, .bluetoothVolumeTint] {
            let options = state.bluetoothAudioOptions(configuring: configured)
            XCTAssertEqual(options.prioritizesNetworkErrors, false)
            XCTAssertEqual(options.symbolScale, 1.35)
        }
    }

    func testBluetoothGuideStatesUseABluetoothDevice() throws {
        for state in [IconGuideState.bluetoothHeadphones, .bluetoothVolumeTint] {
            let device = try XCTUnwrap(state.status.volume.currentDevice)
            XCTAssertTrue(device.isBluetoothAudio)
            XCTAssertEqual(device.transport, .bluetooth)
        }
    }

    /// A blank or unrelated glyph would make both new cards unreadable, so the
    /// example device has to resolve to the headphone symbol.
    func testBluetoothGuideDeviceResolvesToTheHeadphoneSymbol() {
        XCTAssertEqual(
            AudioOutputDeviceIcon.source(for: IconGuideState.bluetoothExampleDevice),
            .symbol("headphones")
        )
    }

    func testBluetoothGuideStatesRequestTheirOwnVolumeExample() throws {
        for state in [IconGuideState.bluetoothHeadphones, .bluetoothVolumeTint] {
            let dockImage = try XCTUnwrap(
                DockIconRenderer.image(
                    status: state.status,
                    volumeOptions: VolumeIconOptions(
                        displayStyle: try XCTUnwrap(state.volumeDisplayStyleOverride),
                        ringStrokeScale: RingStrokeStyle.regular.scale
                    ),
                    bluetoothAudioOptions: state.bluetoothAudioOptions(
                        configuring: .standard
                    )
                )
            )
            XCTAssertEqual(dockImage.size, NSSize(width: 256, height: 256))
        }
    }

    func testEveryGuideStateRendersInMenuBarAndDock() throws {
        for state in IconGuideState.all {
            let menuBarImage = StatusIconRenderer.image(
                menuBarStatus: state.status,
                size: 56
            )
            XCTAssertGreaterThan(menuBarImage.size.width, 0)

            let dockImage = try XCTUnwrap(
                DockIconRenderer.image(status: state.status)
            )
            XCTAssertEqual(dockImage.size, NSSize(width: 256, height: 256))
        }
    }

    func testStateGalleryIncludesDotsAndArcVolumeExamples() {
        XCTAssertEqual(
            IconGuideState.charging.volumeDisplayStyleOverride,
            .dots
        )
        XCTAssertEqual(
            IconGuideState.weakWiFi.volumeDisplayStyleOverride,
            .arc
        )
    }

    func testAnatomyPreviewUsesGreenChargingArcWithPercentage() {
        let battery = IconGuideView.example.battery
        let options = IconGuideView.demoBatteryOptions(
            configured: .standard
        )

        XCTAssertTrue(battery.isCharging)
        XCTAssertTrue(battery.isConnectedToPower)
        XCTAssertEqual(
            StatusMappings.batteryGapContent(battery, options: options),
            .percentage
        )
        XCTAssertEqual(
            StatusMappings.batteryColorRole(
                battery,
                criticalThreshold: options.criticalThreshold
            ),
            .charging
        )
    }

    /// The guide renders the production artwork, so its anatomy and gallery
    /// previews must follow the configured ring stroke width instead of falling
    /// back to the default.
    func testGuidePreviewsForwardTheConfiguredRingStrokeWidth() {
        let options = IconGuideView.demoBatteryOptions(
            configured: BatteryIconOptions(ringStrokeScale: RingStrokeStyle.bold.scale)
        )

        XCTAssertEqual(options.ringStrokeScale, RingStrokeStyle.bold.scale)
    }

    func testStateGalleryCoversLightAndDarkDockAppearances() throws {
        XCTAssertFalse(IconGuidePreviewAppearance.light.isDarkBackground)
        XCTAssertTrue(IconGuidePreviewAppearance.dark.isDarkBackground)
        XCTAssertEqual(
            IconGuidePreviewAppearance.light.dockBackgroundStyle,
            .light
        )
        XCTAssertEqual(
            IconGuidePreviewAppearance.dark.dockBackgroundStyle,
            .dark
        )

        for appearance in IconGuidePreviewAppearance.allCases {
            let dockImage = try XCTUnwrap(
                DockIconRenderer.image(
                    status: IconGuideState.charging.status,
                    backgroundStyle: appearance.dockBackgroundStyle
                )
            )
            XCTAssertEqual(dockImage.size, NSSize(width: 256, height: 256))
        }
    }

    func testDockGlyphFrameMatchesRendererLayout() {
        let frame = DockIconGlyphLayout.frame(
            in: CGRect(x: 0, y: 0, width: 256, height: 256)
        )

        XCTAssertEqual(frame.minX, 48.7, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 45.04, accuracy: 0.001)
        XCTAssertEqual(frame.width, 168, accuracy: 0.001)
        XCTAssertEqual(frame.height, 168, accuracy: 0.001)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 256, height: 256).contains(frame))
    }

    func testGuidePageNavigationAdvancesAndReturns() {
        XCTAssertEqual(IconGuidePage.anatomy.next, .states)
        XCTAssertEqual(IconGuidePage.states.previous, .anatomy)
        XCTAssertEqual(IconGuidePage.anatomy.previous, .anatomy)
        XCTAssertEqual(IconGuidePage.states.next, .states)
    }

    func testRedesignedOnboardingRendersWideLayout() {
        let name = "IconGuideRedesignTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(
            defaults: defaults,
            preferredLanguages: ["en"]
        )
        let view = IconGuideOnboardingView(
            settings: settings,
            onCustomize: {},
            onDone: {}
        )
        .environmentObject(localization)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 560)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertNotNil(hostingView.subviews)
    }

    func testOnboardingHeightStaysEqualAcrossPages() {
        let name = "IconGuideRedesignTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(
            defaults: defaults,
            preferredLanguages: ["en"]
        )
        var preferredHeights: [CGFloat] = []

        for page in [IconGuidePage.anatomy, .states] {
            let view = IconGuideOnboardingView(
                settings: settings,
                initialPage: page,
                onCustomize: {},
                onDone: {}
            )
            .environmentObject(localization)

            let hostingController = NSHostingController(rootView: view)
            hostingController.sizingOptions = [.preferredContentSize]
            hostingController.view.frame = NSRect(
                x: 0,
                y: 0,
                width: IconGuideOnboardingView.contentWidth,
                height: 560
            )
            hostingController.view.layoutSubtreeIfNeeded()

            let preferredSize = hostingController.preferredContentSize
            XCTAssertEqual(
                preferredSize.width,
                IconGuideOnboardingView.contentWidth,
                accuracy: 0.5
            )
            XCTAssertGreaterThanOrEqual(preferredSize.height, 420)
            XCTAssertLessThan(preferredSize.height, 560)
            preferredHeights.append(preferredSize.height)
        }

        XCTAssertEqual(
            preferredHeights[0],
            preferredHeights[1],
            accuracy: 0.5
        )
    }

    func testFooterPrimaryActionStaysFixedAcrossPages() throws {
        let name = "IconGuideRedesignTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removeTestSuite(named: name) }
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(
            defaults: defaults,
            preferredLanguages: ["zh-Hans"]
        )
        var frames: [CGRect] = []

        for page in [IconGuidePage.anatomy, .states] {
            let view = IconGuideOnboardingView(
                settings: settings,
                initialPage: page,
                onCustomize: {},
                onDone: {}
            )
            .environmentObject(localization)

            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 560)
            hostingView.layoutSubtreeIfNeeded()

            let trailingEdge = IconGuideOnboardingView.contentWidth - 28
            let subviewFrames: [CGRect] = hostingView.subviews.map(\.frame)
            let trailingFrames: [CGRect] = subviewFrames.filter { frame in
                frame.height > 0
                    && abs(frame.maxX - trailingEdge) < 0.5
            }
            let primaryFrame = try XCTUnwrap(
                trailingFrames.max { $0.minX < $1.minX }
            )
            frames.append(primaryFrame)
        }

        XCTAssertEqual(frames[0], frames[1])
    }
}
