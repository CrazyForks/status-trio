import AppKit
import CoreGraphics

enum DockIconRenderer {
    static let logicalSize: CGFloat = 512
    static let pixelSize = 1024

    // Geometry mirrors Support/AppIcon.svg.
    private static let bodyRect = CGRect(x: 64, y: 64, width: 896, height: 896)
    private static let bodyCornerRadius: CGFloat = 210
    private static let borderRect = CGRect(x: 65, y: 65, width: 894, height: 894)
    private static let borderCornerRadius: CGFloat = 209

    // SVG coordinates use a top-left origin; AppKit bitmaps use a bottom-left one.
    private static let glyphSVGOrigin = CGPoint(x: 194.8, y: 171.84)
    private static let glyphSVGSize: CGFloat = 672

    // Build colors in the bitmap's own space so AppIcon.svg's hex values survive
    // without a Generic RGB to Device RGB conversion.
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    private static func color(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGColor {
        CGColor(
            colorSpace: colorSpace,
            components: [red, green, blue, 1]
        ) ?? CGColor(gray: 0, alpha: 1)
    }

    static func image(
        status: MenuBarStatus,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard
    ) -> NSImage? {
        guard let glyph = StatusIconRenderer.render(
            menuBarStatus: status,
            size: glyphSVGSize,
            scale: 1,
            foreground: CGColor(gray: 1, alpha: 1),
            options: options,
            connectionOptions: connectionOptions
        ) else {
            return nil
        }

        let canvasLength = CGFloat(pixelSize)
        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: pixelSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.addPath(roundedRect(
            bodyRect,
            cornerRadius: bodyCornerRadius
        ))
        context.setFillColor(color(red: 21.0 / 255.0, green: 21.0 / 255.0, blue: 23.0 / 255.0))
        context.fillPath()

        context.addPath(roundedRect(
            borderRect,
            cornerRadius: borderCornerRadius
        ))
        context.setStrokeColor(color(red: 58.0 / 255.0, green: 58.0 / 255.0, blue: 61.0 / 255.0))
        context.setLineWidth(2)
        context.strokePath()

        context.draw(
            glyph,
            in: CGRect(
                x: glyphSVGOrigin.x,
                y: canvasLength - glyphSVGOrigin.y - glyphSVGSize,
                width: glyphSVGSize,
                height: glyphSVGSize
            )
        )

        guard let output = context.makeImage() else { return nil }

        let representation = NSBitmapImageRep(cgImage: output)
        representation.size = NSSize(width: logicalSize, height: logicalSize)

        let image = NSImage(size: NSSize(width: logicalSize, height: logicalSize))
        image.addRepresentation(representation)
        image.isTemplate = false
        return image
    }

    private static func roundedRect(_ rect: CGRect, cornerRadius: CGFloat) -> CGPath {
        CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }
}
