import XCTest
@testable import StatusTrioCore

/// Writes the 1080×1440 social cover. Skipped unless an output path is given:
///
/// ```bash
/// STATUS_TRIO_SOCIAL_COVER=/tmp/status-trio-xiaohongshu.png \
///   swift test --filter SocialCoverSheetTests
/// ```
@MainActor
final class SocialCoverSheetTests: XCTestCase {
    func testWritesSocialCover() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["STATUS_TRIO_SOCIAL_COVER"] else {
            throw XCTSkip("Set STATUS_TRIO_SOCIAL_COVER to write the cover.")
        }

        let data = try SocialCoverSheet.pngData()
        XCTAssertGreaterThan(data.count, 20_000)
        try data.write(to: URL(fileURLWithPath: outputPath))
        print("Wrote \(data.count) bytes to \(outputPath)")
    }
}
