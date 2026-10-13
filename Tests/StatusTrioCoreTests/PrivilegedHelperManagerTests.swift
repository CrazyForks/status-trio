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

    func testRegistrationAwaitingApprovalKeepsToggleOn() {
        // A LaunchDaemon needs an administrator to approve it before launchd
        // starts it, so `requiresApproval` is the expected state after register.
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let manager = PrivilegedHelperManager(service: service)

        manager.setEnabled(true)

        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertTrue(manager.requiresApproval)

        manager.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 1)
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

    func testRefreshClearsAFailureOnceTheSystemCatchesUp() {
        // The reported bug: registration fails while the item is still
        // disallowed, the user approves it in Login Items, and the banner stayed
        // on screen because only `setEnabled` ever cleared it.
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)

        service.registerError = nil
        service.status = .requiresApproval
        manager.refresh()

        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertTrue(manager.isEnabled)
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
