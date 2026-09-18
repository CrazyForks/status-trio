import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct ManualUpdatePresentationTests {
    @Test func keepsDockTileOwnedByPlacementWhilePresenting() {
        // A Dock-icon placement owns the regular policy. A manual update check
        // may borrow regular mode, but dismissing "You're up to date" must not
        // hand the app back to accessory and take our Dock tile with it.
        let application = ManualUpdatePolicySpy()
        let policy = AppActivationPolicy(application: application)
        #expect(policy.setDockIconVisible(true))
        application.reset()

        let presentation = ManualUpdatePresentation(
            activationPolicy: policy,
            application: ManualUpdateApplicationSpy()
        )
        presentation.begin()
        presentation.end()

        #expect(application.policies == [.regular, .regular])
        #expect(policy.isRegularApp)
    }

    @Test func removesBorrowedRegularModeForMenuBarOnlyPlacement() {
        let application = ManualUpdatePolicySpy()
        let policy = AppActivationPolicy(application: application)
        let presentation = ManualUpdatePresentation(
            activationPolicy: policy,
            application: ManualUpdateApplicationSpy()
        )

        presentation.begin()
        #expect(policy.isRegularApp)

        presentation.end()

        #expect(application.policies == [.regular, .accessory])
        #expect(policy.isRegularApp == false)
    }

    @Test func frontActivatesTheAppOncePerCheck() {
        let application = ManualUpdatePolicySpy()
        let policy = AppActivationPolicy(application: application)
        let activating = ManualUpdateApplicationSpy()
        let presentation = ManualUpdatePresentation(
            activationPolicy: policy,
            application: activating
        )

        presentation.begin()
        presentation.begin()
        presentation.end()

        #expect(activating.activationCount == 1)
        #expect(application.policies == [.regular, .accessory])
    }

    @Test func backgroundCyclesDoNotTouchActivationPolicy() {
        // Background checks finish an update cycle too, and must never change
        // the activation policy the icon placement owns.
        let application = ManualUpdatePolicySpy()
        let policy = AppActivationPolicy(application: application)
        let activating = ManualUpdateApplicationSpy()
        let presentation = ManualUpdatePresentation(
            activationPolicy: policy,
            application: activating
        )

        presentation.end()

        #expect(application.policies.isEmpty)
        #expect(activating.activationCount == 0)
    }

    @Test func settingsWindowRegularModeSurvivesManualCheck() {
        // Checking for updates from the Settings window nests inside the regular
        // mode that window already owns, so finishing the check must leave it up.
        let application = ManualUpdatePolicySpy()
        let policy = AppActivationPolicy(application: application)
        policy.enterTemporaryRegularMode()

        let presentation = ManualUpdatePresentation(
            activationPolicy: policy,
            application: ManualUpdateApplicationSpy()
        )
        presentation.begin()
        presentation.end()

        #expect(policy.isRegularApp)
        #expect(application.policies.last == .regular)

        policy.leaveTemporaryRegularMode()
        #expect(policy.isRegularApp == false)
    }
}

@MainActor
private final class ManualUpdatePolicySpy: ApplicationActivationPolicyApplying {
    private(set) var policies: [NSApplication.ActivationPolicy] = []
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory

    func reset() {
        policies.removeAll()
    }

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        policies.append(activationPolicy)
        currentActivationPolicy = activationPolicy
        return true
    }
}

@MainActor
private final class ManualUpdateApplicationSpy: ApplicationActivating {
    private(set) var activationCount = 0

    func activate(ignoringOtherApps flag: Bool) {
        activationCount += 1
    }
}
