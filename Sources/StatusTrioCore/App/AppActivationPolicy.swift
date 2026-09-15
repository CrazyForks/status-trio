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
final class AppActivationPolicy {
    private let application: any ApplicationActivationPolicyApplying
    private var keepsDockIconVisible = false
    private var temporaryRegularRequestCount = 0

    /// Called whenever the app gains or loses its Dock tile.
    var dockTileVisibilityDidChange: ((Bool) -> Void)?

    /// Whether the app currently owns a Dock tile. That is only true while the
    /// app really is a regular app, whether the placement choice or a window
    /// that keeps the app in regular mode caused it.
    var isDockTileVisible: Bool {
        application.currentActivationPolicy == .regular
    }

    init(application: any ApplicationActivationPolicyApplying = NSApplication.shared) {
        self.application = application
    }

    @discardableResult
    func setDockIconVisible(_ isVisible: Bool) -> Bool {
        let wasVisible = isDockTileVisible
        keepsDockIconVisible = isVisible
        let didApply = apply()
        notifyDockTileVisibility(from: wasVisible)
        return didApply
    }

    func enterTemporaryRegularMode() {
        let wasVisible = isDockTileVisible
        temporaryRegularRequestCount += 1
        _ = apply()
        notifyDockTileVisibility(from: wasVisible)
    }

    func leaveTemporaryRegularMode() {
        let wasVisible = isDockTileVisible
        temporaryRegularRequestCount = max(0, temporaryRegularRequestCount - 1)
        _ = apply()
        notifyDockTileVisibility(from: wasVisible)
    }

    private func notifyDockTileVisibility(from wasVisible: Bool) {
        guard wasVisible != isDockTileVisible else { return }
        dockTileVisibilityDidChange?(isDockTileVisible)
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
        return didApply || application.currentActivationPolicy == policy
    }
}
