import Combine
import Foundation
import PowerHelperProtocol
import ServiceManagement
import SwiftUI

/// The privileged power helper's registration as reported by the system.
enum PrivilegedHelperStatus: Equatable, Sendable {
    /// Not registered, so launchd will not start the daemon.
    ///
    /// macOS reports an app that has never registered as `notRegistered` on
    /// some versions and `notFound` on others, so both collapse into this case.
    case notRegistered
    /// Registered, but an administrator must approve it in Login Items before
    /// launchd will bootstrap the daemon.
    case requiresApproval
    /// Approved; the daemon starts on demand when the app connects.
    case enabled
}

/// Abstracts `SMAppService.daemon` so the manager can be exercised with a fake.
@MainActor
protocol PrivilegedHelperServicing: AnyObject {
    /// False when the helper cannot run here: not an app bundle, the build
    /// excluded the helper, or the daemon binary is missing.
    var isSupported: Bool { get }
    var status: PrivilegedHelperStatus { get }
    func register() throws
    func unregister() throws
    func openLoginItemsSettings()
}

@MainActor
final class SystemPrivilegedHelperService: PrivilegedHelperServicing {
    private let service = SMAppService.daemon(plistName: PowerHelperConstants.launchDaemonPlistName)

    /// The daemon must be present in the bundle for registration to mean
    /// anything; an Ad-hoc build cannot satisfy the daemon's signing
    /// requirement, so the feature is offered only when the build declared it.
    var isSupported: Bool {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return false }
        guard AppMetadata.includesPrivilegedHelper else { return false }
        return FileManager.default.isExecutableFile(atPath: Self.daemonURL.path)
    }

    private static var daemonURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/StatusTrioPowerHelper", isDirectory: false)
    }

    var status: PrivilegedHelperStatus {
        Self.status(for: service.status)
    }

    /// `SMAppService` answers `notFound` for a daemon that has never been
    /// registered, which is the same situation as `notRegistered` for our UI.
    /// Registering still works from that state, so it must not disable the toggle.
    static func status(for status: SMAppService.Status) -> PrivilegedHelperStatus {
        switch status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered, .notFound:
            .notRegistered
        @unknown default:
            .notRegistered
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Keeps the privileged helper registration in sync with the user's opt-in and
/// republishes the system state so the settings UI can react to it.
///
/// Registering a LaunchDaemon does not start it: launchd only bootstraps the
/// daemon once an administrator approves it and the app first connects. So the
/// opt-in both requests registration and, on untick, unregisters — the daemon
/// never runs unless the user asked for the feature. Approval itself happens in
/// System Settings, so a registration that is still pending is watched until the
/// system accepts it.
@MainActor
final class PrivilegedHelperManager: ObservableObject {
    static let shared = PrivilegedHelperManager()

    @Published private(set) var status: PrivilegedHelperStatus
    @Published private(set) var didFailLastOperation = false
    @Published private(set) var lastErrorMessage: String?

    private let service: PrivilegedHelperServicing

    /// The opt-in value whose last attempt failed.
    ///
    /// Approval happens in System Settings, so the state the failed call wanted
    /// can arrive later without any further action in the app. Remembering what
    /// was attempted lets `refresh()` drop the error once the system catches up
    /// instead of leaving the failure banner on screen until the user happens to
    /// touch the toggle again.
    private var failedOperationTarget: Bool?

    /// Whether the user wants the helper registered. Seeded from the system
    /// state so a registration that an earlier session left waiting for approval
    /// is still shown as on.
    @Published private(set) var isEnabled: Bool

    /// How often the system state is re-read while a registration is pending.
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?

    init(
        service: PrivilegedHelperServicing = SystemPrivilegedHelperService(),
        pollInterval: Duration = .seconds(2)
    ) {
        self.service = service
        let initialStatus = service.status
        self.status = initialStatus
        self.isEnabled = initialStatus != .notRegistered
        self.pollInterval = pollInterval
        // A previous session may have quit while the registration was still
        // waiting for approval, so start watching for the system to accept it.
        updateStatusPolling()
    }

    /// True while the system is waiting for the user to approve the helper.
    var requiresApproval: Bool {
        status == .requiresApproval
    }

    /// True only once the helper is approved and launchd can start it. The Low
    /// Power Mode control is offered on this, not on `isEnabled`: a registration
    /// that still awaits approval has no daemon behind it yet.
    var isApproved: Bool {
        status == .enabled
    }

    /// False when this build or process cannot offer the helper at all.
    var isAvailable: Bool {
        service.isSupported
    }

    var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.isEnabled },
            set: { self.setEnabled($0) }
        )
    }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        publishSystemState()
        didFailLastOperation = false
        lastErrorMessage = nil
        failedOperationTarget = nil
        isEnabled = enabled

        if enabled {
            registerIfNeeded()
        } else if status != .notRegistered {
            unregister()
        }

        publishSystemState()
        updateStatusPolling()
    }

    /// Restores a saved opt-in without mutating registration during startup.
    func restoreUserIntent(_ enabled: Bool) {
        isEnabled = enabled
        updateStatusPolling()
    }

    /// Activation and polling observe approval without changing registration.
    func refresh() {
        publishSystemState()
        updateStatusPolling()
    }

    /// Reads the system state and retires a failure the system has since
    /// satisfied. `requiresApproval` is not enough to retire a failed
    /// registration: a `register()` that macOS rejects with "Operation not
    /// permitted" leaves the item in exactly that state, so the banner stays
    /// until the daemon is really `.enabled`. A failed unregister is settled by
    /// the item disappearing.
    private func publishSystemState() {
        status = service.status

        if let target = failedOperationTarget {
            let satisfied = target ? status == .enabled : status == .notRegistered
            if satisfied {
                failedOperationTarget = nil
                didFailLastOperation = false
                lastErrorMessage = nil
            }
        }
    }

    /// An explicit enable retries a pending registration. Background refreshes
    /// never perform this unregister/register sequence.
    private func registerIfNeeded() {
        guard isEnabled, isAvailable, status != .enabled else { return }
        do {
            if status == .requiresApproval {
                try service.unregister()
            }
            try service.register()
            status = service.status
        } catch {
            didFailLastOperation = true
            lastErrorMessage = error.localizedDescription
            failedOperationTarget = true
        }
    }

    private func unregister() {
        do {
            try service.unregister()
        } catch {
            didFailLastOperation = true
            lastErrorMessage = error.localizedDescription
            failedOperationTarget = false
        }
    }

    /// Watches the system state while a registration is pending.
    ///
    /// The state the app waits for can only be reached from System Settings, and
    /// macOS posts no notification when it changes, so re-reading on a timer is
    /// the only way the settings pane catches up without the user having to
    /// touch the app's switch again. The poll is read-only on purpose.
    private func updateStatusPolling() {
        guard isAvailable, isEnabled || failedOperationTarget != nil else {
            pollTask?.cancel()
            pollTask = nil
            return
        }
        guard pollTask == nil else { return }

        pollTask = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    func openLoginItemsSettings() {
        service.openLoginItemsSettings()
    }
}
