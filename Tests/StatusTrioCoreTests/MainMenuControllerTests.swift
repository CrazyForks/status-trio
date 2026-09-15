import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class MainMenuControllerTests: XCTestCase {
    func testInstallsLocalizedMenuAndRebuildsAfterLanguageChange() async throws {
        let environment = try makeEnvironment()
        defer { environment.cleanUp() }
        let harness = makeStartedController(environment)
        defer { harness.controller.stop() }

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
        let harness = makeStartedController(environment) { openCount += 1 }
        defer { harness.controller.stop() }

        let appMenu = try XCTUnwrap(NSApplication.shared.mainMenu?.items.first?.submenu)
        let settingsItem = try XCTUnwrap(appMenu.items.first { $0.keyEquivalent == "," })
        appMenu.performActionForItem(at: appMenu.index(of: settingsItem))

        XCTAssertEqual(openCount, 1)
    }

    func testStopRemovesTheMenu() throws {
        let environment = try makeEnvironment()
        defer { environment.cleanUp() }
        let harness = makeStartedController(environment)

        XCTAssertNotNil(NSApplication.shared.mainMenu)

        harness.controller.stop()

        XCTAssertNil(NSApplication.shared.mainMenu)
    }

    func testInstallsTheMenuOnlyWhileTheAppIsRegularAndActive() throws {
        let environment = try makeEnvironment()
        defer { environment.cleanUp() }

        let notificationCenter = NotificationCenter()
        let policy = AppActivationPolicy(application: MainMenuActivationSpy())
        let controller = MainMenuController(
            activationPolicy: policy,
            localization: environment.localization,
            notificationCenter: notificationCenter
        ) {}
        controller.start()
        defer { controller.stop() }

        XCTAssertNil(NSApplication.shared.mainMenu, "inactive accessory app")

        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertNil(NSApplication.shared.mainMenu, "active accessory app")

        policy.enterTemporaryRegularMode()
        XCTAssertNotNil(NSApplication.shared.mainMenu, "active regular app")

        notificationCenter.post(name: NSApplication.didResignActiveNotification, object: nil)
        XCTAssertNil(NSApplication.shared.mainMenu, "inactive regular app")
    }

    private func makeStartedController(
        _ environment: (localization: Localization, cleanUp: () -> Void),
        openSettings: @escaping () -> Void = {}
    ) -> (controller: MainMenuController, policy: AppActivationPolicy) {
        let notificationCenter = NotificationCenter()
        let policy = AppActivationPolicy(application: MainMenuActivationSpy())
        policy.enterTemporaryRegularMode()
        let controller = MainMenuController(
            activationPolicy: policy,
            localization: environment.localization,
            notificationCenter: notificationCenter,
            openSettings: openSettings
        )
        controller.start()
        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        return (controller, policy)
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

@MainActor
private final class MainMenuActivationSpy: ApplicationActivationPolicyApplying {
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        currentActivationPolicy = activationPolicy
        return true
    }
}
