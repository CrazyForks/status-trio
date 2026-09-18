import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsDisclosureRowTests: XCTestCase {
    func testTrianglePointsDownWhileCollapsedAndUpWhileExpanded() {
        XCTAssertEqual(SettingsDisclosurePresentation.rotationDegrees(isExpanded: false), 0)
        XCTAssertEqual(SettingsDisclosurePresentation.rotationDegrees(isExpanded: true), 180)
    }

    func testAccessibilityValueReportsTheCurrentState() {
        XCTAssertEqual(
            SettingsDisclosurePresentation.accessibilityValueKey(isExpanded: false),
            .commonCollapsed
        )
        XCTAssertEqual(
            SettingsDisclosurePresentation.accessibilityValueKey(isExpanded: true),
            .commonExpanded
        )
    }

    func testAccessibilityHintOffersTheActionTheRowDoesNext() {
        XCTAssertEqual(
            SettingsDisclosurePresentation.accessibilityHintKey(isExpanded: false),
            .commonExpand
        )
        XCTAssertEqual(
            SettingsDisclosurePresentation.accessibilityHintKey(isExpanded: true),
            .commonCollapse
        )
    }

    func testAccessibilityLabelLeadsWithTheTitleAndSkipsAMissingSubtitle() {
        XCTAssertEqual(
            SettingsDisclosurePresentation.accessibilityLabel(
                title: "Connection Icon Style",
                subtitle: "Uses the standard Wi-Fi signal icon."
            ),
            "Connection Icon Style, Uses the standard Wi-Fi signal icon."
        )
        XCTAssertEqual(
            SettingsDisclosurePresentation.accessibilityLabel(title: "Connection Icon Style", subtitle: nil),
            "Connection Icon Style"
        )
        XCTAssertEqual(
            SettingsDisclosurePresentation.accessibilityLabel(title: "Connection Icon Style", subtitle: ""),
            "Connection Icon Style"
        )
    }

    func testExpandAndCollapseWordingIsLocalizedAndDistinctInEveryLanguage() throws {
        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(
                Localization.resourceBundle(for: language),
                "\(language.rawValue) has no resource bundle"
            )

            let values = [
                LocalizationKey.commonExpand,
                .commonCollapse,
                .commonExpanded,
                .commonCollapsed
            ].map { bundle.localizedString(forKey: $0.rawValue, value: nil, table: nil) }

            for (key, value) in zip(
                [LocalizationKey.commonExpand, .commonCollapse, .commonExpanded, .commonCollapsed],
                values
            ) {
                XCTAssertFalse(value.isEmpty, "\(language.rawValue) is missing \(key.rawValue)")
                XCTAssertNotEqual(
                    value,
                    key.rawValue,
                    "\(language.rawValue) does not translate \(key.rawValue)"
                )
            }

            XCTAssertNotEqual(
                values[0],
                values[1],
                "\(language.rawValue) reads the same expanded and collapsed"
            )
            XCTAssertNotEqual(
                values[2],
                values[3],
                "\(language.rawValue) reads the same expanded and collapsed state"
            )
        }
    }
}
