import XCTest
@testable import StatusTrioCore

final class AppMetadataTests: XCTestCase {
    func testNameUsesDisplayNameFirst() {
        let name = AppMetadata.name(from: [
            "CFBundleDisplayName": "Localized Name",
            "CFBundleName": "Bundle Name"
        ])

        XCTAssertEqual(name, "Localized Name")
    }

    func testNameFallsBackToBundleName() {
        let name = AppMetadata.name(from: [
            "CFBundleName": "Bundle Name"
        ])

        XCTAssertEqual(name, "Bundle Name")
    }

    func testNameFallsBackToDefault() {
        XCTAssertEqual(AppMetadata.name(from: [:]), "Status Trio")
    }

    func testDevelopmentCodenameUsesNonEmptyInfoValue() {
        XCTAssertEqual(
            AppMetadata.developmentCodename(from: ["STDevelopmentCodename": "Fix Issues"]),
            "Fix Issues"
        )
        XCTAssertNil(AppMetadata.developmentCodename(from: ["STDevelopmentCodename": "   "]))
        XCTAssertNil(AppMetadata.developmentCodename(from: [:]))
    }

    func testProjectHomepageURL() {
        XCTAssertEqual(
            AppMetadata.projectHomepageURL.absoluteString,
            "https://statustrio.lingai.net/"
        )
    }

    func testGitHubMarkLoadsFromResourceBundle() {
        XCTAssertNotNil(AboutIcon.githubMark)
    }
}
