import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class PrivilegedHelperManagerTests: XCTestCase {
    func testOptOutPreservesApprovalAndStopsHelperReads() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        await waitUntil { manager.isApproved }
        let reads = service.verificationCallCount

        manager.setEnabled(false)
        manager.refreshAfterActivation()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.isApproved)
        XCTAssertFalse(manager.isHelperResponsive)
        XCTAssertEqual(service.status, .enabled)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.verificationCallCount, reads)
    }

    func testRepeatedOptInChangesDoNotRewriteApprovedRegistration() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        await waitUntil { manager.isApproved }
        for _ in 0..<5 {
            manager.setEnabled(false)
            XCTAssertFalse(manager.isApproved)
            manager.setEnabled(true)
            await waitUntil { manager.isApproved }
            XCTAssertTrue(manager.isApproved)
        }
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 0)
    }

    func testPermissionDenialBeforeApprovalStatusSettlesShowsOnlyWaiting() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = NSError(domain: "SMAppServiceErrorDomain", code: 1)
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.requiresApproval)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertNil(manager.lastErrorMessage)
        XCTAssertEqual(manager.status, .notRegistered)
    }

    func testPersistentPermissionErrorWithoutPendingRegistrationIsExposedAfterRetries() async {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = NSError(domain: "SMAppServiceErrorDomain", code: 1)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(5))
        manager.setEnabled(true)
        XCTAssertTrue(manager.requiresApproval)
        await waitUntil { service.registerCallCount == 6 }
        await waitUntil { manager.didFailLastOperation }
        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertFalse(manager.requiresApproval)
        XCTAssertNotNil(manager.lastErrorMessage)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(service.registerCallCount, 6)
    }

    func testPendingRegistrationRetriesAfterPermissionArrivesWithoutAnotherToggle() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        manager.setEnabled(true)
        service.registerError = nil
        await waitUntil { manager.isApproved }
        XCTAssertTrue(manager.isApproved)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testRegistrationRetryAlsoRecoversAnUnregisteredTransientFailure() async {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)
        service.registerError = nil
        await waitUntil { manager.isApproved }
        XCTAssertTrue(manager.isApproved)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testOpeningApprovalSettingsStartsANewBoundedRetryWindow() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(5))
        manager.setEnabled(true)
        await waitUntil { service.registerCallCount == 6 }
        let attempts = service.registerCallCount
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(service.registerCallCount, attempts)
        service.registerError = nil
        manager.openLoginItemsSettings()
        await waitUntil { manager.isApproved }
        XCTAssertTrue(manager.isApproved)
        XCTAssertGreaterThan(service.registerCallCount, attempts)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testOptOutCancelsPendingRegistrationRetries() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        manager.setEnabled(true)
        manager.setEnabled(false)
        let attempts = service.registerCallCount
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(service.registerCallCount, attempts)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.requiresApproval)
    }

    func testRegistrationRetryDoesNotHideUnrelatedPermissionErrors() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = NSError(domain: "OtherRegistrationFailure", code: 1)
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertFalse(manager.requiresApproval)
        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertNotNil(manager.lastErrorMessage)
    }

    func testFailedRecoveryRegistrationGetsADelayedRegisterOnlyRetry() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.verificationFailuresRemaining = 1
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        await waitUntil { manager.didFailLastOperation }
        service.registerError = nil
        await waitUntil { manager.isApproved }
        XCTAssertTrue(manager.isApproved)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 1)
    }

    func testRecoveryThatRegistersIntoPendingApprovalGetsDelayedRetries() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.verificationFailuresRemaining = 1
        service.statusAfterRegister = .requiresApproval
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(10))
        await waitUntil { manager.status == .requiresApproval }
        service.statusAfterRegister = .enabled
        await waitUntil { manager.isApproved }
        XCTAssertTrue(manager.isApproved)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 1)
    }

    func testEnabledServiceMustAnswerAReadBeforeItIsApproved() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        XCTAssertFalse(manager.isApproved)
        await waitUntil { service.verificationCallCount > 0 && manager.isApproved }
        XCTAssertTrue(manager.isApproved)
        XCTAssertEqual(service.registerCallCount, 0)
    }

    func testEnabledButUnreachableHelperIsRecovered() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.verificationFailuresRemaining = 1
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        await waitUntil { service.recoveryUnregisterCallCount > 0 && manager.isApproved }
        XCTAssertTrue(manager.isApproved)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 1)
    }

    func testDeniedRegistrationAwaitingApprovalIsNotAnOperationFailure() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        service.statusOnRegistrationFailure = .requiresApproval
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.requiresApproval)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertNil(manager.lastErrorMessage)
    }

    func testFailedHealthRecoveryHasATwoAttemptLimit() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.verificationFailuresRemaining = 100
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        await waitUntil { service.verificationCallCount >= 4 }
        let readsAfterExhaustion = service.verificationCallCount
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(service.recoveryUnregisterCallCount, 2)
        XCTAssertEqual(service.verificationCallCount, readsAfterExhaustion)
        XCTAssertFalse(manager.isApproved)
        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertTrue(manager.isEnabled)
        service.status = .requiresApproval
        manager.refresh()
        service.status = .enabled
        manager.refresh()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(service.recoveryUnregisterCallCount, 2)
    }

    func testOptOutDuringRecoveryPreventsReregistration() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.verificationFailuresRemaining = 1
        service.holdRecoveryUnregister = true
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        await waitUntil { service.recoveryContinuation != nil }
        XCTAssertNotNil(service.recoveryContinuation)
        manager.setEnabled(false)
        service.recoveryContinuation?.resume()
        await waitUntil { service.recoveryContinuation == nil }
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertFalse(manager.isEnabled)
    }

    func testPollDoesNotCancelAnUnregisterThatIsStillCompleting() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        service.verificationFailuresRemaining = 1
        service.holdRecoveryUnregister = true
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        await waitUntil { service.recoveryContinuation != nil }
        service.status = .notRegistered
        try? await Task.sleep(for: .milliseconds(80))
        service.recoveryContinuation?.resume()
        await waitUntil { manager.isApproved }
        XCTAssertTrue(manager.isApproved)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 1)
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(1)
        while !predicate(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testVerifiedHelperIsNotKeptAliveByStatusPolling() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        await waitUntil { manager.isApproved }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(service.verificationCallCount, 1)
        XCTAssertEqual(service.recoveryUnregisterCallCount, 0)
    }

    func testActivationRetryWhileWaitingIsBoundedAndDoesNotUnregister() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(5))
        for _ in 0..<10 { manager.refreshAfterActivation() }
        await waitUntil { service.registerCallCount == 5 }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(service.registerCallCount, 5)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.verificationCallCount, 0)
        XCTAssertTrue(manager.requiresApproval)
        XCTAssertFalse(manager.didFailLastOperation)
    }

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

    func testOptOutReadsButPreservesRegistrationThatArrivedBeforeThePoll() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        let manager = PrivilegedHelperManager(service: service)
        service.registerError = TestFailure.registration
        manager.setEnabled(true)
        service.status = .enabled

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.status, .enabled)
        XCTAssertEqual(manager.status, .enabled)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.isApproved)
    }

    func testOptOutBeforeVerificationStopsHelperContact() async {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))
        manager.setEnabled(false)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .enabled)
        XCTAssertEqual(service.verificationCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
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

    func testOptOutKeepsRegistrationButMakesTheFeatureUnavailable() {
        let service = FakePrivilegedHelperService(status: .enabled)
        let manager = PrivilegedHelperManager(service: service)

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(manager.status, .enabled)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.isApproved)
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

    func testOptOutPreservesAPendingRegistrationWithoutShowingApprovalWarning() {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service)
        XCTAssertTrue(manager.isEnabled)

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertFalse(manager.requiresApproval)
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

    func testRefreshObservesPendingApprovalWithoutRewritingRegistration() async {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)

        service.status = .requiresApproval
        manager.refresh()
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)

        service.status = .enabled
        manager.refresh()
        await waitUntil { manager.isApproved }
        XCTAssertTrue(manager.isApproved)
        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertNil(manager.lastErrorMessage)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testRefreshClearsAFailureOnceTheDaemonIsApproved() async {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)

        service.status = .enabled
        manager.refresh()
        await waitUntil { manager.isApproved }

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

    func testOptOutClearsAnUnsettledRegistrationFailure() {
        let service = FakePrivilegedHelperService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = PrivilegedHelperManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)
        manager.setEnabled(false)

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertNil(manager.lastErrorMessage)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(service.unregisterCallCount, 0)
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
        while !manager.isApproved, Date() < deadline {
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

    func testFeatureOptOutStopsWatchingTheSystem() async {
        let service = FakePrivilegedHelperService(status: .requiresApproval)
        let manager = PrivilegedHelperManager(service: service, pollInterval: .milliseconds(20))

        manager.setEnabled(false)
        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertFalse(manager.isEnabled)

        service.status = .enabled
        try? await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(manager.status, .requiresApproval)
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
    var statusOnRegistrationFailure: PrivilegedHelperStatus?
    var verificationFailuresRemaining = 0
    var holdRecoveryUnregister = false
    var recoveryContinuation: CheckedContinuation<Void, any Error>?
    private(set) var verificationCallCount = 0
    private(set) var recoveryUnregisterCallCount = 0
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
            if let statusOnRegistrationFailure { status = statusOnRegistrationFailure }
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

    func verifyConnection() async throws {
        verificationCallCount += 1
        if verificationFailuresRemaining > 0 {
            verificationFailuresRemaining -= 1
            throw NSError(domain: "XPCProbe", code: 4099)
        }
    }

    func unregisterForRecovery() async throws {
        recoveryUnregisterCallCount += 1
        if holdRecoveryUnregister {
            try await withCheckedThrowingContinuation { recoveryContinuation = $0 }
            recoveryContinuation = nil
        }
        try unregister()
    }
}
