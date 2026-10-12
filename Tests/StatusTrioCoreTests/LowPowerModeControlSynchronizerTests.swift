import XCTest
@testable import StatusTrioCore

@MainActor
final class LowPowerModeControlSynchronizerTests: XCTestCase {
    func testRegistrationMirrorsIntoThePersistedFlag() {
        let suite = makeSuite()
        defer { clear(suite) }
        let settings = SettingsStore(defaults: suite.defaults)
        let helper = PrivilegedHelperManager(service: FakePrivilegedHelperService(status: .notRegistered))
        let synchronizer = LowPowerModeControlSynchronizer()

        synchronizer.start(settings: settings, helper: helper)
        XCTAssertFalse(settings.controlsLowPowerMode)

        helper.setEnabled(true)

        XCTAssertTrue(settings.controlsLowPowerMode)
    }

    func testUnregisteringClearsThePersistedFlag() {
        let suite = makeSuite()
        defer { clear(suite) }
        let settings = SettingsStore(defaults: suite.defaults)
        let service = FakePrivilegedHelperService(status: .enabled)
        let helper = PrivilegedHelperManager(service: service)
        let synchronizer = LowPowerModeControlSynchronizer()
        synchronizer.start(settings: settings, helper: helper)
        XCTAssertTrue(settings.controlsLowPowerMode)

        helper.setEnabled(false)

        XCTAssertFalse(settings.controlsLowPowerMode)
    }

    func testPendingApprovalStillCountsAsOn() {
        // The user asked for the feature; a registration awaiting approval must
        // not flip the persisted flag back off while they go approve it.
        let suite = makeSuite()
        defer { clear(suite) }
        let settings = SettingsStore(defaults: suite.defaults)
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let helper = PrivilegedHelperManager(service: service)
        let synchronizer = LowPowerModeControlSynchronizer()
        synchronizer.start(settings: settings, helper: helper)

        helper.setEnabled(true)

        XCTAssertTrue(settings.controlsLowPowerMode)
    }

    func testStaleFlagIsClearedWhenTheHelperIsGone() {
        // A flag left on by a previous install whose daemon is no longer
        // registered must not show a control with nothing behind it.
        let suite = makeSuite()
        defer { clear(suite) }
        let defaults = suite.defaults
        defaults.set(true, forKey: SettingsStore.controlsLowPowerModeDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertTrue(settings.controlsLowPowerMode)
        let helper = PrivilegedHelperManager(service: FakePrivilegedHelperService(status: .notRegistered))

        let synchronizer = LowPowerModeControlSynchronizer()
        synchronizer.start(settings: settings, helper: helper)

        XCTAssertFalse(settings.controlsLowPowerMode)
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.LowPowerModeControlSynchronizer.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removePersistentDomain(forName: suite.name)
    }
}