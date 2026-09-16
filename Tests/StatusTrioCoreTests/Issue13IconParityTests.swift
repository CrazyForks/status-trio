import AppKit
import CoreGraphics
import Testing
@testable import StatusTrioCore

@MainActor
struct Issue13IconParityTests {
    @Test(
        "Special Wi-Fi connection marks follow the Wi-Fi symbol scale",
        .bug("https://github.com/lingyired/status-trio/issues/13"),
        arguments: [WiFiState.temporary, .shared]
    )
    func specialWiFiConnectionMarksFollowSymbolScale(_ state: WiFiState) throws {
        let normal = try renderedPixels(for: state, wifiScale: 1.0)
        let scaled = try renderedPixels(for: state, wifiScale: 1.5)
        let wifiRegion = CGRect(x: 20, y: 20, width: 80, height: 80)
        let normalAlpha = normal.alphaSum(
            inSVGRect: wifiRegion,
            size: 20,
            scale: 8
        )
        let scaledAlpha = scaled.alphaSum(
            inSVGRect: wifiRegion,
            size: 20,
            scale: 8
        )

        #expect(scaledAlpha > normalAlpha, "\(state)")
    }

    @Test(
        "Dock icon reflects the continuous volume arc style",
        .bug("https://github.com/lingyired/status-trio/issues/13")
    )
    func dockIconReflectsVolumeArcStyle() throws {
        let status = MenuBarStatus(snapshot: StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
        ))
        let dots = try dockPixels(
            for: status,
            volumeOptions: VolumeIconOptions(displayStyle: .dots)
        )
        let arc = try dockPixels(
            for: status,
            volumeOptions: VolumeIconOptions(displayStyle: .arc)
        )

        #expect(pixelsDiffer(dots, arc))
    }

    private func renderedPixels(
        for state: WiFiState,
        wifiScale: Double
    ) throws -> PixelBuffer {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: state, rssi: -50),
            volume: .placeholder
        )
        let image = try #require(StatusIconRenderer.render(
            snapshot: snapshot,
            size: 20,
            scale: 8,
            foreground: CGColor(gray: 1, alpha: 1),
            connectionOptions: ConnectionIconOptions(wifiScale: wifiScale)
        ))
        return try PixelBuffer(image: image)
    }

    private func dockPixels(
        for status: MenuBarStatus,
        volumeOptions: VolumeIconOptions
    ) throws -> PixelBuffer {
        let image = try #require(DockIconRenderer.image(
            status: status,
            volumeOptions: volumeOptions
        ))
        let representation = try #require(
            image.representations.first as? NSBitmapImageRep
        )
        return try PixelBuffer(image: try #require(representation.cgImage))
    }

    private func pixelsDiffer(_ lhs: PixelBuffer, _ rhs: PixelBuffer) -> Bool {
        lhs.bytes != rhs.bytes
    }
}
