import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconSceneRendererParityTests: XCTestCase {
    func testNormalSceneMatchesLegacyPixels() throws {
        try assertMenuBarParity(for: PresentationFixtures.snapshot())
    }

    func testTaskOneVisualMatrixMatchesLegacyPixelsOnBothSurfaces() throws {
        for fixture in visualCases() {
            try assertMenuBarParity(for: fixture.snapshot, configuration: fixture.configuration, label: fixture.name)
            for style in DockIconBackgroundStyle.allCases {
                try assertDockParity(for: fixture, style: style)
            }
        }
    }

    func testStaticSteadyAndBurstChargingFramesMatchLegacyPixels() throws {
        let snapshot = makeSnapshot(
            battery: battery(percentage: 43, charging: true, connected: true),
            wifi: WiFiStatus(state: .connected, rssi: -62),
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )
        let phases: [(String, ChargingEffectPhase?)] = [
            ("static", nil),
            ("steady", ChargingEffectPhase(step: 18, stepsPerCycle: 36, kind: .steady)),
            ("burst", ChargingEffectPhase(step: 4, stepsPerCycle: 12, kind: .burst))
        ]
        for (name, phase) in phases {
            try assertMenuBarParity(for: snapshot, phase: phase, label: name)
        }
        let charged = makeSnapshot(
            battery: battery(percentage: 100, charging: true, connected: true),
            wifi: WiFiStatus(state: .connected, rssi: -62),
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )
        try assertMenuBarParity(for: charged,
                                phase: ChargingEffectPhase(step: 4, stepsPerCycle: 12, kind: .burst),
                                label: "charged completion")
        try assertMenuBarParity(
            for: snapshot,
            configuration: configuration(battery: BatteryIconOptions(showsChargingEffect: false)),
            phase: ChargingEffectPhase(step: 4, stepsPerCycle: 12, kind: .burst),
            label: "charging effect disabled"
        )
        let configurations: [(String, BatteryIconOptions)] = [
            ("heartbeat enabled with status tint", .standard),
            ("heartbeat disabled", BatteryIconOptions(showsChargingBoltHeartbeat: false)),
            ("heartbeat enabled without status colors", BatteryIconOptions(usesStatusColors: false))
        ]
        for (name, options) in configurations {
            let config = configuration(battery: options)
            try assertMenuBarParity(for: snapshot, configuration: config,
                                    phase: ChargingEffectPhase(step: 6, stepsPerCycle: 12, kind: .burst),
                                    label: name)
        }
    }

    func testFractionalMenuBarSizeAndScaleMatchLegacyPixels() throws {
        let snapshot = PresentationFixtures.snapshot(rssi: -79, scalar: 0.74, muted: true)
        try assertMenuBarParity(for: snapshot, size: 20, scale: 8, label: "20pt at 8x")
        try assertMenuBarParity(for: snapshot, size: 18.5, scale: 3, label: "fractional logical size")
    }

    func testMenuBarRejectsNonFiniteAndNonPositiveSizeAndScale() {
        let scene = mappedScene(for: PresentationFixtures.snapshot())
        let foreground = CGColor(gray: 1, alpha: 1)
        let critical = StatusIconRenderer.defaultCriticalColor
        for size: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertNil(StatusIconRenderer.render(
                scene: scene,
                environment: StatusIconRenderEnvironment(size: size, scale: 2,
                                                         foreground: foreground, criticalColor: critical)
            ), "size=\(size)")
        }
        for scale: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertNil(StatusIconRenderer.render(
                scene: scene,
                environment: StatusIconRenderEnvironment(size: 20, scale: scale,
                                                         foreground: foreground, criticalColor: critical)
            ), "scale=\(scale)")
        }
    }

    func testRendererRejectsEmptyAndMultiSegmentRings() {
        let foreground = CGColor(gray: 1, alpha: 1)
        let environment = StatusIconRenderEnvironment(
            size: 28,
            scale: 2,
            foreground: foreground,
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        let one = RingSegmentState(progress: 0.4, color: .primary)
        let unsupported = [
            OuterRingState(segments: [], gap: .closed),
            OuterRingState(segments: [one, one], gap: .closed)
        ]
        for ring in unsupported {
            XCTAssertNil(StatusIconRenderer.render(scene: IconSceneState(outerRing: ring), environment: environment))
        }
        XCTAssertNil(StatusIconRenderer.render(
            scene: IconSceneState(footer: .dots(DotsState(count: 5, activeCount: 3, color: .primary))),
            environment: environment
        ))
        XCTAssertNil(DockIconRenderer.image(scene: IconSceneState(), pixelLength: 513))
    }

    func testUnknownSymbolAndUnreadableImageUseLegacyFallbacks() throws {
        let device = AudioOutputDevice(
            id: 41,
            name: "Headphones",
            isCurrent: true,
            volume: 0.5,
            transport: .bluetooth
        )
        let snapshot = makeSnapshot(
            wifi: WiFiStatus(state: .connected, rssi: -55),
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Headphones", currentDevice: device)
        )
        let bluetooth = BluetoothAudioIconOptions(replacesNetworkIcon: true)
        let unknownOverride = BluetoothAudioIconOptions(
            replacesNetworkIcon: true,
            networkIconSymbolOverride: "status-trio-symbol-that-does-not-exist"
        )
        try assertMenuBarParity(for: snapshot, configuration: configuration(bluetooth: unknownOverride), label: "unknown symbol")

        let base = mappedScene(for: snapshot, configuration: configuration(bluetooth: bluetooth))
        let brokenImageCenter = CenterState.symbol(IconSymbolState(
            source: .image(url: URL(fileURLWithPath: "/tmp/status-trio-missing-device-icon.png"), fallbackSymbol: "headphones"),
            color: .bluetooth,
            scale: bluetooth.symbolScale
        ))
        let scene = IconSceneState(outerRing: base.outerRing, center: brokenImageCenter, footer: base.footer)
        let foreground = CGColor(gray: 1, alpha: 1)
        let environment = StatusIconRenderEnvironment(
            size: 28,
            scale: 2,
            foreground: foreground,
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        let actual = try XCTUnwrap(StatusIconRenderer.render(scene: scene, environment: environment))
        let expected = try XCTUnwrap(StatusIconRenderer.render(
            snapshot: snapshot,
            size: environment.size,
            scale: environment.scale,
            foreground: environment.foreground,
            criticalColor: environment.criticalColor,
            bluetoothAudioOptions: bluetooth
        ))
        assertPixelsEqual(expected, actual, label: "unreadable image fallback")
    }

    func testKnownPickedSymbolWithoutDeviceMatchesLegacyOnBothSurfaces() throws {
        let snapshot = PresentationFixtures.snapshot()
        let symbol = "headphones"
        XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil))
        let picked = configuration(bluetooth: BluetoothAudioIconOptions(
            replacesNetworkIcon: true,
            networkIconSymbolOverride: symbol
        ))
        let fixture = VisualCase(name: "picked headphones without device", snapshot: snapshot,
                                 configuration: picked)
        try assertMenuBarParity(for: snapshot, configuration: picked, label: fixture.name)
        for style in DockIconBackgroundStyle.allCases {
            try assertDockParity(for: fixture, style: style)
        }
    }

    func testReadableDeviceImageMatchesLegacyOnBothSurfaces() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-readable-device-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemPurple.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 16, height: 16)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)

        let device = AudioOutputDevice(id: 42, name: "Custom Bluetooth", isCurrent: true,
                                       volume: 0.6, transport: .bluetooth, iconURL: url)
        let snapshot = makeSnapshot(
            wifi: WiFiStatus(state: .connected, rssi: -62),
            volume: VolumeStatus(scalar: 0.6, isMuted: false, deviceName: device.name, currentDevice: device)
        )
        let bluetooth = BluetoothAudioIconOptions(replacesNetworkIcon: true)
        let fixture = VisualCase(name: "readable device resource", snapshot: snapshot,
                                 configuration: configuration(bluetooth: bluetooth))
        XCTAssertEqual(IconPresentationResourceResolver.inputs(snapshot: snapshot).audioIcon,
                       .image(url: url, fallbackSymbol: "headphones"))
        try assertMenuBarParity(for: snapshot, configuration: fixture.configuration, label: fixture.name)
        for style in DockIconBackgroundStyle.allCases {
            try assertDockParity(for: fixture, style: style)
        }
    }

    func testColoredBoltAndPlugPrimitivesUseDeclaredColor() throws {
        let foreground = CGColor(gray: 1, alpha: 1)
        let environment = StatusIconRenderEnvironment(size: 28, scale: 2, foreground: foreground,
                                                      criticalColor: StatusIconRenderer.defaultCriticalColor)
        for primitive in [IconPrimitive.bolt, .plug] {
            let primary = IconSceneState(outerRing: OuterRingState(
                segments: [RingSegmentState(progress: 0.43, color: .primary)],
                gap: .indicator,
                accessory: .symbol(IconSymbolState(source: .primitive(primitive), color: .primary, scale: 1)),
                effect: primitive == .bolt ? RingEffectState(pulsesAccessory: true, tintsAccessory: true) : nil
            ))
            let critical = IconSceneState(outerRing: OuterRingState(
                segments: [RingSegmentState(progress: 0.43, color: .primary)],
                gap: .indicator,
                accessory: .symbol(IconSymbolState(source: .primitive(primitive), color: .critical, scale: 1)),
                effect: primitive == .bolt ? RingEffectState(pulsesAccessory: true, tintsAccessory: true) : nil
            ))
            let phase = ChargingEffectPhase(step: 5, stepsPerCycle: 12, kind: .burst)
            let primaryImage = try XCTUnwrap(StatusIconRenderer.render(scene: primary, environment: environment,
                                                                        phase: phase))
            let criticalImage = try XCTUnwrap(StatusIconRenderer.render(scene: critical, environment: environment,
                                                                        phase: phase))
            XCTAssertNotEqual(try PixelBuffer(image: primaryImage).bytes,
                              try PixelBuffer(image: criticalImage).bytes,
                              "\(primitive) must use its declared scene color")
        }
    }

    func testBluetoothVolumeArcTintMatchesLegacyOnBothSurfaces() throws {
        let volume = VolumeStatus(scalar: 0.72, isMuted: false, deviceName: "Headphones",
                                 currentDevice: PresentationFixtures.bluetoothDevice)
        let snapshot = makeSnapshot(volume: volume)
        let options = configuration(
            volume: VolumeIconOptions(displayStyle: .arc),
            bluetooth: BluetoothAudioIconOptions(usesVolumeColor: true)
        )
        let fixture = VisualCase(name: "Bluetooth tinted volume arc", snapshot: snapshot,
                                 configuration: options)
        try assertMenuBarParity(for: snapshot, configuration: options, label: fixture.name)
        for style in DockIconBackgroundStyle.allCases {
            try assertDockParity(for: fixture, style: style)
        }
    }

    private struct VisualCase {
        let name: String
        let snapshot: StatusSnapshot
        let configuration: IconPresentationConfiguration
    }

    private func visualCases() -> [VisualCase] {
        let ordinary = PresentationFixtures.snapshot()
        var cases = [VisualCase(name: "ordinary", snapshot: ordinary, configuration: .standard)]

        let batteryCases: [(String, BatteryStatus, BatteryIconOptions)] = [
            ("low battery critical", battery(percentage: 12), .standard),
            ("low power", BatteryStatus(rawPercentage: 34, isPresent: true, isCharging: false,
                                         isLowPowerMode: true, isConnectedToPower: false), .standard),
            ("charging bolt", battery(percentage: 43, charging: true, connected: true), .standard),
            ("connected plug", battery(percentage: 73, connected: true), .standard),
            ("present battery closed ring", battery(percentage: 68), BatteryIconOptions(
                showsPercentage: false, showsChargingIndicator: false, usesStatusColors: false
            )),
            ("scaled battery text and bold ring", battery(percentage: 54), BatteryIconOptions(
                textScale: 1.35, ringStrokeScale: RingStrokeStyle.bold.scale
            )),
            ("custom critical threshold", battery(percentage: 28), BatteryIconOptions(
                criticalThreshold: 30, ringStrokeScale: RingStrokeStyle.light.scale
            )),
            ("absent battery", BatteryStatus(rawPercentage: nil, isPresent: false, isCharging: false,
                                              isLowPowerMode: false, isConnectedToPower: false), .standard)
        ]
        for (name, status, options) in batteryCases {
            cases.append(VisualCase(name: name,
                                    snapshot: makeSnapshot(battery: status),
                                    configuration: configuration(battery: options)))
        }

        let wifiCases: [(String, WiFiStatus, NetworkConnection, ConnectionIconOptions)] = [
            ("connected full signal", WiFiStatus(state: .connected, rssi: -60), .wifi, .standard),
            ("connected medium signal", WiFiStatus(state: .connected, rssi: -70), .wifi, .standard),
            ("connected weak signal", WiFiStatus(state: .connected, rssi: -85), .wifi, .standard),
            ("connected no signal", WiFiStatus(state: .connected, rssi: nil), .wifi, .standard),
            ("not associated", WiFiStatus(state: .notAssociated, rssi: nil), .wifi, .standard),
            ("wifi off", WiFiStatus(state: .off, rssi: nil), .wifi, .standard),
            ("wifi unavailable", WiFiStatus(state: .unavailable, rssi: nil), .wifi, .standard),
            ("no internet", WiFiStatus(state: .noInternet, rssi: -45), .wifi, .standard),
            ("hotspot mark", WiFiStatus(state: .hotspot, rssi: -65), .wifi, .standard),
            ("hotspot signal", WiFiStatus(state: .hotspot, rssi: -65), .wifi,
             ConnectionIconOptions(showsWiFiIconForHotspot: true)),
            ("temporary mark", WiFiStatus(state: .temporary, rssi: -65), .wifi, .standard),
            ("temporary signal", WiFiStatus(state: .temporary, rssi: -65), .wifi,
             ConnectionIconOptions(showsWiFiIconForTemporaryConnection: true, wifiScale: 1.4)),
            ("shared mark", WiFiStatus(state: .shared, rssi: -65), .wifi, .standard),
            ("shared signal", WiFiStatus(state: .shared, rssi: -65), .wifi,
             ConnectionIconOptions(showsWiFiIconForInternetSharing: true, wifiScale: 0.8)),
            ("ethernet", WiFiStatus(state: .off, rssi: nil), .ethernet, .standard),
            ("ethernet as full wifi", WiFiStatus(state: .off, rssi: nil), .ethernet,
             ConnectionIconOptions(showsWiFiIconForEthernet: true, wifiScale: 1.3))
        ]
        for (name, wifi, connection, options) in wifiCases {
            cases.append(VisualCase(name: name,
                                    snapshot: makeSnapshot(wifi: wifi, connection: connection),
                                    configuration: configuration(connection: options)))
        }
        cases.append(VisualCase(
            name: "battery percentage in center slot",
            snapshot: ordinary,
            configuration: configuration(connection: ConnectionIconOptions(showsBatteryPercentageInConnectionSlot: true))
        ))

        let volumeCases: [(String, VolumeStatus, VolumeIconOptions, BluetoothAudioIconOptions)] = [
            ("volume silent dots", VolumeStatus(scalar: 0, isMuted: false, deviceName: "Output"), .standard, .standard),
            ("volume partial dots", VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output"), .standard, .standard),
            ("volume full dots", VolumeStatus(scalar: 1, isMuted: false, deviceName: "Output"), .standard, .standard),
            ("volume muted", VolumeStatus(scalar: 0.82, isMuted: true, deviceName: "Output"), .standard, .standard),
            ("volume unavailable", .placeholder, .standard, .standard),
            ("volume arc", VolumeStatus(scalar: 0.63, isMuted: false, deviceName: "Output"),
             VolumeIconOptions(displayStyle: .arc, ringStrokeScale: RingStrokeStyle.bold.scale), .standard),
            ("bold volume dots", VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output"),
             VolumeIconOptions(ringStrokeScale: RingStrokeStyle.bold.scale), .standard),
            ("volume muted arc", VolumeStatus(scalar: 0.63, isMuted: true, deviceName: "Output"),
             VolumeIconOptions(displayStyle: .arc), .standard),
            ("Bluetooth tinted volume", VolumeStatus(scalar: 0.75, isMuted: false, deviceName: "Output",
                                                       currentDevice: PresentationFixtures.bluetoothDevice),
             .standard, BluetoothAudioIconOptions(usesVolumeColor: true)),
            ("Bluetooth replaced center", VolumeStatus(scalar: 0.75, isMuted: false, deviceName: "Output",
                                                         currentDevice: PresentationFixtures.bluetoothDevice),
             .standard, BluetoothAudioIconOptions(replacesNetworkIcon: true, usesVolumeColor: true))
        ]
        for (name, volume, options, bluetooth) in volumeCases {
            cases.append(VisualCase(name: name,
                                    snapshot: makeSnapshot(volume: volume),
                                    configuration: configuration(volume: options, bluetooth: bluetooth)))
        }

        return cases
    }

    private func assertMenuBarParity(
        for snapshot: StatusSnapshot,
        configuration: IconPresentationConfiguration = .standard,
        phase: ChargingEffectPhase? = nil,
        size: CGFloat = 28,
        scale: CGFloat = 2,
        label: String = ""
    ) throws {
        let critical = CGColor(red: 255.0 / 255.0, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
        for foreground in [CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] {
            let expected = try XCTUnwrap(StatusIconRenderer.render(
                snapshot: snapshot,
                size: size,
                scale: scale,
                foreground: foreground,
                criticalColor: critical,
                options: configuration.battery,
                connectionOptions: configuration.connection,
                volumeOptions: configuration.volume,
                bluetoothAudioOptions: configuration.bluetooth,
                phase: phase
            ), "legacy render \(label)")
            let scene = mappedScene(for: snapshot, configuration: configuration)
            let environment = StatusIconRenderEnvironment(size: size, scale: scale,
                                                          foreground: foreground, criticalColor: critical)
            let actual = try XCTUnwrap(StatusIconRenderer.render(scene: scene, environment: environment, phase: phase),
                                       "scene render \(label)")
            assertPixelsEqual(expected, actual, label: label)
        }
    }

    private func assertDockParity(for fixture: VisualCase, style: DockIconBackgroundStyle) throws {
        let expected = try XCTUnwrap(DockIconRenderer.image(
            status: MenuBarStatus(snapshot: fixture.snapshot),
            options: fixture.configuration.battery,
            connectionOptions: fixture.configuration.connection,
            volumeOptions: fixture.configuration.volume,
            bluetoothAudioOptions: fixture.configuration.bluetooth,
            backgroundStyle: style,
            pixelLength: 96
        ))
        let scene = mappedScene(for: fixture.snapshot, configuration: fixture.configuration)
        let actual = try XCTUnwrap(DockIconRenderer.image(scene: scene, backgroundStyle: style, pixelLength: 96))
        assertPixelsEqual(
            try cgImage(from: expected),
            try cgImage(from: actual),
            label: "Dock \(fixture.name), \(style)"
        )
    }

    private func mappedScene(
        for snapshot: StatusSnapshot,
        configuration: IconPresentationConfiguration = .standard
    ) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationResourceResolver.inputs(snapshot: snapshot),
            configuration: configuration
        )
    }

    private func configuration(
        battery: BatteryIconOptions = .standard,
        connection: ConnectionIconOptions = .standard,
        volume: VolumeIconOptions = .standard,
        bluetooth: BluetoothAudioIconOptions = .standard
    ) -> IconPresentationConfiguration {
        IconPresentationConfiguration(battery: battery, connection: connection, volume: volume, bluetooth: bluetooth)
    }

    private func makeSnapshot(
        battery: BatteryStatus = .placeholder,
        wifi: WiFiStatus = .placeholder,
        connection: NetworkConnection = .wifi,
        volume: VolumeStatus = .placeholder
    ) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, connection: connection, volume: volume)
    }

    private func battery(percentage: Int, charging: Bool = false, connected: Bool = false) -> BatteryStatus {
        BatteryStatus(rawPercentage: percentage, isPresent: true, isCharging: charging,
                      isLowPowerMode: false, isConnectedToPower: connected)
    }

    private func cgImage(from image: NSImage) throws -> CGImage {
        try XCTUnwrap(XCTUnwrap(image.representations.first as? NSBitmapImageRep).cgImage)
    }

    private func assertPixelsEqual(
        _ expected: CGImage,
        _ actual: CGImage,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(expected.width, actual.width, "image width: \(label)", file: file, line: line)
        XCTAssertEqual(expected.height, actual.height, "image height: \(label)", file: file, line: line)
        guard let expectedBytes = try? PixelBuffer(image: expected).bytes,
              let actualBytes = try? PixelBuffer(image: actual).bytes else {
            XCTFail("could not read pixel buffers: \(label)", file: file, line: line)
            return
        }
        let firstDifference = zip(expectedBytes, actualBytes).enumerated().first { $0.element.0 != $0.element.1 }
        XCTAssertEqual(expectedBytes.count, actualBytes.count, "pixel byte count: \(label)", file: file, line: line)
        XCTAssertEqual(expectedBytes, actualBytes,
                       "pixel mismatch: \(label), first byte \(String(describing: firstDifference))",
                       file: file, line: line)
    }
}
