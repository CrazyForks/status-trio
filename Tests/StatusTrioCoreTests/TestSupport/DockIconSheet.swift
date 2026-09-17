import AppKit
import CoreGraphics
import Foundation
@testable import StatusTrioCore

/// Renders the Dock icon sheet (dark, light, and clear backgrounds) used by the
/// READMEs. Every tile comes from `DockIconRenderer`.
@MainActor
enum DockIconSheet {
    enum SheetError: Error {
        case iconUnavailable
        case gradientUnavailable
    }

    struct Variant {
        let zh: String
        let en: String
        let style: DockIconBackgroundStyle
    }

    private static let margin: CGFloat = 36
    private static let panelWidth: CGFloat = 262
    private static let panelHeight: CGFloat = 268
    private static let panelSpacing: CGFloat = 18
    private static let iconSize: CGFloat = 190
    private static let titleHeight: CGFloat = 96
    private static let labelHeight: CGFloat = 58
    private static let footerHeight: CGFloat = 58

    private static var totalWidth: CGFloat {
        margin * 2 + panelWidth * 3 + panelSpacing * 2
    }

    private static var totalHeight: CGFloat {
        titleHeight + panelHeight + labelHeight + footerHeight
    }

    static var variants: [Variant] {
        [
            Variant(zh: "深色背景", en: "Dark background", style: .dark),
            Variant(zh: "浅色背景", en: "Light background", style: .light),
            Variant(zh: "透明背景", en: "Clear background", style: .clear)
        ]
    }

    /// A charging battery keeps the green accent visible in every variant.
    private static var status: MenuBarStatus {
        MenuBarStatus(
            battery: BatteryStatus(
                rawPercentage: 76,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: WiFiStatus(state: .connected, rssi: -52),
            connection: .wifi,
            volume: MenuBarVolumeStatus(scalar: 0.6, isMuted: false, deviceName: nil)
        )
    }

    static func pngData(scale: CGFloat = 2) throws -> Data {
        let context = try SheetCanvas.makeContext(width: totalWidth, height: totalHeight, scale: scale)
        context.setFillColor(SheetCanvas.pageFill)
        context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))

        let flip: (CGFloat) -> CGFloat = { totalHeight - $0 }

        SheetCanvas.draw(
            "Status Trio 程序坞图标",
            font: SheetCanvas.font("PingFangSC-Semibold", 21),
            color: SheetCanvas.ink,
            topLeft: CGPoint(x: margin, y: flip(38)),
            in: context
        )
        SheetCanvas.draw(
            "Dock icon backgrounds · drawn by the app's own renderer",
            font: SheetCanvas.font("HelveticaNeue", 12),
            color: SheetCanvas.mutedInk,
            topLeft: CGPoint(x: margin, y: flip(64)),
            in: context
        )

        for (index, variant) in variants.enumerated() {
            let x = margin + CGFloat(index) * (panelWidth + panelSpacing)
            try drawPanel(variant, left: x, topY: titleHeight, totalHeight: totalHeight, in: context)
            drawLabel(variant, left: x, topY: titleHeight + panelHeight + 16, totalHeight: totalHeight, in: context)
        }

        SheetCanvas.draw(
            "深色 / 浅色在「设置 › 应用图标 › Dock 图标背景」中选择；透明对应系统「图标与小组件样式」为透明时的近似效果。",
            font: SheetCanvas.font("PingFangSC-Regular", 11),
            color: SheetCanvas.mutedInk,
            topLeft: CGPoint(x: margin, y: flip(totalHeight - footerHeight + 24)),
            in: context
        )
        SheetCanvas.draw(
            "Choose dark or light in Settings › App Icon › Dock icon background; clear approximates the system's Clear icon style.",
            font: SheetCanvas.font("HelveticaNeue", 11),
            color: SheetCanvas.mutedInk,
            topLeft: CGPoint(x: margin, y: flip(totalHeight - footerHeight + 42)),
            in: context
        )

        return try SheetCanvas.pngData(context)
    }

    private static func drawPanel(
        _ variant: Variant,
        left: CGFloat,
        topY: CGFloat,
        totalHeight: CGFloat,
        in context: CGContext
    ) throws {
        let flip: (CGFloat) -> CGFloat = { totalHeight - $0 }
        let panel = CGRect(x: left, y: flip(topY + panelHeight), width: panelWidth, height: panelHeight)

        // Stand-in for a wallpaper behind the Dock, so the clear tile reads as
        // translucent instead of as a plain white square.
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                SheetCanvas.color(0.93, 0.93, 0.95),
                SheetCanvas.color(0.76, 0.76, 0.82)
            ] as CFArray,
            locations: [0, 1]
        ) else {
            throw SheetError.gradientUnavailable
        }

        context.saveGState()
        context.addPath(SheetCanvas.roundedRect(panel, cornerRadius: 18))
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: panel.minX, y: panel.maxY),
            end: CGPoint(x: panel.minX, y: panel.minY),
            options: []
        )
        context.restoreGState()

        context.setStrokeColor(SheetCanvas.hairline)
        context.setLineWidth(1)
        context.addPath(SheetCanvas.roundedRect(panel.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 18))
        context.strokePath()

        guard let image = DockIconRenderer.image(status: status, backgroundStyle: variant.style) else {
            throw SheetError.iconUnavailable
        }

        var proposed = CGRect(origin: .zero, size: image.size)
        guard let tile = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw SheetError.iconUnavailable
        }

        let inset = (panelWidth - iconSize) / 2
        context.draw(
            tile,
            in: CGRect(
                x: left + inset,
                y: flip(topY + (panelHeight - iconSize) / 2 + iconSize),
                width: iconSize,
                height: iconSize
            )
        )
    }

    private static func drawLabel(
        _ variant: Variant,
        left: CGFloat,
        topY: CGFloat,
        totalHeight: CGFloat,
        in context: CGContext
    ) {
        let flip: (CGFloat) -> CGFloat = { totalHeight - $0 }
        let zhFont = SheetCanvas.font("PingFangSC-Semibold", 14)
        let enFont = SheetCanvas.font("HelveticaNeue", 11.5)

        let zhWidth = SheetCanvas.textWidth(of: variant.zh, font: zhFont)
        SheetCanvas.draw(
            variant.zh,
            font: zhFont,
            color: SheetCanvas.ink,
            topLeft: CGPoint(x: left + (panelWidth - zhWidth) / 2, y: flip(topY + 14)),
            in: context
        )

        let enWidth = SheetCanvas.textWidth(of: variant.en, font: enFont)
        SheetCanvas.draw(
            variant.en,
            font: enFont,
            color: SheetCanvas.mutedInk,
            topLeft: CGPoint(x: left + (panelWidth - enWidth) / 2, y: flip(topY + 36)),
            in: context
        )
    }
}
