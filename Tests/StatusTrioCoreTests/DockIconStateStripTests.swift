import XCTest
@testable import StatusTrioCore

/// Writes the text-free, one-line Dock icon strip used for visual sharing.
///
/// ```bash
/// STATUS_TRIO_DOCK_STATE_STRIP=/tmp/status-trio-dock-state-strip.png \
///   swift test --filter DockIconStateStripTests
/// ```
@MainActor
final class DockIconStateStripTests: XCTestCase {
    func testStripHasEightAlternatingBackgroundStates() {
        let states = DockIconStateStrip.states

        XCTAssertEqual(states.count, 8)
        XCTAssertEqual(
            states.map(\.backgroundStyle),
            [.dark, .light, .dark, .light, .dark, .light, .dark, .light]
        )
        XCTAssertEqual(
            states.map(\.volumeStyle),
            [.dots, .arc, .dots, .dots, .dots, .arc, .dots, .arc]
        )
        XCTAssertEqual(states.filter(\.usesBluetoothAudio).count, 3)
        XCTAssertTrue(states[5].usesBluetoothVolumeColor)
        XCTAssertTrue(states[6].usesBluetoothVolumeColor)
    }

    func testWritesLandscapeStripWithoutText() throws {
        let data = try DockIconStateStrip.pngData(scale: 1)
        XCTAssertGreaterThan(data.count, 10_000)

        let image = try XCTUnwrap(NSImage(data: data))
        XCTAssertGreaterThan(image.size.width, image.size.height * 4)
    }

    func testWritesRequestedOutputWhenEnvironmentIsSet() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["STATUS_TRIO_DOCK_STATE_STRIP"] else {
            throw XCTSkip("Set STATUS_TRIO_DOCK_STATE_STRIP to write the Dock state strip.")
        }

        let data = try DockIconStateStrip.pngData()
        try data.write(to: URL(fileURLWithPath: outputPath))
        XCTAssertGreaterThan(data.count, 10_000)
        print("Wrote \(data.count) bytes to \(outputPath)")
    }
}
