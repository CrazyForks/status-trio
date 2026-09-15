import AppKit

@MainActor
protocol ApplicationActivationPolicyApplying: AnyObject {
    var currentActivationPolicy: NSApplication.ActivationPolicy { get }
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool
}

extension NSApplication: ApplicationActivationPolicyApplying {
    var currentActivationPolicy: NSApplication.ActivationPolicy {
        activationPolicy()
    }
}

@MainActor
final class AppActivationPolicy: ObservableObject {
    private let application: any ApplicationActivationPolicyApplying
    private var keepsDockIconVisible = false
    private var temporaryRegularRequestCount = 0

    /// Whether the app currently runs as a regular app. That is only true while
    /// it really is regular, whether the placement choice or a window that keeps
    /// the app in regular mode caused it. A regular app owns both the Dock tile
    /// and the menu bar, so both follow this.
    @Published private(set) var isRegularApp: Bool

    init(application: any ApplicationActivationPolicyApplying = NSApplication.shared) {
        self.application = application
        self.isRegularApp = application.currentActivationPolicy == .regular
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
        // AppKit reports a redundant request as a failure even though the app is
        // already in the requested state, so confirm against the live policy
        // before treating a false result as a rejected transition.
        let didApply = application.setActivationPolicy(policy)
        let isRegular = application.currentActivationPolicy == .regular
        if isRegularApp != isRegular {
            isRegularApp = isRegular
        }
        return didApply || isRegular
    }
}
