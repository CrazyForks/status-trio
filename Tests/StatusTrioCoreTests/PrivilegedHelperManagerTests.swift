import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class PrivilegedHelperManagerTests: XCTestCase {
    func testStatusAndAvailabilityReflectTheService() {
        let enabled = PrivilegedHelperManager(service: FakePrivilegedHelperService(status: .enabled))
        XCTAssertEqual(enabled.status, .enabled)
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertTrue(enabled.isAvailable)
        XCTAssertFalse(enabled.requiresApproval)

        let notRegistered = PrivilegedHelperManager(
            service: FakePrivilegedHelperService(status: .notRegistered)
        )
        XCTAssertFalse(notRegistered.isEnabled)
        XCTAssertTrue(notRegistered.isAvailable)
    }

    func testUnsupportedBuildDisablesTheToggle() {
        let service = FakePrivilegedHelperService(status: .notRegistered, isSupported: false)
        let manager = PrivilegedHelperManager(service: service)

        XCTAssertFalse(manager.isAvailable)

        manager.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 0)
    }

    func testSystemNotFoundIsTreatedAsNotRegistered() {
        // macOS answers `notFound` for a daemon that has never registered.
        XCTAssertEqual(SystemPrivilegedHelperService.status(for: .notFound), .notRegistered)
        XCTAssertEqual(SystemPrivilegedHelperService.status(for: .notRegistered), .notRegistered)
        XCTAssertEqual(SystemPrivilegedHelperService.status(for: .enabled), .enabled)
        XCTAssertEqual(
            SystemPrivilegedHelperService.status(for: .requiresApproval),
            .requiresApproval
        )
    }

    func testEnablingRegistersAndPublishesEnabled() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        let manager = PrivilegedHelperManager(service: service)

        manager.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(manager.status, .enabled)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertFalse(manager.didFailLastOperation)
    }

    func testDisablingUnregistersAndPublishesNotRegistered() {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service)

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertFalse(manager.isEnabled)
    }

    func testReenablingWhileWaitingRetriesRegistration() {
        // A LaunchDaemon needs an administrator to approve it before launchd
        // starts it, so `requiresApproval` is an expected intermediate state.
        // Flicking the switch on again re-asks, because the approval the system
        // is waiting for arrives outside the app.
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let manager = PrivilegedHelperManager(service: service)

        manager.setEnabled(true)

        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertTrue(manager.requiresApproval)
        XCTAssertEqual(service.registerCallCount, 1)

        manager.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 2)
    }

    func testDisablingAPendingRegistrationUnregisters() {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service)
        XCTAssertTrue(manager.isEnabled)

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(manager.status, .notRegistered)
    }

    func testRegistrationFailureIsReportedAndLeavesStatusUnchanged() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)

        manager.setEnabled(true)

        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertFalse(manager.isEnabled)
    }

    func testLaterSuccessfulOperationClearsTheFailureFlag() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)

        service.registerError = nil
        manager.setEnabled(true)

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .enabled)
    }

    func testRefreshRetriesRegistrationUntilTheSystemAcceptsIt() {
        // The reported flow: the app's switch is on while Status Trio is off in
        // System Settings › General › Login Items & Extensions › Allow in the
        // Background. `register()` is refused and macOS answers
        // `requiresApproval`, so the app has to ask again after the user enables
        // it — otherwise the toggle sits on "waiting for approval" and the
        // daemon is never bootstrapped until the user flicks the app's own
        // switch off and on again.
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)

        // macOS reports the refused registration as `requiresApproval`.
        service.status = .requiresApproval
        manager.refresh()

        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertEqual(service.registerCallCount, 2)
        XCTAssertTrue(manager.isEnabled)

        // The user switches Status Trio back on in System Settings; the next
        // refresh re-registers and macOS accepts it.
        service.registerError = nil
        manager.refresh()

        XCTAssertEqual(manager.status, .enabled)
        XCTAssertEqual(service.registerCallCount, 3)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertNil(manager.lastErrorMessage)
        XCTAssertTrue(manager.isApproved)
    }

    func testRefreshClearsAFailureOnceTheDaemonIsApproved() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)

        service.status = .enabled
        manager.refresh()

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertTrue(manager.isApproved)
    }

    func testRefreshKeepsAFailureThatIsStillUnsettled() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)

        manager.refresh()

        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .notRegistered)
    }

    func testFailedUnregistrationIsClearedOnceTheItemIsGone() {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.unregisterError = TestFailure.unregistration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(false)
        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .enabled)

        service.unregisterError = nil
        service.status = .notRegistered
        manager.refresh()

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertFalse(manager.isEnabled)
    }

    func testRefreshWithoutAFailureLeavesTheFlagClear() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        let manager = PrivilegedHelperManager(service: service)

        service.status = .enabled
        manager.refresh()

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .enabled)
    }

    func testPendingRegistrationIsRetriedUntilTheSystemApprovesIt() async {
        // macOS posts nothing when the user enables the app under System
        // Settings › Login Items, so the manager has to keep asking on its own
        // or the toggle stays on "waiting for approval" forever.
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, retryInterval: .milliseconds(20))

        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .notRegistered)

        service.registerError = nil

        let deadline = Date().addingTimeInterval(5)
        while manager.status != .enabled, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(manager.status, .enabled)
        XCTAssertTrue(manager.isApproved)
        XCTAssertFalse(manager.didFailLastOperation)
    }

    func testTurningTheHelperOffStopsTheRetryLoop() async {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, retryInterval: .milliseconds(20))
        manager.setEnabled(true)

        manager.setEnabled(false)
        let callsAfterDisabling = service.registerCallCount
        try? await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(service.registerCallCount, callsAfterDisabling)
        XCTAssertFalse(manager.didFailLastOperation)
    }

    func testOpenLoginItemsSettingsIsForwardedToTheService() {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service)

        manager.openLoginItemsSettings()

        XCTAssertEqual(service.openLoginItemsCallCount, 1)
    }

    func testEnabledBindingReadsAndWritesManagerState() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        let manager = PrivilegedHelperManager(service: service)

        XCTAssertFalse(manager.isEnabledBinding.wrappedValue)

        manager.isEnabledBinding.wrappedValue = true
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertTrue(manager.isEnabledBinding.wrappedValue)
    }

    private enum TestFailure: Error {
        case registration
        case unregistration
    }
}

@MainActor
final class FakePrivilegedHelperService: PrivilegedHelperServicing {
    var status: PrivilegedHelperStatus
    var statusAfterRegister: PrivilegedHelperStatus?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openLoginItemsCallCount = 0
    let isSupported: Bool

    init(status: PrivilegedHelperStatus, isSupported: Bool = true) {
        self.status = status
        self.isSupported = isSupported
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = statusAfterRegister ?? .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }

    func openLoginItemsSettings() {
        openLoginItemsCallCount += 1
    }
}
