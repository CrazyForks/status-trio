import AppKit
import CoreGraphics
import CoreText

enum StatusIconRenderer {
    private static let wifiSymbolCenter = CGPoint(
        x: StatusIconGeometry.canvas.midX,
        y: 64.0
    )

    // Keep the 7pt rounded Wi-Fi strokes fully inside the bitmap.
    private static let wifiCanvasBounds = CGRect(
        x: 31.5,
        y: 34.4,
        width: 56,
        height: 56
    )

    /// Unified optical alpha for all inactive tracks (battery groove, Wi-Fi muted signal, volume hidden dots).
    private static let inactiveTrackAlpha: CGFloat = 0.22
    private static let bluetoothBlueOnLightBackground = CGColor(
        red: 0,
        green: 102.0 / 255.0,
        blue: 204.0 / 255.0,
        alpha: 1
    )
    private static let bluetoothBlueOnDarkBackground = CGColor(
        red: 77.0 / 255.0,
        green: 163.0 / 255.0,
        blue: 1,
        alpha: 1
    )

    static func image(
        snapshot: StatusSnapshot,
        size: CGFloat,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard
    ) -> NSImage {
        image(
            menuBarStatus: MenuBarStatus(snapshot: snapshot),
            size: size,
            options: options,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions
        )
    }

