import CoreGraphics
import XCTest
@testable import StatusTrioCore

final class Issue30WiFiAlignmentTests: XCTestCase {
    func testWiFiGlyphIsHorizontallyCenteredInMenuBarIcon() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -50),
            volume: .placeholder
        )
        let image = try XCTUnwrap(StatusIconRenderer.render(
            snapshot: snapshot,
            size: 120,
            scale: 4,
            foreground: CGColor(gray: 1, alpha: 1)
        ))
        let pixels = try PixelBuffer(image: image)
        let wifiRegion = CGRect(x: 30, y: 40, width: 60, height: 38)
        let visibleCenterX = try XCTUnwrap(
            pixels.horizontalAlphaCenter(inSVGRect: wifiRegion, size: 120, scale: 4)
        )

        XCTAssertEqual(
            visibleCenterX,
            StatusIconGeometry.canvas.midX,
            accuracy: 0.45,
            "Wi-Fi ink should be centered on the canvas"
        )
    }
}

private extension PixelBuffer {
    func horizontalAlphaCenter(
        inSVGRect rect: CGRect,
        size: CGFloat,
        scale: CGFloat
    ) -> CGFloat? {
        let pixelsPerSVGUnit = size * scale / StatusIconGeometry.canvas.width
        let minX = max(0, Int((rect.minX * pixelsPerSVGUnit).rounded(.down)))
        let maxX = min(width, Int((rect.maxX * pixelsPerSVGUnit).rounded(.up)))
        let minY = max(0, Int((rect.minY * pixelsPerSVGUnit).rounded(.down)))
        let maxY = min(height, Int((rect.maxY * pixelsPerSVGUnit).rounded(.up)))

        guard minX < maxX, minY < maxY else { return nil }

        var weightedX = 0.0
        var totalAlpha = 0.0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let alpha = Double(rgba(x: x, y: y).alpha)
                guard alpha > 0 else { continue }
                weightedX += (Double(x) + 0.5) / Double(pixelsPerSVGUnit) * alpha
                totalAlpha += alpha
            }
        }

        guard totalAlpha > 0 else { return nil }
        return CGFloat(weightedX / totalAlpha)
    }
}
