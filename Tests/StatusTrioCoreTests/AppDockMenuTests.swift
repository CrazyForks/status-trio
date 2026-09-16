import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class AppDockMenuTests: XCTestCase {
    func testOffersSettingsOnlyAndLetsTheSystemProvideQuit() throws {
        let menu = AppDockMenu.make(localization: makeLocalization(), target: nil, action: nil)

        XCTAssertEqual(menu.items.count, 1)
        XCTAssertEqual(menu.items.first?.title, "设置…")
    }

    func testLocalizesTheSettingsItem() throws {
        let menu = AppDockMenu.make(
            localization: makeLocalization(language: "en"),
            target: nil,
            action: nil
        )

        XCTAssertEqual(menu.items.first?.title, "Settings…")
    }

    private func makeLocalization(language: String = "zh-Hans") -> Localization {
        let name = "StatusTrioCoreTests.AppDockMenu.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return Localization(defaults: defaults, preferredLanguages: [language])
    }
}
