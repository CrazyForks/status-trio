import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class PrivilegedHelperManagerTests: XCTestCase {
    func testRefreshDoesNotUnregisterApprovalThatArrivedBeforeThePoll() {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service)
        service.status = .enabled
        service.registerError = TestFailure.registration

        manager.refresh()

        XCTAssertEqual(manager.status, .enabled)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertFalse(manager.didFailLastOperation)
    }

    func testDisablingReadsRegistrationThatArrivedBeforeThePoll() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        let manager = PrivilegedHelperManager(service: service)
        service.registerError = TestFailure.registration
        manager.setEnabled(true)
        service.status = .enabled

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertFalse(manager.isEnabled)
    }

    func testFailedUnregisterSettlesWithoutForegroundRefresh() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        service.unregisterError = TestFailure.unregistration
        manager.setEnabled(false)
        XCTAssertTrue(manager.didFailLastOperation)
        service.status = .notRegistered

        let deadline = Date().addingTimeInterval(1)
        while manager.didFailLastOperation, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertEqual(service.unregisterCallCount, 1)
    }

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
        // The switch follows what the user asked for; the banner and the note
        // underneath explain why the helper is not working yet.
        XCTAssertTrue(manager.isEnabled)
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

    func testRefreshObservesPendingApprovalWithoutRewritingRegistration() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)

        service.status = .requiresApproval
        manager.refresh()
        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)

        service.status = .enabled
        manager.refresh()
        XCTAssertTrue(manager.isApproved)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertNil(manager.lastErrorMessage)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
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

    func testPendingRegistrationIsPickedUpWhenTheSystemApprovesIt() async {
        // macOS posts nothing when the user enables the app under System
        // Settings › Login Items, so the registration that is waiting has to be
        // watched — and watched without touching it, because unregistering and
        // re-registering in a loop leaves the item flapping.
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        XCTAssertTrue(manager.isEnabled)

        service.status = .enabled

        let deadline = Date().addingTimeInterval(5)
        while manager.status != .enabled, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(manager.status, .enabled)
        XCTAssertTrue(manager.isApproved)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testPendingRegistrationIsNotRewrittenByThePoll() async {
        // The flapping regression: a poll that unregisters and re-registers the
        // pending item made the status alternate between `requiresApproval` and
        // `notRegistered` every couple of seconds.
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testTurningTheHelperOffStopsWatchingTheSystem() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))

        manager.setEnabled(false)
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertFalse(manager.isEnabled)

        service.status = .enabled
        try? await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(manager.status, .notRegistered)
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
