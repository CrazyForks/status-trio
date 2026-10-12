import AppKit
import Combine

/// Keeps the privileged helper's registration and the persisted Low Power Mode
/// opt-in in step.
///
/// The registration is the source of truth: `SMAppService` owns the daemon's
/// state, and the user can also change it from System Settings, so a persisted
/// bool alone would drift. The toggle writes through `PrivilegedHelperManager`
/// (which registers or unregisters), and this synchronizer copies the resulting
/// status back into `SettingsStore.controlsLowPowerMode` so the feature stays
/// on across launches only while the helper is actually registered.
@MainActor
final class LowPowerModeControlSynchronizer {
    private var cancellables = Set<AnyCancellable>()
    private var activationObserver: NSObjectProtocol?

    func start(settings: SettingsStore, helper: PrivilegedHelperManager) {
        guard cancellables.isEmpty, activationObserver == nil else { return }

        // Mirror the manager's registration state into the persisted flag.
        helper.$status
            .map { $0 != .notRegistered }
            .removeDuplicates()
            .sink { [weak settings] isRegistered in
                guard let settings, settings.controlsLowPowerMode != isRegistered else { return }
                settings.controlsLowPowerMode = isRegistered
            }
            .store(in: &cancellables)

        // On launch, reconcile: if the user asked for the feature previously but
        // the helper is no longer registered (uninstalled, revoked in System
        // Settings), clear the flag rather than showing a dead control.
        if settings.controlsLowPowerMode && !helper.isEnabled {
            settings.controlsLowPowerMode = false
        }

        // Approval happens in System Settings, so re-read the status when the app
        // comes back to the foreground. Without this, a registration approved
        // while the app was in the background keeps showing "waiting for
        // approval" until the Settings window is closed and reopened.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak helper] _ in
            Task { @MainActor in helper?.refresh() }
        }
    }

    func stop() {
        cancellables.removeAll()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }
}