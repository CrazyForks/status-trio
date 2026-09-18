import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class AppMainMenuTests: XCTestCase {
    func testBuildsAppAndWindowMenus() throws {
        let localization = makeLocalization(language: "zh-Hans")
        let menu = AppMainMenu.make(
            localization: localization,
            target: nil,
            openSettingsAction: #selector(NSApplication.terminate(_:))
        )

        XCTAssertEqual(menu.items.count, 2)

        let appMenu = try XCTUnwrap(menu.items.first?.submenu)
        XCTAssertEqual(appMenu.title, AppMetadata.name)
        XCTAssertEqual(
            appMenu.items.filter { !$0.isSeparatorItem }.map(\.title),
            [
                "关于 \(AppMetadata.name)",
                "设置…",
                "隐藏 \(AppMetadata.name)",
                "隐藏其他",
                "显示全部",
                "退出 Status Trio"
            ]
        )
        XCTAssertEqual(appMenu.items.filter(\.isSeparatorItem).count, 3)

        let windowMenu = try XCTUnwrap(menu.items.last?.submenu)
        XCTAssertEqual(windowMenu.title, "窗口")
        XCTAssertEqual(
            windowMenu.items.filter { !$0.isSeparatorItem }.map(\.title),
            ["关闭窗口"]
        )
        XCTAssertEqual(NSApplication.shared.windowsMenu, windowMenu)
    }

    func testUsesStandardActionsAndShortcuts() throws {
        let localization = makeLocalization(language: "en")
        let openSettings = #selector(NSApplication.terminate(_:))
        let menu = AppMainMenu.make(
            localization: localization,
            target: nil,
            openSettingsAction: openSettings
        )

        let appMenu = try XCTUnwrap(menu.items.first?.submenu)
        let items = appMenu.items.filter { !$0.isSeparatorItem }
        let byTitle = Dictionary(uniqueKeysWithValues: items.map { ($0.title, $0) })

        XCTAssertEqual(
            byTitle["About \(AppMetadata.name)"]?.action,
            #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        )
        XCTAssertEqual(byTitle["Settings…"]?.action, openSettings)
        XCTAssertEqual(byTitle["Hide \(AppMetadata.name)"]?.action, #selector(NSApplication.hide(_:)))
        XCTAssertEqual(byTitle["Hide Others"]?.action, #selector(NSApplication.hideOtherApplications(_:)))
        XCTAssertEqual(byTitle["Show All"]?.action, #selector(NSApplication.unhideAllApplications(_:)))
        XCTAssertEqual(byTitle["Quit Status Trio"]?.action, #selector(NSApplication.terminate(_:)))

        XCTAssertEqual(byTitle["Settings…"]?.keyEquivalent, ",")
        XCTAssertEqual(byTitle["Settings…"]?.keyEquivalentModifierMask, .command)
        XCTAssertEqual(byTitle["Hide \(AppMetadata.name)"]?.keyEquivalent, "h")
        XCTAssertEqual(byTitle["Hide Others"]?.keyEquivalent, "h")
        XCTAssertEqual(byTitle["Hide Others"]?.keyEquivalentModifierMask, [.command, .option])
        XCTAssertEqual(byTitle["Quit Status Trio"]?.keyEquivalent, "q")

        let windowMenu = try XCTUnwrap(menu.items.last?.submenu)
        let closeItem = try XCTUnwrap(windowMenu.items.first { !$0.isSeparatorItem })
        XCTAssertEqual(closeItem.action, #selector(NSWindow.performClose(_:)))
        XCTAssertEqual(closeItem.keyEquivalent, "w")
        XCTAssertEqual(closeItem.keyEquivalentModifierMask, .command)
    }

    func testHasNoEditMenu() {
        let localization = makeLocalization(language: "en")
        let menu = AppMainMenu.make(
            localization: localization,
            target: nil,
            openSettingsAction: #selector(NSApplication.terminate(_:))
        )

        XCTAssertFalse(menu.items.contains { $0.submenu?.title == "Edit" })
    }

    private func makeLocalization(language: String) -> Localization {
        let name = "StatusTrioCoreTests.AppMainMenu.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removeTestSuite(named: name)
        addTeardownBlock { TestUserDefaults.removeSuite(named: name) }
        return Localization(defaults: defaults, preferredLanguages: [language])
    }
}