    static func image(
        menuBarStatus: MenuBarStatus,
        size: CGFloat,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        appearance: NSAppearance? = nil
    ) -> NSImage {
        // Resolve colors while AppKit draws into each menu bar. A pre-rendered
        // bitmap would keep the first display's light or dark foreground.
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            var foreground: CGColor = CGColor(gray: 1, alpha: 1)
            var criticalColor: CGColor = Self.defaultCriticalColor

            if let appearance {
                appearance.performAsCurrentDrawingAppearance {
                    foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)?.cgColor
                        ?? CGColor(gray: 1, alpha: 1)
                    criticalColor = NSColor.systemRed.usingColorSpace(.deviceRGB)?.cgColor
                        ?? Self.defaultCriticalColor
                }
            } else {
                foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)?.cgColor
                    ?? CGColor(gray: 1, alpha: 1)
                criticalColor = NSColor.systemRed.usingColorSpace(.deviceRGB)?.cgColor
                    ?? Self.defaultCriticalColor
            }

            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(
                menuBarStatus: menuBarStatus,
                options: options,
                connectionOptions: connectionOptions,
                volumeOptions: volumeOptions,
                bluetoothAudioOptions: bluetoothAudioOptions,
                in: context,
                size: size,
                foreground: foreground,
                criticalColor: criticalColor
            )
            return true
        }
    }

    static func wifiImage(
        wifi: WiFiStatus,
        size: CGFloat,
        options: ConnectionIconOptions = .standard
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else { return image }

        context.saveGState()
        defer { context.restoreGState() }

        let scale = size / 56.0
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(
            x: -(wifiSymbolCenter.x - 28.0),
            y: -(wifiSymbolCenter.y - 28.0)
        )
        context.setLineCap(.round)
        context.setLineJoin(.round)

        drawWiFi(
            wifi,
            options: options,
            in: context,
            foreground: CGColor(gray: 1, alpha: 1)
        )
        image.isTemplate = true
        return image
    }

    static func render(
        snapshot: StatusSnapshot,
        size: CGFloat,
        scale: CGFloat,
        foreground: CGColor,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard
    ) -> CGImage? {
        render(
            menuBarStatus: MenuBarStatus(snapshot: snapshot),
            size: size,
            scale: scale,
            foreground: foreground,
            options: options,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions
        )
    }

    static func render(
        menuBarStatus: MenuBarStatus,
        size: CGFloat,
        scale: CGFloat,
        foreground: CGColor,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard
    ) -> CGImage? {
        guard size.isFinite, scale.isFinite, size > 0, scale > 0 else { return nil }

        let pixelLength = (size * scale).rounded(.up)
        guard pixelLength.isFinite,
              let pixelDimension = Int(exactly: pixelLength),
              pixelDimension > 0,
              pixelDimension <= Int.max / 4
        else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: pixelDimension,
            height: pixelDimension,
            bitsPerComponent: 8,
            bytesPerRow: pixelDimension * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        draw(
            menuBarStatus: menuBarStatus,
            options: options,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            in: context,
            size: size,
            foreground: foreground,
            criticalColor: defaultCriticalColor
        )
        return context.makeImage()
    }

    /// Draws the status glyph into an existing context, using the renderer's
    /// canvas coordinates. Avoids the intermediate bitmap that `render` creates.
    static func draw(
        menuBarStatus: MenuBarStatus,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        foreground: CGColor,
        in context: CGContext,
        origin: CGPoint,
        size: CGFloat
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        context.translateBy(x: origin.x, y: origin.y)
        draw(
            menuBarStatus: menuBarStatus,
            options: options,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            in: context,
            size: size,
            foreground: foreground,
            criticalColor: defaultCriticalColor
        )
    }

    private static func draw(
        menuBarStatus: MenuBarStatus,
        options: BatteryIconOptions,
        connectionOptions: ConnectionIconOptions,
        volumeOptions: VolumeIconOptions,
        bluetoothAudioOptions: BluetoothAudioIconOptions,
        in context: CGContext,
        size: CGFloat,
        foreground: CGColor,
        criticalColor: CGColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        let scale = size / StatusIconGeometry.canvas.width
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: scale, y: -scale)

        context.setLineCap(.round)
        context.setLineJoin(.round)

        drawBattery(
            menuBarStatus.battery,
            options: options,
            in: context,
            foreground: foreground,
            criticalColor: criticalColor
        )
        if let currentDevice = menuBarStatus.volume.currentDevice,
           StatusMappings.shouldReplaceNetworkIcon(
               currentDevice: currentDevice,
               wifi: menuBarStatus.wifi,
               connection: menuBarStatus.connection,
               options: bluetoothAudioOptions
           ) {
            drawBluetoothAudioDevice(
                currentDevice,
                options: bluetoothAudioOptions,
                in: context,
                foreground: foreground
            )
        } else if menuBarStatus.connection == .ethernet {
            if connectionOptions.showsWiFiIconForEthernet {
                drawStandardWiFi(menuBarStatus.wifi, wifiScale: connectionOptions.wifiScale, in: context, foreground: foreground)
            } else {
                drawEthernet(in: context, foreground: foreground)
            }
        } else {
            drawWiFi(
                menuBarStatus.wifi,
                options: connectionOptions,
                in: context,
                foreground: foreground
            )
        }
        drawVolume(
            menuBarStatus.volume,
            options: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            in: context,
            foreground: foreground
        )
    }

    private static func drawBattery(
        _ battery: BatteryStatus,
        options: BatteryIconOptions,
        in context: CGContext,
        foreground: CGColor,
        criticalColor: CGColor
    ) {
        let gapContent = StatusMappings.batteryGapContent(battery, options: options)
        let hasTopGap = gapContent != .empty
        let topGapWidth = switch gapContent {
        case .bolt, .plug: StatusIconGeometry.batteryChargingBoltTopGapWidth
        case .percentage, .empty: StatusIconGeometry.batteryValueTopGapWidth
        }

        context.setLineWidth(8)
        context.setStrokeColor(foreground.copy(alpha: inactiveTrackAlpha) ?? foreground)
        context.addPath(StatusIconGeometry.batteryTrack(
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        ))
        context.strokePath()

        let role = options.usesStatusColors
            ? StatusMappings.batteryColorRole(
                battery,
                criticalThreshold: options.criticalThreshold
            )
            : .foreground
        let arcColor = color(
            for: role,
            foreground: foreground,
            criticalColor: criticalColor
        )

        context.setStrokeColor(arcColor)
        context.addPath(StatusIconGeometry.batteryFill(
            progress: StatusMappings.batteryProgress(battery),
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        ))
        context.strokePath()

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 0.75),
            blur: 0.75,
            color: CGColor(gray: 0, alpha: 0.38)
        )
        defer { context.restoreGState() }

        let indicatorScale = batteryChargingBoltScale(textScale: options.textScale)

        switch gapContent {
        case .bolt:
            context.setFillColor(foreground)
            context.addPath(StatusIconGeometry.batteryChargingBolt(
                scale: indicatorScale
            ))
            context.fillPath()
        case .plug:
            drawBatteryPlug(
                boltScale: indicatorScale,
                foreground: foreground,
                in: context
            )
        case .percentage:
            drawBatteryPercentage(
                battery.percentage,
                color: foreground,
                fontSize: batteryValueFontSize(scale: options.textScale),
                in: context
            )
        case .empty:
            break
        }
    }

    /// Draws the plug at the bolt's optical size and center, so the arc's top
    /// gap reads the same whichever indicator is showing.
    private static func drawBatteryPlug(
        boltScale: CGFloat,
        foreground: CGColor,
        in context: CGContext
    ) {
        let boltHeight = StatusIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
        let targetHeight = boltHeight * boltScale * StatusIconGeometry.batteryPlugHeightScale
        guard targetHeight.isFinite, targetHeight > 0 else { return }

        drawOfficialSymbol(
            name: StatusIconGeometry.batteryPlugSymbolName,
            pointSize: batteryPlugPointSize(targetHeight: targetHeight),
            center: StatusIconGeometry.batteryTopIndicatorCenter(boltScale: boltScale),
            foreground: foreground,
            in: context
        )
    }

    private static func color(
        for role: BatteryColorRole,
        foreground: CGColor,
        criticalColor: CGColor
    ) -> CGColor {
        switch role {
        case .foreground:
            foreground
        case .critical:
            criticalColor
        case .charging:
            if usesDarkStatusPalette(foreground: foreground) {
                CGColor(red: 31.0 / 255.0, green: 143.0 / 255.0, blue: 61.0 / 255.0, alpha: 1)
            } else {
                CGColor(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1)
            }
        case .lowPower:
            if usesDarkStatusPalette(foreground: foreground) {
                CGColor(red: 201.0 / 255.0, green: 151.0 / 255.0, blue: 0, alpha: 1)
            } else {
                CGColor(red: 242.0 / 255.0, green: 185.0 / 255.0, blue: 0, alpha: 1)
            }
        }
    }

    private static func usesDarkStatusPalette(foreground: CGColor) -> Bool {
        guard let color = NSColor(cgColor: foreground)?.usingColorSpace(.deviceRGB) else {
            return false
        }
        return color.brightnessComponent < 0.5
    }

    private static func bluetoothColor(foreground: CGColor) -> CGColor {
        usesDarkStatusPalette(foreground: foreground)
            ? bluetoothBlueOnLightBackground
            : bluetoothBlueOnDarkBackground
    }

    private static func drawBatteryPercentage(
        _ percentage: Int,
        color: CGColor,
        fontSize: CGFloat,
        in context: CGContext
    ) {
        let font = batteryValueFont(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: -fontSize * 0.04,
            .foregroundColor: NSColor(cgColor: color) ?? .white
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: String(percentage), attributes: attributes)
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let baseline = StatusIconGeometry.batteryValueBaseline(fontSize: fontSize)

        context.setFillColor(color)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: baseline.x - width / 2, y: baseline.y)
        CTLineDraw(line, context)
    }

    private static func batteryValueFontSize(scale: Double) -> CGFloat {
        StatusIconGeometry.batteryValueBaseFontSize * CGFloat(scale)
    }

    private static func batteryChargingBoltScale(textScale: Double) -> CGFloat {
        let boltHeight = StatusIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
        let targetHeight = batteryTopIndicatorHeight(textScale: textScale)
        guard boltHeight.isFinite, boltHeight > 0, targetHeight > 0 else {
            return CGFloat(textScale / BatteryIconOptions.defaultTextScale)
                * StatusIconGeometry.batteryChargingBoltCalibration
        }
        return targetHeight / boltHeight
    }

    /// Height shared by every top-gap glyph. The bolt is calibrated to match the
    /// percentage numerals, and the plug matches the bolt.
    private static func batteryTopIndicatorHeight(textScale: Double) -> CGFloat {
        let fontSize = batteryValueFontSize(scale: textScale)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: "100",
                attributes: [.font: batteryValueFont(size: fontSize)]
            )
        )
        let glyphHeight = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds]).height
        guard glyphHeight.isFinite, glyphHeight > 0 else {
            return StatusIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
                * CGFloat(textScale / BatteryIconOptions.defaultTextScale)
                * StatusIconGeometry.batteryChargingBoltCalibration
        }
        return CGFloat(glyphHeight) * StatusIconGeometry.batteryChargingBoltCalibration
    }

    /// Glyph height per point of symbol size, measured once. SF Symbols report
    /// sizes rounded to whole points, so this reference size stays large enough
    /// for the rounding to be negligible.
    private static let batteryPlugHeightPerPoint: CGFloat = {
        let referencePointSize: CGFloat = 200
        guard let height = configuredSymbol(
            name: StatusIconGeometry.batteryPlugSymbolName,
            pointSize: referencePointSize,
            foreground: .labelColor
        )?.size.height, height.isFinite, height > 0 else {
            return 1.34
        }
        return height / referencePointSize
    }()

    private static func batteryPlugPointSize(targetHeight: CGFloat) -> CGFloat {
        let fallbackPointSize: CGFloat = 38
        let pointSize = targetHeight / batteryPlugHeightPerPoint
        return pointSize.isFinite && pointSize > 0 ? pointSize : fallbackPointSize
    }

    private static var defaultCriticalColor: CGColor {
        CGColor(red: 255.0 / 255.0, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
    }

    private static func batteryValueFont(size: CGFloat) -> NSFont {
        let fallback = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = fallback.fontDescriptor.withDesign(.rounded) else {
            return fallback
        }
        return NSFont(descriptor: descriptor, size: size) ?? fallback
    }

    private static func drawEthernet(
        in context: CGContext,
        foreground: CGColor
    ) {
        context.setStrokeColor(foreground)
        context.setLineWidth(StatusIconGeometry.ethernetStrokeWidth)
        for path in StatusIconGeometry.ethernetChevrons() {
            context.addPath(path)
            context.strokePath()
        }

        context.setFillColor(foreground)
        let radius = StatusIconGeometry.ethernetDotRadius
        for point in StatusIconGeometry.ethernetDots() {
            context.fillEllipse(
                in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
        }
    }

    private static func drawBluetoothAudioDevice(
        _ device: AudioOutputDevice,
        options: BluetoothAudioIconOptions,
        in context: CGContext,
        foreground: CGColor
    ) {
        let tint = bluetoothColor(foreground: foreground)
        let scale = bluetoothSymbolScale(options.symbolScale)
        let pointSize = 38 * scale
        let maxDimension = 42 * scale

        switch AudioOutputDeviceIcon.source(for: device) {
        case let .symbol(name):
            drawOfficialSymbol(
                name: name,
                pointSize: pointSize,
                foreground: tint,
                in: context
            )
        case let .image(url):
            guard let image = NSImage(contentsOf: url) else {
                drawOfficialSymbol(
                    name: "headphones",
                    pointSize: pointSize,
                    foreground: tint,
                    in: context
                )
                return
            }
            drawTintedImage(
                image,
                maxDimension: maxDimension,
                center: wifiSymbolCenter,
                tint: tint,
                in: context
            )
        }
    }

    private static func bluetoothSymbolScale(_ symbolScale: Double) -> CGFloat {
        guard symbolScale.isFinite,
              symbolScale > 0,
              BluetoothAudioIconOptions.defaultSymbolScale > 0 else {
            return 1
        }
        return CGFloat(symbolScale / BluetoothAudioIconOptions.defaultSymbolScale)
    }

    private static func drawTintedImage(
        _ image: NSImage,
        maxDimension: CGFloat,
        center: CGPoint,
        tint: CGColor,
        in context: CGContext
    ) {
        let sourceSize = image.size
        guard sourceSize.width.isFinite,
              sourceSize.height.isFinite,
              sourceSize.width > 0,
              sourceSize.height > 0 else {
            return
        }

        let scale = min(
            maxDimension / sourceSize.width,
            maxDimension / sourceSize.height
        )
        let size = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        let targetRect = CGRect(
            x: center.x - size.width / 2,
            y: -(center.y + size.height / 2),
            width: size.width,
            height: size.height
        )

        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: 1, y: -1)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        image.draw(
            in: targetRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        context.setFillColor(tint)
        context.setBlendMode(.sourceIn)
        context.fill(targetRect)
        context.endTransparencyLayer()
    }

    private static func drawWiFi(
        _ wifi: WiFiStatus,
        options: ConnectionIconOptions,
        in context: CGContext,
        foreground: CGColor
    ) {
        let basePointSize: CGFloat = 38.0
        let symbolPointSize = basePointSize * CGFloat(options.wifiScale)

        switch wifi.state {
        case .connected:
            drawStandardWiFi(wifi, wifiScale: options.wifiScale, in: context, foreground: foreground)
        case .notAssociated:
            drawOfficialSymbol(
                name: "wifi",
                variableValue: 0.0,
                pointSize: symbolPointSize,
                foreground: foreground,
                in: context
            )
        case .off, .unavailable:
            drawOfficialSymbol(
                name: "wifi.slash",
                variableValue: 1.0,
                pointSize: symbolPointSize,
                foreground: foreground,
                in: context
            )
        case .noInternet:
            drawOfficialSymbol(
                name: "wifi.exclamationmark",
                variableValue: 1.0,
                pointSize: symbolPointSize,
                foreground: foreground,
                in: context
            )
        case .hotspot where options.showsWiFiIconForHotspot:
            drawStandardWiFi(wifi, wifiScale: options.wifiScale, in: context, foreground: foreground)
        case .hotspot:
            drawOfficialSymbol(
                name: "personalhotspot",
                variableValue: 1.0,
                pointSize: symbolPointSize,
                foreground: foreground,
                in: context
            )
        case .temporary where options.showsWiFiIconForTemporaryConnection:
            drawStandardWiFi(wifi, wifiScale: options.wifiScale, in: context, foreground: foreground)
        case .temporary:
            drawTemporaryConnectionMark(
                wifiScale: options.wifiScale,
                in: context,
                foreground: foreground
            )
        case .shared where options.showsWiFiIconForInternetSharing:
            drawStandardWiFi(wifi, wifiScale: options.wifiScale, in: context, foreground: foreground)
        case .shared:
            drawSharedConnectionMark(
                wifiScale: options.wifiScale,
                in: context,
                foreground: foreground
            )
        }
    }

    private static func drawTemporaryConnectionMark(
        wifiScale: Double,
        in context: CGContext,
        foreground: CGColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        applyWiFiScale(wifiScale, in: context)

        context.setFillColor(foreground)
        context.setStrokeColor(foreground)
        context.setLineWidth(7)
        context.addPath(StatusIconGeometry.temporaryWedge())
        context.drawPath(using: .fillStroke)

        context.saveGState()
        context.setBlendMode(.clear)
        context.setLineWidth(2.5)
        context.addPath(StatusIconGeometry.temporaryScreenOutline())
        context.strokePath()
        context.addPath(StatusIconGeometry.temporaryScreenStand())
        context.fillPath()
        context.restoreGState()
    }

    private static func drawSharedConnectionMark(
        wifiScale: Double,
        in context: CGContext,
        foreground: CGColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        applyWiFiScale(wifiScale, in: context)

        context.setFillColor(foreground)
        context.setStrokeColor(foreground)
        context.setLineWidth(7)
        context.addPath(StatusIconGeometry.sharedWedge())
        context.drawPath(using: .fillStroke)

        context.saveGState()
        context.setBlendMode(.clear)
        context.addPath(StatusIconGeometry.sharedArrowCutout())
        context.fillPath()
        context.restoreGState()
    }

    private static func applyWiFiScale(_ wifiScale: Double, in context: CGContext) {
        let scale = CGFloat(wifiScale)
        guard scale.isFinite, scale > 0, scale != 1 else { return }

        let pivot = wifiSymbolCenter
        context.translateBy(x: pivot.x, y: pivot.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -pivot.x, y: -pivot.y)
    }

    private static func drawStandardWiFi(
        _ wifi: WiFiStatus,
        wifiScale: Double = 1.0,
        in context: CGContext,
        foreground: CGColor
    ) {
        let basePointSize: CGFloat = 38.0
        let symbolPointSize = basePointSize * CGFloat(wifiScale)
        let bars = StatusMappings.wifiBars(rssi: wifi.rssi)
        if bars == 0 {
            let mutedColor = foreground.copy(alpha: inactiveTrackAlpha) ?? foreground
            drawOfficialSymbol(
                name: "wifi",
                variableValue: 0.0,
                pointSize: symbolPointSize,
                foreground: mutedColor,
                in: context
            )
        } else {
            let variableValue: Double = switch bars {
            case 3: 1.0
            case 2: 0.66
            case 1: 0.33
            default: 0.0
            }
            drawOfficialSymbol(
                name: "wifi",
                variableValue: variableValue,
                pointSize: symbolPointSize,
                foreground: foreground,
                in: context
            )
        }
    }

    private static func drawOfficialSymbol(
        name: String,
        variableValue: Double = 1.0,
        pointSize: CGFloat,
        center: CGPoint = wifiSymbolCenter,
        foreground: CGColor,
        in context: CGContext
    ) {
        guard let symbol = configuredSymbol(
            name: name,
            variableValue: variableValue,
            pointSize: pointSize,
            foreground: NSColor(cgColor: foreground) ?? .labelColor
        ) else { return }

        context.saveGState()
        defer { context.restoreGState() }

        let gc = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = gc

        context.scaleBy(x: 1, y: -1)

        let targetRect = CGRect(
            x: center.x - symbol.size.width / 2,
            y: -(center.y + symbol.size.height / 2),
            width: symbol.size.width,
            height: symbol.size.height
        )
        symbol.draw(in: targetRect)
    }

    private static func configuredSymbol(
        name: String,
        variableValue: Double = 1.0,
        pointSize: CGFloat,
        foreground: NSColor
    ) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(hierarchicalColor: foreground))

        return NSImage(
            systemSymbolName: name,
            variableValue: variableValue,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(config)
    }

    private static func drawVolume(
        _ volume: MenuBarVolumeStatus,
        options: VolumeIconOptions,
        bluetoothAudioOptions: BluetoothAudioIconOptions,
        in context: CGContext,
        foreground: CGColor
    ) {
        let hiddenColor = foreground.copy(alpha: inactiveTrackAlpha) ?? foreground
        let activeColor = bluetoothAudioOptions.usesVolumeColor
            && volume.currentDevice?.isBluetoothAudio == true
            ? bluetoothColor(foreground: foreground)
            : foreground

        switch options.displayStyle {
        case .dots:
            let level = StatusMappings.volumeSteps(scalar: volume.scalar, isMuted: volume.isMuted) ?? 0
            for (index, point) in StatusIconGeometry.volumeDots().enumerated() {
                context.setFillColor(index < level ? activeColor : hiddenColor)
                let radius = StatusIconGeometry.volumeDotRadius
                context.fillEllipse(
                    in: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }
        case .arc:
            // Continuous arc bounded between Dot 0 (left, ~122°) and Dot 3 (right, ~59°)
            context.setLineWidth(7)
            context.setLineCap(.round)
            context.setStrokeColor(hiddenColor)
            context.addPath(StatusIconGeometry.volumeArcTrack())
            context.strokePath()

            guard !volume.isMuted, let scalar = volume.scalar, scalar > 0 else { return }
            context.setStrokeColor(activeColor)
            context.addPath(StatusIconGeometry.volumeArcFill(progress: scalar))
            context.strokePath()
        }
    }
}
