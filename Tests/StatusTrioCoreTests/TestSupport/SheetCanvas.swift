import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shared drawing surface for the generated README sheets.
enum SheetCanvas {
    enum CanvasError: Error {
        case contextUnavailable
        case imageUnavailable
        case encoderUnavailable
    }

    static func color(
        _ red: CGFloat,
        _ green: CGFloat,
        _ blue: CGFloat,
        _ alpha: CGFloat = 1
    ) -> CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    static var ink: CGColor { color(0.11, 0.11, 0.12) }
    static var mutedInk: CGColor { color(0.42, 0.42, 0.45) }
    static var hairline: CGColor { color(0.90, 0.90, 0.92) }
    static var chipFill: CGColor { color(0.949, 0.949, 0.965) }
    static var pageFill: CGColor { color(1, 1, 1) }

    /// Colors for one appearance, mirroring how the app resolves its own
    /// foreground and track colors.
    struct Palette {
        let page: CGColor
        let ink: CGColor
        let mutedInk: CGColor
        let hairline: CGColor
        let chip: CGColor
        let glyph: CGColor
        let batteryTint: CGColor
        let networkTint: CGColor
        let bluetoothTint: CGColor
        let volumeTint: CGColor

        static var light: Palette {
            Palette(
                page: color(1, 1, 1),
                ink: color(0.11, 0.11, 0.12),
                mutedInk: color(0.42, 0.42, 0.45),
                hairline: color(0.90, 0.90, 0.92),
                chip: color(0.949, 0.949, 0.965),
                glyph: color(0, 0, 0),
                batteryTint: color(0.20, 0.78, 0.35),
                networkTint: color(0.00, 0.48, 1.00),
                bluetoothTint: color(0, 102.0 / 255.0, 204.0 / 255.0),
                volumeTint: color(0.20, 0.70, 0.85)
            )
        }

        static var dark: Palette {
            Palette(
                page: color(0.11, 0.11, 0.12),
                ink: color(0.949, 0.949, 0.965),
                mutedInk: color(0.60, 0.60, 0.62),
                hairline: color(0.24, 0.24, 0.25),
                chip: color(0.17, 0.17, 0.18),
                glyph: color(1, 1, 1),
                batteryTint: color(0.19, 0.82, 0.35),
                networkTint: color(0.04, 0.52, 1.00),
                bluetoothTint: color(77.0 / 255.0, 163.0 / 255.0, 1),
                volumeTint: color(0.39, 0.82, 1.00)
            )
        }
    }

    static func font(_ name: String, _ size: CGFloat) -> CTFont {
        CTFontCreateWithName(name as CFString, size, nil)
    }

    static func makeContext(width: CGFloat, height: CGFloat, scale: CGFloat) throws -> CGContext {
        let pixelWidth = Int((width * scale).rounded())
        let pixelHeight = Int((height * scale).rounded())

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CanvasError.contextUnavailable
        }

        context.scaleBy(x: scale, y: scale)
        context.setShouldAntialias(true)
        return context
    }

    static func draw(
        _ text: String,
        font: CTFont,
        color: CGColor,
        topLeft: CGPoint,
        in context: CGContext
    ) {
        context.saveGState()
        context.textPosition = CGPoint(x: topLeft.x, y: topLeft.y - CTFontGetAscent(font))
        CTLineDraw(line(of: text, font: font, color: color), context)
        context.restoreGState()
    }

    /// Draws a line with an explicit baseline in the context's own
    /// coordinates, so a small label can share the baseline of a larger one.
    static func draw(
        _ text: String,
        font: CTFont,
        color: CGColor,
        baseline: CGFloat,
        x: CGFloat,
        in context: CGContext
    ) {
        context.saveGState()
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line(of: text, font: font, color: color), context)
        context.restoreGState()
    }

    /// The bilingual heading used by the generated sheets: an accent bar that
    /// spans the Chinese glyphs, the Chinese title, and the English label on
    /// the same baseline.
    ///
    /// `topY` is the heading's distance from the top of the sheet. The bar is
    /// measured from `inkBounds`, because the font's line box is far taller
    /// than the glyphs and a bar drawn from it floats above the text.
    static func drawSectionHeading(
        zh: String,
        en: String,
        tint: CGColor,
        ink: CGColor,
        mutedInk: CGColor,
        left: CGFloat,
        topY: CGFloat,
        totalHeight: CGFloat,
        in context: CGContext
    ) {
        let zhFont = font("PingFangSC-Semibold", 14)
        let enFont = font("HelveticaNeue-Medium", 12)
        let baseline = totalHeight - (topY + textInset) - CTFontGetAscent(zhFont)
        let bounds = inkBounds(of: zh, font: zhFont)

        context.saveGState()
        defer { context.restoreGState() }

        context.setFillColor(tint)
        context.addPath(roundedRect(
            CGRect(
                x: left,
                y: baseline + bounds.minY,
                width: 3,
                height: bounds.height
            ),
            cornerRadius: 1.5
        ))
        context.fillPath()

        draw(zh, font: zhFont, color: ink, baseline: baseline, x: left + 12, in: context)
        draw(
            en,
            font: enFont,
            color: mutedInk,
            baseline: baseline,
            x: left + 12 + textWidth(of: zh, font: zhFont) + 8,
            in: context
        )
    }

    /// Distance from a heading's top edge to the top of its glyphs.
    private static let textInset: CGFloat = 12

    /// The glyph ink box of one line, measured from its baseline in text space
    /// (y up). Decorations line up with the letters instead of with the font's
    /// line box.
    static func inkBounds(of text: String, font: CTFont) -> CGRect {
        let bounds = CTLineGetImageBounds(line(of: text, font: font), nil)
        guard !bounds.isNull, !bounds.isEmpty, bounds.height > 0 else {
            return CGRect(
                x: 0,
                y: -CTFontGetDescent(font),
                width: 0,
                height: CTFontGetAscent(font) + CTFontGetDescent(font)
            )
        }
        return bounds
    }

    private static func line(
        of text: String,
        font: CTFont,
        color: CGColor? = nil
    ) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if let color {
            attributes[.foregroundColor] = color
        }
        return CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
    }

    static func textWidth(of text: String, font: CTFont) -> CGFloat {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(
            line(of: text, font: font),
            &ascent,
            &descent,
            &leading
        )
        return CGFloat(width)
    }

    static func roundedRect(
        _ rect: CGRect,
        cornerRadius: CGFloat
    ) -> CGPath {
        CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }

    static func pngData(_ context: CGContext) throws -> Data {
        guard let image = context.makeImage() else { throw CanvasError.imageUnavailable }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CanvasError.encoderUnavailable
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CanvasError.encoderUnavailable }
        return data as Data
    }
}
