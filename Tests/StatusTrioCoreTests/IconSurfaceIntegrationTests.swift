import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct IconSurfaceIntegrationTests {
    @Test func bothSurfacesRenderTheSameDeliveredScene() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .both)
        defer { harness.cleanUp() }
        var menuBarScenes: [IconSceneState] = []
        let localization = Localization(preferredLanguages: ["en"])
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: localization,
            openSettings: {},
            quitAction: {},
            renderMenuBarIcon: { scene, _, _, _, _ in
                menuBarScenes.append(scene)
                return NSImage(size: NSSize(width: 32, height: 32))
            }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()
        try await waitUntil { !menuBarScenes.isEmpty && harness.log.renderCount > 0 }

        harness.settings.ringStrokeStyle = .bold
        try await waitUntil {
            menuBarScenes.last?.outerRing?.strokeScale == RingStrokeStyle.bold.scale
                && harness.log.lastScene?.outerRing?.strokeScale == RingStrokeStyle.bold.scale
        }

        #expect(menuBarScenes.last == harness.log.lastScene)
    }

    @Test func hiddenMenuBarRestoresWithLatestSceneAndFailedRasterRetries() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .both)
        defer { harness.cleanUp() }
        let rasterSpy = MenuBarRasterSpy()
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: Localization(preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            renderMenuBarIcon: { scene, _, _, _, _ in
                rasterSpy.render(scene)
            }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()
        try await waitUntil { rasterSpy.calls > 0 }

        menuBar.setVisible(false)
        harness.settings.iconSize = 32
        harness.settings.ringStrokeStyle = .bold
        try await waitUntil {
            harness.iconPresentation.output.menuBarSize == 32
                && harness.iconPresentation.output.scene.outerRing?.strokeScale == RingStrokeStyle.bold.scale
        }
        let hiddenCallCount = rasterSpy.calls
        #expect(hiddenCallCount > 0)

        rasterSpy.allowSuccess = true
        menuBar.setVisible(true)
        try await waitUntil { rasterSpy.calls > hiddenCallCount }
        try await waitUntil {
            harness.log.lastScene?.outerRing?.strokeScale == RingStrokeStyle.bold.scale
        }
        #expect(rasterSpy.scenes.last?.outerRing?.strokeScale == RingStrokeStyle.bold.scale)
        #expect(harness.log.lastScene?.outerRing?.strokeScale == RingStrokeStyle.bold.scale)
    }

    @Test func mappedSettingsStayInParityAcrossMenuBarAndDock() async throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .both,
            initialBattery: BatteryStatus(
                rawPercentage: 62,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            initialWiFi: WiFiStatus(state: .noInternet, rssi: nil),
            initialVolume: VolumeStatus(
                scalar: 0.6,
                isMuted: false,
                deviceName: "AirPods",
                currentDevice: PresentationFixtures.bluetoothDevice
            )
        )
        defer { harness.cleanUp() }
        harness.settings.showsBatteryPercentage = true
        try await waitUntil {
            if case .text = harness.iconPresentation.output.scene.outerRing?.accessory { return true }
            return false
        }
        var menuBarScenes: [IconSceneState] = []
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: Localization(preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            renderMenuBarIcon: { scene, _, _, _, _ in
                menuBarScenes.append(scene)
                return NSImage(size: NSSize(width: 32, height: 32))
            }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()
        try await waitUntil { !menuBarScenes.isEmpty && harness.log.renderCount > 0 }

        try await verifySetting(
            "battery scale",
            { harness.settings.batterySymbolScale = 0.95 },
            matches: { scene in
                guard case let .text(text) = scene.outerRing?.accessory else { return false }
                return text.scale == 0.95 * BatteryIconOptions.defaultTextScale
            },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness
        )

        try await verifySetting(
            "ring stroke",
            { harness.settings.ringStrokeStyle = .bold },
            matches: { $0.outerRing?.strokeScale == RingStrokeStyle.bold.scale },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness
        )
        try await verifySetting(
            "Wi-Fi scale",
            { harness.settings.wifiSymbolScale = 1.35 },
            matches: { scene in
                guard case let .symbol(symbol) = scene.center else { return false }
                return symbol.scale == 1.35
            },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness
        )
        try await verifySetting(
            "volume style",
            { harness.settings.volumeDisplayStyle = .arc },
            matches: { if case .arc = $0.footer { true } else { false } },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness
        )

        harness.settings.replacesNetworkIconWithBluetoothAudio = true
        let beforePriorityChange = harness.iconPresentation.output.scene
        harness.settings.prioritizesNetworkErrorsOverBluetoothAudio = false
        try await waitUntil {
            guard case let .symbol(symbol) = harness.iconPresentation.output.scene.center else { return false }
            return symbol.color == .bluetooth && harness.iconPresentation.output.scene != beforePriorityChange
        }
        try await waitUntil {
            menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.log.lastScene == harness.iconPresentation.output.scene
        }
        #expect(menuBarScenes.last == harness.iconPresentation.output.scene)
        #expect(harness.log.lastScene == harness.iconPresentation.output.scene)

        try await verifySetting(
            "Bluetooth scale",
            { harness.settings.bluetoothSymbolScale = 1.4 },
            matches: { scene in
                guard case let .symbol(symbol) = scene.center else { return false }
                return symbol.scale == 1.4
            },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness
        )
        harness.publishBattery(BatteryStatus(
            rawPercentage: 62,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        ))
        try await waitUntil {
            harness.iconPresentation.output.scene.outerRing?.effect?.pulsesAccessory == true
                && menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.log.lastScene == harness.iconPresentation.output.scene
        }
        try await verifySetting(
            "charging bolt heartbeat",
            { harness.settings.showsChargingBoltHeartbeat = false },
            matches: { $0.outerRing?.effect?.pulsesAccessory == false },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness
        )
        try await verifySetting(
            "charging effect",
            { harness.settings.showsChargingEffect = false },
            matches: { $0.outerRing?.effect == nil },
            latestMenuBarScene: { menuBarScenes.last },
            harness: harness
        )
    }

    @Test func ssidExactVolumeAndLanguageChangesDoNotRasterizeEitherSurface() async throws {
        let initialWiFi = WiFiStatus(
            state: .connected,
            rssi: -50,
            ssid: "Office",
            nameAccess: .authorized
        )
        let harness = try AppIconControllerHarness(
            initialPlacement: .both,
            initialWiFi: initialWiFi,
            initialVolume: VolumeStatus(scalar: 0.60, isMuted: false, deviceName: "Speakers")
        )
        defer { harness.cleanUp() }
        harness.settings.volumeDisplayStyle = .dots
        try await waitUntil {
            if case .dots = harness.iconPresentation.output.scene.footer { return true }
            return false
        }
        var menuBarRenders = 0
        var menuBarKeys: [MenuBarRenderSurfaceKey] = []
        let languageSuite = "IconSurfaceIntegration.\(UUID().uuidString)"
        let languageDefaults = try #require(UserDefaults(suiteName: languageSuite))
        defer { languageDefaults.removePersistentDomain(forName: languageSuite) }
        let localization = Localization(defaults: languageDefaults, preferredLanguages: ["en"])
        var menuBarScenes: [IconSceneState] = []
        var spokenValues: [String] = []
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: localization,
            openSettings: {},
            quitAction: {},
            accessibilityValueDidChange: { spokenValues.append($0) },
            renderMenuBarIcon: { scene, size, scale, appearance, phase in
                menuBarRenders += 1
                menuBarScenes.append(scene)
                menuBarKeys.append(MenuBarRenderSurfaceKey(
                    scene: scene,
                    size: size,
                    scale: scale,
                    appearanceName: appearance.name.rawValue,
                    phase: phase
                ))
                return NSImage(size: NSSize(width: 32, height: 32))
            }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()
        try await waitUntil { menuBarRenders > 0 && harness.log.renderCount > 0 }
        try await waitUntil {
            menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.log.lastScene == harness.iconPresentation.output.scene
                && !spokenValues.isEmpty
        }
        let initialMenuBarRenders = menuBarRenders
        let initialDockRenders = harness.log.renderCount
        let initialScene = harness.iconPresentation.output.scene
        let initialMenuBarKey = try #require(menuBarKeys.last)
        let initialDockKey = try #require(harness.log.dockRenderKeys.last)
        #expect(initialMenuBarKey.phase == nil)
        let initialSpokenValue = try #require(spokenValues.last)

        harness.publishWiFi(WiFiStatus(
            state: .connected,
            rssi: -50,
            ssid: "Guest",
            nameAccess: .authorized
        ))
        try await waitUntil { harness.store.snapshot.wifi.ssid == "Guest" }
        try await waitUntil { spokenValues.last?.contains("Guest") == true }
        let ssidSpokenValue = try #require(spokenValues.last)
        #expect(ssidSpokenValue != initialSpokenValue)
        #expect(ssidSpokenValue.contains("Guest"))
        harness.publishVolume(VolumeStatus(scalar: 0.70, isMuted: false, deviceName: "Speakers"))
        try await waitUntil { harness.store.snapshot.volume.scalar == 0.70 }
        try await waitUntil { spokenValues.last != ssidSpokenValue }
        let exactVolumeSpokenValue = try #require(spokenValues.last)
        #expect(exactVolumeSpokenValue != ssidSpokenValue)
        localization.setPreference(.language(.simplifiedChinese))
        try await waitUntil { localization.resolvedLanguage == .simplifiedChinese }
        try await waitUntil { spokenValues.last != exactVolumeSpokenValue }
        let localizedSpokenValue = try #require(spokenValues.last)
        #expect(localizedSpokenValue != exactVolumeSpokenValue)

        #expect(harness.iconPresentation.output.scene == initialScene)
        var precedingKey = initialMenuBarKey
        for key in menuBarKeys.dropFirst(initialMenuBarRenders) {
            #expect(key.scene == precedingKey.scene)
            #expect(key.size == precedingKey.size)
            #expect(key.phase == precedingKey.phase)
            #expect(key.appearanceName != precedingKey.appearanceName || key.scale != precedingKey.scale)
            precedingKey = key
        }
        #expect(harness.log.dockRenderKeys.count == initialDockRenders)
        #expect(harness.log.dockRenderKeys.last == initialDockKey)
    }

    @Test func chargingTestProjectionStaysMenuBarOnly() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .both)
        defer { harness.cleanUp() }
        var menuBarScenes: [IconSceneState] = []
        let menuBar = StatusBarController(
            store: harness.store,
            settings: harness.settings,
            iconPresentation: harness.iconPresentation,
            localization: Localization(preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            renderMenuBarIcon: { scene, _, _, _, _ in
                menuBarScenes.append(scene)
                return NSImage(size: NSSize(width: 32, height: 32))
            }
        )
        defer { menuBar.setVisible(false) }
        harness.controller.start()
        try await waitUntil { !menuBarScenes.isEmpty && harness.log.renderCount > 0 }
        try await waitUntil {
            menuBarScenes.last == harness.iconPresentation.output.scene
                && harness.log.lastScene == harness.iconPresentation.output.scene
        }
        let canonicalScene = harness.iconPresentation.output.scene
        let originalDockImage = harness.application.applicationIconImage
        let dockRenders = harness.log.renderCount

        harness.settings.setChargingEffectTestEnabled(true)
        try await waitUntil {
            guard let testScene = harness.iconPresentation.output.menuBarTestScene else { return false }
            return menuBarScenes.last == testScene
        }

        #expect(harness.iconPresentation.output.scene == canonicalScene)
        #expect(menuBarScenes.last != canonicalScene)
        #expect(harness.log.lastScene == canonicalScene)
        #expect(harness.log.renderCount == dockRenders)
        #expect(harness.application.applicationIconImage === originalDockImage)
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        failureMessage: String = "The surface update did not arrive.",
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("\(failureMessage) Timeout: \(timeout).")
    }

    private func verifySetting(
        _ label: String,
        _ update: @escaping @MainActor () -> Void,
        matches: @escaping @MainActor (IconSceneState) -> Bool,
        latestMenuBarScene: @escaping @MainActor () -> IconSceneState?,
        harness: AppIconControllerHarness
    ) async throws {
        update()
        try await waitUntil(failureMessage: "Model did not map \(label).") {
            matches(harness.iconPresentation.output.scene)
        }
        try await waitUntil(failureMessage: "Surfaces did not render \(label) in parity.") {
            guard let scene = latestMenuBarScene() else { return false }
            return matches(scene)
                && scene == harness.log.lastScene
                && scene == harness.iconPresentation.output.scene
        }
        #expect(latestMenuBarScene() == harness.log.lastScene)
    }

}

private struct MenuBarRenderSurfaceKey: Equatable {
    let scene: IconSceneState
    let size: Double
    let scale: CGFloat
    let appearanceName: String
    let phase: ChargingEffectPhase?
}

@MainActor
private final class MenuBarRasterSpy {
    var allowSuccess = false
    private(set) var calls = 0
    private(set) var scenes: [IconSceneState] = []

    func render(_ scene: IconSceneState) -> NSImage? {
        calls += 1
        scenes.append(scene)
        guard allowSuccess else { return nil }
        return NSImage(size: NSSize(width: 32, height: 32))
    }
}
