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
}

@MainActor
private final class ActivationPolicyApplicationSpy: ApplicationActivationPolicyApplying {
    private let result: Bool
    private(set) var policies: [NSApplication.ActivationPolicy] = []

    init(result: Bool = true) {
        self.result = result
    }

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        policies.append(activationPolicy)
        return result
    }
}
