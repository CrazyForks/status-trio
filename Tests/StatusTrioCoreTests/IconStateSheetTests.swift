import XCTest
@testable import StatusTrioCore

/// Writes the icon state sheet used by the READMEs.
///
/// The test is skipped unless an output path is provided, so CI never writes
/// files:
///
/// ```bash
/// STATUS_TRIO_ICON_SHEET=/tmp/status-trio-icon-states.png \
/// STATUS_TRIO_ICON_SHEET_DARK=/tmp/status-trio-icon-states-dark.png \
///   swift test --filter IconStateSheetTests
/// ```
final class IconStateSheetTests: XCTestCase {
    func testWritesIconStateSheet() throws {
        let environment = ProcessInfo.processInfo.environment
        let targets = [
            (environment["STATUS_TRIO_ICON_SHEET"], IconStateSheet.Appearance.light),
            (environment["STATUS_TRIO_ICON_SHEET_DARK"], IconStateSheet.Appearance.dark)
        ]

        let requested = targets.compactMap { path, appearance in
            path.map { ($0, appearance) }
        }

        guard !requested.isEmpty else {
            throw XCTSkip("Set STATUS_TRIO_ICON_SHEET or STATUS_TRIO_ICON_SHEET_DARK.")
        }

        for (outputPath, appearance) in requested {
            let data = try IconStateSheet.pngData(appearance: appearance)
            XCTAssertGreaterThan(data.count, 10_000)
            try data.write(to: URL(fileURLWithPath: outputPath))
            print("Wrote \(data.count) bytes to \(outputPath)")
        }
    }

    func testSheetCoversEachZone() {
        let sections = IconStateSheet.sections
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections.map(\.zh), ["电池（顶部）", "Wi-Fi（中部）", "音量（底部）"])
        XCTAssertEqual(sections.map(\.zone).count, 3)
        for section in sections {
            XCTAssertGreaterThanOrEqual(section.entries.count, 6, section.zh)
            for entry in section.entries {
                XCTAssertFalse(entry.zh.isEmpty)
                XCTAssertFalse(entry.en.isEmpty)
            }
        }
    }
}
