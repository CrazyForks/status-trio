import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct AppActivationPolicyTests {
    @Test func persistentDockVisibilityKeepsRegularPolicy() {
        let application = ActivationPolicyApplicationSpy()
        let policy = AppActivationPolicy(application: application)

        #expect(policy.setDockIconVisible(true))
        policy.enterTemporaryRegularMode()
        #expect(policy.setDockIconVisible(false))
        policy.leaveTemporaryRegularMode()

        #expect(application.policies == [.regular, .regular, .regular, .accessory])
    }

    @Test func nestedTemporaryRequestsLeaveOnlyAfterFinalOwner() {
        let application = ActivationPolicyApplicationSpy()
        let policy = AppActivationPolicy(application: application)

        policy.enterTemporaryRegularMode()
        policy.enterTemporaryRegularMode()
        policy.leaveTemporaryRegularMode()
        policy.leaveTemporaryRegularMode()
        policy.leaveTemporaryRegularMode()

        #expect(application.policies == [.regular, .regular, .regular, .accessory, .accessory])
    }

    @Test func reportsRejectedPolicyChanges() {
        let application = ActivationPolicyApplicationSpy(result: false)
        let policy = AppActivationPolicy(application: application)

        #expect(policy.setDockIconVisible(true) == false)
        #expect(application.policies == [.regular])
    }

    @Test func defaultPolicyIsAccessory() {
        let application = ActivationPolicyApplicationSpy()
        let policy = AppActivationPolicy(application: application)

        policy.enterTemporaryRegularMode()
        policy.leaveTemporaryRegularMode()

        #expect(application.policies == [.regular, .accessory])
    }

    @Test func treatsAlreadyAppliedPolicyAsSuccess() {
        // AppKit reports false for redundant requests even though the app already
        // has the requested policy.
        let application = ActivationPolicyApplicationSpy(
            result: false,
            currentPolicy: .regular
        )
        let policy = AppActivationPolicy(application: application)

        #expect(policy.setDockIconVisible(true))
    }

    @Test func reportsFailureWhenPolicyDidNotChange() {
        let application = ActivationPolicyApplicationSpy(
            result: false,
            currentPolicy: .accessory
        )
        let policy = AppActivationPolicy(application: application)

        #expect(policy.setDockIconVisible(true) == false)
    }
}

@MainActor
private final class ActivationPolicyApplicationSpy: ApplicationActivationPolicyApplying {
    private let result: Bool
    private(set) var policies: [NSApplication.ActivationPolicy] = []
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy

    init(result: Bool = true, currentPolicy: NSApplication.ActivationPolicy = .accessory) {
        self.result = result
        self.currentActivationPolicy = currentPolicy
    }

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        policies.append(activationPolicy)
        guard result else { return false }
        currentActivationPolicy = activationPolicy
        return result
    }
}
