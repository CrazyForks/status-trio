import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconSceneRendererParityTests: XCTestCase {
    func testOrdinarySceneKeepsIndependentCanvasAndRegionConventions() throws {
        let scene = mappedScene(for: PresentationFixtures.snapshot())
        for foreground in [CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] {
            let pixels = try menuBarPixels(scene: scene, foreground: foreground, size: 28, scale: 2)
            assertMenuBarPixelConventions(pixels, size: 28, scale: 2, label: "ordinary")
        }
    }

    func testTaskOneVisualMatrixKeepsFixedGeometryAndDockPaletteConventions() throws {
        for fixture in visualCases() {
            let scene = mappedScene(for: fixture.snapshot, configuration: fixture.configuration)
            for foreground in [CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] {
                let pixels = try menuBarPixels(scene: scene, foreground: foreground, size: 28, scale: 2)
                assertMenuBarPixelConventions(pixels, size: 28, scale: 2, label: fixture.name)
            }
            for style in DockIconBackgroundStyle.allCases {
                let image = try XCTUnwrap(DockIconRenderer.image(scene: scene, backgroundStyle: style, pixelLength: 96))
                let pixels = try cgPixels(from: image)
                XCTAssertEqual(pixels.width, 96, "Dock width: \(fixture.name), \(style)")
                XCTAssertEqual(pixels.height, 96, "Dock height: \(fixture.name), \(style)")
                XCTAssertEqual(pixels.bytes.count, 96 * 96 * 4, "Dock full buffer: \(fixture.name), \(style)")
                XCTAssertEqual(pixels.rgba(x: 0, y: 0).alpha, 0, "Dock transparent corner: \(fixture.name), \(style)")
                XCTAssertEqual(pixels.rgba(x: 48, y: 2).alpha, 0, "Dock transparent margin: \(fixture.name), \(style)")
                let body = pixels.rgba(x: 12, y: 48)
                switch style {
                case .dark:
                    XCTAssertGreaterThan(body.alpha, 250, "Dock dark body: \(fixture.name)")
                    XCTAssertEqual(body.red, 21, accuracy: 3)
                    XCTAssertEqual(body.green, 21, accuracy: 3)
                    XCTAssertEqual(body.blue, 23, accuracy: 3)
                    XCTAssertTrue(pixels.containsColor(red: 1, green: 1, blue: 1, tolerance: 0.08, minimumAlpha: 0.9), fixture.name)
                case .light:
                    XCTAssertGreaterThan(body.alpha, 250, "Dock light body: \(fixture.name)")
                    XCTAssertGreaterThanOrEqual(body.red, 250)
                    XCTAssertGreaterThanOrEqual(body.green, 250)
                    XCTAssertGreaterThanOrEqual(body.blue, 250)
                    XCTAssertTrue(pixels.containsColor(red: 29.0 / 255.0, green: 29.0 / 255.0, blue: 31.0 / 255.0,
                                                       tolerance: 0.08, minimumAlpha: 0.9), fixture.name)
                case .clear:
                    XCTAssertGreaterThan(body.alpha, 80, "Dock clear body: \(fixture.name)")
                    XCTAssertLessThan(body.alpha, 240, "Dock clear body: \(fixture.name)")
                    XCTAssertTrue(pixels.containsColor(red: 29.0 / 255.0, green: 29.0 / 255.0, blue: 31.0 / 255.0,
                                                       tolerance: 0.08, minimumAlpha: 0.9), fixture.name)
                }
            }
        }
    }

    func testAnimationPhasesKeepStaticAndDisabledPixelConventions() throws {
        let active = makeSnapshot(
            battery: battery(percentage: 43, charging: true, connected: true),
            wifi: WiFiStatus(state: .connected, rssi: -62),
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        )
        let scene = mappedScene(for: active)
        var frames: [PixelBuffer] = []
        for phase in [
            nil,
            ChargingEffectPhase(step: 18, stepsPerCycle: 36, kind: .steady),
            ChargingEffectPhase(step: 4, stepsPerCycle: 12, kind: .burst)
        ] {
            let image = try XCTUnwrap(StatusIconRenderer.render(
                scene: scene,
                environment: StatusIconRenderEnvironment(size: 28, scale: 2,
                                                         foreground: CGColor(gray: 1, alpha: 1),
                                                         criticalColor: StatusIconRenderer.defaultCriticalColor),
                phase: phase
            ))
            frames.append(try PixelBuffer(image: image))
        }
        for (index, frame) in frames.enumerated() {
            assertMenuBarPixelConventions(frame, size: 28, scale: 2, label: "animation phase \(index)")
        }
        XCTAssertNotEqual(frames[0].bytes, frames[1].bytes, "steady phase changes only the animated battery artwork")
        XCTAssertNotEqual(frames[0].bytes, frames[2].bytes, "burst phase changes only the animated battery artwork")

        let charged = mappedScene(for: makeSnapshot(
            battery: BatteryStatus(rawPercentage: 100, isPresent: true, isCharging: true, isCharged: true,
                                   isLowPowerMode: false, isConnectedToPower: true),
            wifi: WiFiStatus(state: .connected, rssi: -62),
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Output")
        ))
        let chargedStatic = try menuBarPixels(scene: charged, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2)
        let chargedBurst = try menuBarPixels(
            scene: charged, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2,
            phase: ChargingEffectPhase(step: 4, stepsPerCycle: 12, kind: .burst)
        )
        XCTAssertTrue(chargedStatic.bytes == chargedBurst.bytes, "a completed battery has no charging animation")

        let disabled = mappedScene(for: active, configuration: configuration(
            battery: BatteryIconOptions(showsChargingEffect: false)
        ))
        let disabledStatic = try menuBarPixels(scene: disabled, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2)
        let disabledBurst = try menuBarPixels(
            scene: disabled, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2,
            phase: ChargingEffectPhase(step: 4, stepsPerCycle: 12, kind: .burst)
        )
        XCTAssertTrue(disabledStatic.bytes == disabledBurst.bytes, "disabled animation preserves static pixels")
    }

    func testFractionalMenuBarSizesKeepExactPixelLengthAndGeometryConventions() throws {
        let scene = mappedScene(for: PresentationFixtures.snapshot(rssi: -79, scalar: 0.74, muted: true))
        let standardScale = try menuBarPixels(scene: scene, foreground: CGColor(gray: 1, alpha: 1), size: 20, scale: 8)
        let fractionalSize = try menuBarPixels(scene: scene, foreground: CGColor(gray: 1, alpha: 1), size: 18.5, scale: 3)
        XCTAssertEqual(standardScale.width, 160)
        XCTAssertEqual(standardScale.height, 160)
        XCTAssertEqual(standardScale.bytes.count, 160 * 160 * 4)
        XCTAssertEqual(fractionalSize.width, 56)
        XCTAssertEqual(fractionalSize.height, 56)
        XCTAssertEqual(fractionalSize.bytes.count, 56 * 56 * 4)
        assertMenuBarPixelConventions(standardScale, size: 20, scale: 8, label: "20pt at 8x")
        assertMenuBarPixelConventions(fractionalSize, size: 18.5, scale: 3, label: "fractional logical size")
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

    func testUnknownSymbolAndUnreadableImageUseKnownSceneFallbacks() throws {
        let environment = StatusIconRenderEnvironment(
            size: 28,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1),
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        let unknown = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "status-trio-symbol-that-does-not-exist", variableValue: nil,
                           fallback: "dot.radiowaves.left.and.right"),
            color: .bluetooth,
            scale: 1
        )))
        let knownWaveFallback = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "dot.radiowaves.left.and.right", variableValue: 1, fallback: nil),
            color: .bluetooth,
            scale: 1
        )))
        let unknownPixels = try PixelBuffer(image: XCTUnwrap(StatusIconRenderer.render(
            scene: unknown, environment: environment
        )))
        let fallbackPixels = try PixelBuffer(image: XCTUnwrap(StatusIconRenderer.render(
            scene: knownWaveFallback, environment: environment
        )))
        XCTAssertEqual(unknownPixels.width, 56)
        XCTAssertEqual(unknownPixels.height, 56)
        XCTAssertEqual(unknownPixels.bytes, fallbackPixels.bytes,
                       "an unavailable symbol uses its explicitly declared available glyph")

        let missingImage = IconSceneState(center: .symbol(IconSymbolState(
            source: .image(url: URL(fileURLWithPath: "/tmp/status-trio-missing-device-icon.png"),
                           fallbackSymbol: "headphones"),
            color: .bluetooth,
            scale: 1
        )))
        let knownImageFallback = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "headphones", variableValue: 1, fallback: nil),
            color: .bluetooth,
            scale: 1
        )))
        let missingPixels = try PixelBuffer(image: XCTUnwrap(StatusIconRenderer.render(
            scene: missingImage, environment: environment
        )))
        let imageFallbackPixels = try PixelBuffer(image: XCTUnwrap(StatusIconRenderer.render(
            scene: knownImageFallback, environment: environment
        )))
        XCTAssertEqual(missingPixels.bytes, imageFallbackPixels.bytes,
                       "an unreadable image uses its explicitly declared fallback glyph")
    }

    func testKnownPickedSymbolWithoutDeviceKeepsDeclaredCenterGlyph() throws {
        let snapshot = PresentationFixtures.snapshot()
        let symbol = "headphones"
        XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil))
        let picked = configuration(bluetooth: BluetoothAudioIconOptions(
            replacesNetworkIcon: true,
            networkIconSymbolOverride: symbol
        ))
        let scene = mappedScene(for: snapshot, configuration: picked)
        XCTAssertEqual(scene.center, .symbol(IconSymbolState(
            source: .symbol(name: symbol, variableValue: nil, fallback: "dot.radiowaves.left.and.right"),
            color: .bluetooth,
            scale: BluetoothAudioIconOptions(replacesNetworkIcon: true,
                                             networkIconSymbolOverride: symbol).symbolScale
        )))
        let pixels = try menuBarPixels(scene: scene, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2)
        XCTAssertGreaterThan(pixels.alphaSum(inSVGRect: CGRect(x: 42, y: 55, width: 35, height: 35), size: 28, scale: 2),
                             100, "the picked headphones glyph occupies the fixed center slot")
    }

    func testReadableDeviceImageMapsAndRendersOnBothSurfaces() throws {
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
        let scene = mappedScene(for: snapshot, configuration: configuration(bluetooth: bluetooth))
        XCTAssertEqual(IconPresentationResourceResolver.inputs(snapshot: snapshot).audioIcon,
                       .image(url: url, fallbackSymbol: "headphones"))
        guard case .symbol(let center)? = scene.center else {
            return XCTFail("A readable Bluetooth resource must occupy the center slot")
        }
        XCTAssertEqual(center.source, .image(url: url, fallbackSymbol: "headphones"))
        let pixels = try menuBarPixels(scene: scene, foreground: CGColor(gray: 1, alpha: 1), size: 28, scale: 2)
        XCTAssertGreaterThan(pixels.alphaSum(inSVGRect: CGRect(x: 38, y: 43, width: 43, height: 42), size: 28, scale: 2),
                             100, "the resolved image resource occupies its fixed 42-unit center box")
        XCTAssertTrue(pixels.containsColor(red: 77.0 / 255.0, green: 163.0 / 255.0, blue: 1,
                                           tolerance: 0.08, minimumAlpha: 0.9),
                      "the Bluetooth image keeps its declared menu-bar tint")
        for style in [DockIconBackgroundStyle.dark, .light] {
            let dock = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
                scene: scene, backgroundStyle: style, pixelLength: 96
            )))
            let centerImagePixels = CGRect(x: 35, y: 30, width: 30, height: 34)
            XCTAssertGreaterThan(alphaSum(dock, inPixelRect: centerImagePixels), 100,
                                 "the device image stays in the Dock center glyph box: \(style)")
            let expectedBlue = style == .dark
                ? (red: 77.0 / 255.0, green: 163.0 / 255.0, blue: 1.0)
                : (red: 0.0, green: 102.0 / 255.0, blue: 204.0 / 255.0)
            XCTAssertTrue(containsColor(
                dock,
                inPixelRect: centerImagePixels,
                red: expectedBlue.red,
                green: expectedBlue.green,
                blue: expectedBlue.blue,
                tolerance: 0.1
            ), "the device image keeps the Dock palette tint: \(style)")
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

    func testBluetoothVolumeArcRetainsIndependentTintConventionOnDock() throws {
        let snapshot = makeSnapshot(volume: VolumeStatus(
            scalar: 0.72,
            isMuted: false,
            deviceName: "Headphones",
            currentDevice: PresentationFixtures.bluetoothDevice
        ))
        let options = configuration(
            volume: VolumeIconOptions(displayStyle: .arc),
            bluetooth: BluetoothAudioIconOptions(usesVolumeColor: true)
        )
        let scene = mappedScene(for: snapshot, configuration: options)
        let dark = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: scene, backgroundStyle: .dark, pixelLength: 96
        )))
        let light = try cgPixels(from: XCTUnwrap(DockIconRenderer.image(
            scene: scene, backgroundStyle: .light, pixelLength: 96
        )))
        XCTAssertTrue(dark.containsColor(red: 77.0 / 255.0, green: 163.0 / 255.0, blue: 1,
                                         tolerance: 0.08, minimumAlpha: 0.9),
                      "dark Dock retains the Bluetooth volume-arc tint")
        XCTAssertTrue(light.containsColor(red: 0, green: 102.0 / 255.0, blue: 204.0 / 255.0,
                                          tolerance: 0.1, minimumAlpha: 0.9),
                      "light Dock uses the established darker Bluetooth tint")
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

    private func menuBarPixels(
        scene: IconSceneState,
        foreground: CGColor,
        size: CGFloat,
        scale: CGFloat,
        phase: ChargingEffectPhase? = nil
    ) throws -> PixelBuffer {
        let environment = StatusIconRenderEnvironment(
            size: size,
            scale: scale,
            foreground: foreground,
            criticalColor: StatusIconRenderer.defaultCriticalColor
        )
        return try PixelBuffer(image: XCTUnwrap(StatusIconRenderer.render(
            scene: scene, environment: environment, phase: phase
        )))
    }

    private func cgPixels(from image: NSImage) throws -> PixelBuffer {
        try PixelBuffer(image: XCTUnwrap(XCTUnwrap(image.representations.first as? NSBitmapImageRep).cgImage))
    }

    private func assertMenuBarPixelConventions(
        _ pixels: PixelBuffer,
        size: CGFloat,
        scale: CGFloat,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let dimension = Int((size * scale).rounded(.up))
        XCTAssertEqual(pixels.width, dimension, "canvas width: \(label)", file: file, line: line)
        XCTAssertEqual(pixels.height, dimension, "canvas height: \(label)", file: file, line: line)
        XCTAssertEqual(pixels.bytes.count, dimension * dimension * 4, "complete RGBA buffer: \(label)", file: file, line: line)
        let fixedRegions: [(String, CGRect)] = [
            ("battery upper track", CGRect(x: 18, y: 11, width: 84, height: 22)),
            ("center connection slot", CGRect(x: 37, y: 48, width: 45, height: 43)),
            ("volume footer", CGRect(x: 33, y: 98, width: 54, height: 19))
        ]
        for (name, region) in fixedRegions {
            XCTAssertGreaterThan(
                pixels.alphaSum(inSVGRect: region, size: size, scale: scale),
                100,
                "\(name) must leave measurable ink at its fixed artwork location: \(label)",
                file: file,
                line: line
            )
        }
    }

    private func alphaSum(_ pixels: PixelBuffer, inPixelRect rect: CGRect) -> Int {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(pixels.width, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(pixels.height, Int(rect.maxY.rounded(.up)))
        guard minX < maxX, minY < maxY else { return 0 }
        return (minY..<maxY).reduce(0) { row, y in
            row + (minX..<maxX).reduce(0) { row, x in
                row + Int(pixels.rgba(x: x, y: y).alpha)
            }
        }
    }

    private func containsColor(
        _ pixels: PixelBuffer,
        inPixelRect rect: CGRect,
        red: Double,
        green: Double,
        blue: Double,
        tolerance: Double
    ) -> Bool {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(pixels.width, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(pixels.height, Int(rect.maxY.rounded(.up)))
        guard minX < maxX, minY < maxY else { return false }
        for y in minY..<maxY {
            for x in minX..<maxX {
                let pixel = pixels.rgba(x: x, y: y)
                guard pixel.alpha >= 240 else { continue }
                if abs(Double(pixel.red) / 255 - red) <= tolerance,
                   abs(Double(pixel.green) / 255 - green) <= tolerance,
                   abs(Double(pixel.blue) / 255 - blue) <= tolerance {
                    return true
                }
            }
        }
        return false
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

}
