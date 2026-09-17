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
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
        context.saveGState()
        context.textPosition = CGPoint(x: topLeft.x, y: topLeft.y - CTFontGetAscent(font))
        CTLineDraw(line, context)
        context.restoreGState()
    }

    static func textWidth(of text: String, font: CTFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
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
