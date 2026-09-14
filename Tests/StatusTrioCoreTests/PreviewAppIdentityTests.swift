import Foundation
import XCTest
@testable import StatusTrioCore

final class PreviewAppIdentityTests: XCTestCase {
    func testPopupSettingsTitleUsesPreviewPrefix() {
        XCTAssertEqual(
            PreviewAppIdentity.popupSettingsTitle(localizedTitle: "Settings…"),
            "[preview] Settings…"
        )
    }

    func testPreviewUsesIndependentRuntimeIdentity() {
        XCTAssertEqual(
            PreviewAppIdentity.bundleIdentifier,
            "com.lingsmbp.StatusTrio.preview"
        )
        XCTAssertEqual(
            PreviewAppIdentity.defaultsSuiteName,
            "com.lingsmbp.StatusTrio.preview"
        )
        XCTAssertEqual(
            PreviewAppIdentity.applicationSupportDirectoryName,
            "StatusTrioPreview"
        )
        XCTAssertEqual(
            SingleInstanceGuard.lockFileName(for: nil),
            "com.lingsmbp.StatusTrio.preview.lock"
        )
    }
}
