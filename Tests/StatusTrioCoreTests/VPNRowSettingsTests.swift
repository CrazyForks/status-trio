import XCTest
@testable import StatusTrioCore

/// The VPN row's settings surface: it is on by default, a list stored before
/// the row existed picks it up exactly once, and switching it off sticks.
@MainActor
final class VPNRowSettingsTests: XCTestCase {
    func testVPNIsInTheDefaultSelection() {
        XCTAssertTrue(SettingsStore.defaultEnabledPopupSections.contains(.vpn))
    }

    func testAFreshInstallShowsTheVPNRow() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)

        XCTAssertTrue(store.enabledPopupSections.contains(.vpn))
        XCTAssertTrue(store.visiblePopupSections.contains(.vpn))
    }

    /// The default set only reaches a user who has never saved a list, so an
    /// upgrade has to add the row by hand — and write the result back. The
    /// second `SettingsStore` is the assertion that matters: `didSet` does not
    /// run for an assignment made inside `init`, so a migration left in memory
    /// only would rebuild the old list on the next launch.
    func testAStoredListFromBeforeTheRowGainsItAndKeepsIt() {
        let suite = makeSuite()
        defer { clear(suite) }

        suite.defaults.set(
            [PopupSection.battery.rawValue, PopupSection.volume.rawValue],
            forKey: SettingsStore.enabledPopupSectionsDefaultsKey
        )

        let upgraded = SettingsStore(defaults: suite.defaults)
        XCTAssertTrue(upgraded.enabledPopupSections.contains(.vpn))

        let reopened = SettingsStore(defaults: suite.defaults)
        XCTAssertTrue(reopened.enabledPopupSections.contains(.vpn))
        XCTAssertTrue(reopened.enabledPopupSections.contains(.battery))
        XCTAssertTrue(reopened.enabledPopupSections.contains(.volume))
        XCTAssertFalse(reopened.enabledPopupSections.contains(.network))
    }

    func testTurningTheRowOffSurvivesARelaunch() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)
        store.setPopupSection(.vpn, enabled: false)
        XCTAssertFalse(store.enabledPopupSections.contains(.vpn))

        let reopened = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(reopened.enabledPopupSections.contains(.vpn))
        XCTAssertFalse(reopened.visiblePopupSections.contains(.vpn))
    }

    func testTheMigrationRunsOnceEvenWithAnEmptyStoredList() {
        let suite = makeSuite()
        defer { clear(suite) }

        // An empty list is a user who switched every row off. The row is offered
        // once, and the second launch has to respect the choice that follows.
        suite.defaults.set([String](), forKey: SettingsStore.enabledPopupSectionsDefaultsKey)

        let upgraded = SettingsStore(defaults: suite.defaults)
        XCTAssertTrue(upgraded.enabledPopupSections.contains(.vpn))

        upgraded.setPopupSection(.vpn, enabled: false)
        let reopened = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(reopened.enabledPopupSections.contains(.vpn))
    }

    func testSanitizerOnlyAddsTheRowBeforeTheMarkerIsSet() {
        let stored = [PopupSection.battery.rawValue, PopupSection.volume.rawValue]

        XCTAssertTrue(
            SettingsStore
                .sanitizedEnabledPopupSections(stored, hasIntroducedVPN: false)
                .contains(.vpn)
        )
        XCTAssertFalse(
            SettingsStore
                .sanitizedEnabledPopupSections(stored, hasIntroducedVPN: true)
                .contains(.vpn)
        )
    }

    func testSanitizerFallsBackToTheDefaultsWithoutAStoredList() {
        XCTAssertEqual(
            SettingsStore.sanitizedEnabledPopupSections(nil, hasIntroducedVPN: true),
            SettingsStore.defaultEnabledPopupSections
        )
    }

    /// The order sanitizer appends a section it has never seen, so the row also
    /// reaches a user whose stored order predates it.
    func testStoredOrderPicksUpTheRow() {
        let order = SettingsStore.sanitizedPopupSectionOrder(
            [PopupSection.volume.rawValue, PopupSection.battery.rawValue]
        )

        XCTAssertEqual(order.first, .volume)
        XCTAssertTrue(order.contains(.vpn))
        XCTAssertEqual(order.count, PopupSection.allCases.count)
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.VPNRowSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        defaults.removeTestSuite(named: name)
        addTeardownBlock { TestUserDefaults.removeSuite(named: name) }
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removeTestSuite(named: suite.name)
    }
}
