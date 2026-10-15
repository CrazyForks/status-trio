import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import StatusTrioCore

/// Icon files for the input-source rendering tests.
///
/// Input sources hand their icon over as a file (`kTISPropertyIconImageURL`), so
/// the fixtures are real files on disk: the renderer caches the decode by URL,
/// and an in-memory image would skip that path.
enum InputSourceIconFixtures {
    enum Background {
        case transparent
        case opaque
    }

    /// Writes a PNG whose inked area sits deliberately off the bitmap's centre,
    /// so a box-centred draw and an ink-centred draw land in different places.
    /// A symmetric fixture could pass while the layout is wrong.
    static func writeIcon(
        pixelWidth: Int,
        pixelHeight: Int,
        inkRect: CGRect,
        background: Background = .transparent
    ) throws -> URL {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        if background == .opaque {
            context.setFillColor(CGColor(gray: 0.2, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(inkRect)

        let cgImage = try XCTUnwrap(context.makeImage())
        let png = try XCTUnwrap(
            NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-input-source-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }
}

extension PixelBuffer {
    /// Edge-to-edge midpoint of the opaque ink in the icon's own scene units,
    /// independent of how much faint anti-aliasing each platform includes.
    func horizontalAlphaMidpoint(size: CGFloat, scale: CGFloat) -> CGFloat? {
        let pixelsPerSVGUnit = size * scale / StatusIconGeometry.canvas.width
        var minX = width
        var maxX = -1
        for y in 0..<height {
            for x in 0..<width where rgba(x: x, y: y).alpha > 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        guard minX <= maxX else { return nil }
        return (CGFloat(minX) + CGFloat(maxX) + 1) / 2 / pixelsPerSVGUnit
    }
}
