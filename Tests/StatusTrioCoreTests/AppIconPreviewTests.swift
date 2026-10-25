import AppKit
import XCTest
@testable import StatusTrioCore

/// Writes the 1024px App Icon preview with Bluetooth-colored volume dots:
///
/// ```bash
/// STATUS_TRIO_APP_ICON_PREVIEW=/tmp/status-trio-app-icon-preview.png \
///   swift test --filter AppIconPreviewTests
/// ```
///
/// The Icon Composer artwork for the bundle icon's light and dark appearances
/// is written to `Support/AppIcon.icon/Assets` the same way:
///
/// ```bash
/// STATUS_TRIO_APP_ICON_ARTWORK_DIR=Support/AppIcon.icon/Assets \
///   swift test --filter AppIconPreviewTests
/// ```
@MainActor
final class AppIconPreviewTests: XCTestCase {
    private static let artworkStyles: [(style: DockIconBackgroundStyle, fileName: String)] = [
        (.light, "AppIcon-light.png"),
        (.dark, "AppIcon-dark.png")
    ]

    func testPreviewUsesTheChargingWiFiStateWithBluetoothVolumeColor() {
        let state = AppIconPreview.state

        XCTAssertTrue(state.status.battery.isCharging)
        XCTAssertEqual(state.status.wifi.state, .connected)
        XCTAssertEqual(state.status.volume.currentDevice, SheetFixtures.bluetoothDevice)
        XCTAssertTrue(state.bluetoothAudioOptions.usesVolumeColor)
        XCTAssertFalse(state.bluetoothAudioOptions.replacesNetworkIcon)
        XCTAssertEqual(state.backgroundStyle, .dark)
    }

    func testPreviewIsASquare1024PixelPngWithTransparentCorners() throws {
        let data = try AppIconPreview.pngData()
        let image = try XCTUnwrap(NSImage(data: data))
        let representation = try XCTUnwrap(image.representations.first)

        XCTAssertEqual(representation.pixelsWide, 1024)
        XCTAssertEqual(representation.pixelsHigh, 1024)
        XCTAssertGreaterThan(data.count, 10_000)

        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let alphaInfo = cgImage.alphaInfo
        XCTAssertTrue(alphaInfo == .premultipliedLast || alphaInfo == .last)
    }

    func testBundledAppIconMatchesTheApprovedBluetoothColoredPreview() throws {
        let appIconURL = URL(fileURLWithPath: "Support/AppIcon.png")
        let approvedPreviewURL = URL(fileURLWithPath: "screenshots/status-trio-app-icon-preview.png")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: appIconURL.path),
            "Support/AppIcon.png is the approved 1024 px preview used by the READMEs."
        )
        guard FileManager.default.fileExists(atPath: appIconURL.path) else { return }

        XCTAssertEqual(
            try Data(contentsOf: appIconURL),
            try Data(contentsOf: approvedPreviewURL),
            "The approved app icon preview must exactly match the Bluetooth-colored render."
        )
    }

    func testIconComposerArtworkIsAFullBleedSquareForBothAppearances() throws {
        var lightData: Data?
        for entry in Self.artworkStyles {
            let data = try AppIconPreview.artworkPNGData(backgroundStyle: entry.style)
            let image = try XCTUnwrap(NSImage(data: data))
            let representation = try XCTUnwrap(image.representations.first)
            let bitmap = try XCTUnwrap(representation as? NSBitmapImageRep)

            XCTAssertEqual(bitmap.pixelsWide, 1024)
            XCTAssertEqual(bitmap.pixelsHigh, 1024)

            // The corner is opaque because the system clips the square to its
            // own icon shape; a transparent corner would show through there.
            let corner = try XCTUnwrap(bitmap.colorAt(x: 4, y: 4))
            XCTAssertEqual(corner.alphaComponent, 1, accuracy: 0.01)

            if entry.style == .light {
                lightData = data
            }
        }

        let darkData = try AppIconPreview.artworkPNGData(backgroundStyle: .dark)
        XCTAssertNotEqual(lightData, darkData, "Light and dark artwork must differ.")
    }

    func testCommittedIconComposerArtworkMatchesTheRenderer() throws {
        for entry in Self.artworkStyles {
            let url = URL(fileURLWithPath: "Support/AppIcon.icon/Assets/\(entry.fileName)")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "The bundle icon is built from \(url.path)."
            )
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            XCTAssertEqual(
                try Data(contentsOf: url),
                try AppIconPreview.artworkPNGData(backgroundStyle: entry.style),
                "\(entry.fileName) must match the renderer's \(entry.style.rawValue) artwork."
            )
        }
    }

    func testWritesRequestedArtworkWhenEnvironmentIsSet() throws {
        guard let directory = ProcessInfo.processInfo.environment["STATUS_TRIO_APP_ICON_ARTWORK_DIR"] else {
            throw XCTSkip("Set STATUS_TRIO_APP_ICON_ARTWORK_DIR to write the Icon Composer artwork.")
        }

        let directoryURL = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        for entry in Self.artworkStyles {
            let data = try AppIconPreview.artworkPNGData(backgroundStyle: entry.style)
            XCTAssertGreaterThan(data.count, 10_000)
            try data.write(to: directoryURL.appendingPathComponent(entry.fileName))
            print("Wrote \(data.count) bytes to \(entry.fileName)")
        }
    }

    func testWritesRequestedOutputWhenEnvironmentIsSet() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["STATUS_TRIO_APP_ICON_PREVIEW"] else {
            throw XCTSkip("Set STATUS_TRIO_APP_ICON_PREVIEW to write the App Icon preview.")
        }

        let data = try AppIconPreview.pngData()
        try data.write(to: URL(fileURLWithPath: outputPath))
        XCTAssertGreaterThan(data.count, 10_000)
        print("Wrote \(data.count) bytes to \(outputPath)")
    }
}
