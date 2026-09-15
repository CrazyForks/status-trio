import AppKit

@MainActor
protocol ApplicationActivationPolicyApplying: AnyObject {
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool
}

extension NSApplication: ApplicationActivationPolicyApplying {}

@MainActor
final class AppActivationPolicy {
    private let application: any ApplicationActivationPolicyApplying
    private var keepsDockIconVisible = false
    private var temporaryRegularRequestCount = 0

    init(application: any ApplicationActivationPolicyApplying = NSApplication.shared) {
        self.application = application
    }

    @discardableResult
    func setDockIconVisible(_ isVisible: Bool) -> Bool {
        keepsDockIconVisible = isVisible
        return apply()
    }

    func enterTemporaryRegularMode() {
        temporaryRegularRequestCount += 1
        _ = apply()
    }

    func leaveTemporaryRegularMode() {
        temporaryRegularRequestCount = max(0, temporaryRegularRequestCount - 1)
        _ = apply()
    }

    @discardableResult
    private func apply() -> Bool {
        let policy: NSApplication.ActivationPolicy = keepsDockIconVisible
            || temporaryRegularRequestCount > 0
            ? .regular
            : .accessory
        return application.setActivationPolicy(policy)
    }
}
