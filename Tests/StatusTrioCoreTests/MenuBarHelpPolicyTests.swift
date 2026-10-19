import XCTest
@testable import StatusTrioCore

final class MenuBarHelpPolicyTests: XCTestCase {
    func testMenuBarSettingsUseTheMenuBarPaneOnMacOS26() {
        let policy = MenuBarHelpPolicy(majorVersion: 26)

        XCTAssertEqual(policy.tier, .menuBarSettings)
        XCTAssertEqual(
            policy.stepKeys,
            [
                .guideMenuBarHelpMenuBarSettingsStep,
                .guideMenuBarHelpFindStatusTrioStep,
                .guideMenuBarHelpMoveStep
            ]
        )
        XCTAssertEqual(
            policy.systemSettingsURLs,
            [MenuBarHelpPolicy.systemSettingsAppURL]
        )
        XCTAssertEqual(
            policy.systemSettingsButtonKey,
            .guideMenuBarHelpOpenSystemSettings
        )
    }

    func testNativeOverflowEntryAppearsStartingWithMacOS27() {
        for version in [27, 28, 31] {
            let policy = MenuBarHelpPolicy(majorVersion: version)
            XCTAssertEqual(policy.tier, .menuBarSettings)
            XCTAssertTrue(policy.showsNativeOverflowEntry)
            XCTAssertEqual(policy.stepKeys.count, 3)
            XCTAssertEqual(policy.stepKeys.first, .guideMenuBarHelpOverflowStep)
        }
    }

    func testMacOS13Through25UseControlCenterSettings() {
        for version in [13, 15, 25] {
            let policy = MenuBarHelpPolicy(majorVersion: version)
            XCTAssertEqual(policy.tier, .controlCenterSettings)
            XCTAssertFalse(policy.showsNativeOverflowEntry)
            XCTAssertEqual(
                policy.systemSettingsURLs.first?.absoluteString,
                "x-apple.systempreferences:"
            )
            XCTAssertEqual(
                policy.systemSettingsButtonKey,
                .guideMenuBarHelpOpenSystemSettings
            )
            XCTAssertEqual(
                policy.stepKeys,
                [
                    .guideMenuBarHelpControlCenterStep,
                    .guideMenuBarHelpMoveStep
                ]
            )
        }
    }

    func testUnsupportedOlderSystemsStillGetReadableSteps() {
        let policy = MenuBarHelpPolicy(majorVersion: 12)

        XCTAssertEqual(policy.tier, .controlCenterSettings)
        XCTAssertFalse(policy.stepKeys.isEmpty)
        XCTAssertFalse(policy.systemSettingsURLs.isEmpty)
    }

    func testSystemSettingsFallbackOpensTheMainApp() throws {
        XCTAssertEqual(
            MenuBarHelpPolicy.systemSettingsAppURL.absoluteString,
            "x-apple.systempreferences:"
        )

        for version in [13, 26, 27, 28] {
            let policy = MenuBarHelpPolicy(majorVersion: version)
            XCTAssertEqual(
                policy.systemSettingsURLs.last,
                MenuBarHelpPolicy.systemSettingsAppURL
            )
        }
    }

    func testMacOS26UsesMenuBarPaneButDoesNotShowTheNativeOverflowStep() {
        let policy = MenuBarHelpPolicy(majorVersion: 26)

        XCTAssertFalse(policy.showsNativeOverflowEntry)
        XCTAssertEqual(
            policy.systemSettingsURLs,
            [MenuBarHelpPolicy.systemSettingsAppURL]
        )
    }

    func testMacOS27UsesTheVerifiedMenuBarPaneRouteFirst() {
        let policy = MenuBarHelpPolicy(majorVersion: 27)

        XCTAssertEqual(
            policy.systemSettingsURLs.first?.absoluteString,
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
        )
        XCTAssertEqual(
            policy.systemSettingsButtonKey,
            .guideMenuBarHelpOpenMenuBarSettings
        )
    }

    func testHelpPresentationStartsClosedAndClosesOnNavigation() {
        var presentation = MenuBarHelpPresentation()
        XCTAssertFalse(presentation.isPresented)

        presentation.toggle()
        XCTAssertTrue(presentation.isPresented)

        presentation.prepareForPageChange()
        XCTAssertFalse(presentation.isPresented)

        presentation.toggle()
        presentation.close()
        XCTAssertFalse(presentation.isPresented)
    }
}
