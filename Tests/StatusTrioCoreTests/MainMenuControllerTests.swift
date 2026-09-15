import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class MainMenuControllerTests: XCTestCase {
    func testInstallsLocalizedMenuAndRebuildsAfterLanguageChange() async throws {
        let environment = try makeEnvironment()
        defer { environment.cleanUp() }

        let controller = MainMenuController(localization: environment.localization) {}
        controller.start()
        defer { controller.stop() }

        XCTAssertEqual(
            try appMenuTitles(),
            [
                "About \(AppMetadata.name)",
                "Settings…",
                "Hide \(AppMetadata.name)",
                "Hide Others",
                "Show All",
                "Quit Status Trio"
            ]
        )

        environment.localization.setPreference(.language(.simplifiedChinese))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(
            try appMenuTitles(),
            [
                "关于 \(AppMetadata.name)",
                "设置…",
                "隐藏 \(AppMetadata.name)",
                "隐藏其他",
                "显示全部",
                "退出 Status Trio"
            ]
        )
    }

    func testSettingsMenuItemInvokesTheHandler() throws {
        let environment = try makeEnvironment()
        defer { environment.cleanUp() }

        var openCount = 0
        let controller = MainMenuController(localization: environment.localization) {
            openCount += 1
        }
        controller.start()
        defer { controller.stop() }

        let appMenu = try XCTUnwrap(NSApplication.shared.mainMenu?.items.first?.submenu)
        let settingsItem = try XCTUnwrap(appMenu.items.first { $0.keyEquivalent == "," })
        appMenu.performActionForItem(at: appMenu.index(of: settingsItem))

        XCTAssertEqual(openCount, 1)
    }

    func testStopRemovesTheMenu() throws {
        let environment = try makeEnvironment()
        defer { environment.cleanUp() }

        let controller = MainMenuController(localization: environment.localization) {}
        controller.start()
        XCTAssertNotNil(NSApplication.shared.mainMenu)

        controller.stop()

        XCTAssertNil(NSApplication.shared.mainMenu)
    }

    private func appMenuTitles() throws -> [String] {
        let appMenu = try XCTUnwrap(NSApplication.shared.mainMenu?.items.first?.submenu)
        return appMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
    }

    private func makeEnvironment() throws -> (localization: Localization, cleanUp: () -> Void) {
        let name = "StatusTrioCoreTests.MainMenu.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        return (localization, { defaults.removePersistentDomain(forName: name) })
    }
}
