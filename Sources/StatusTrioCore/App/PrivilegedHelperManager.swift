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
    func unregisterForRecovery() async throws
    func verifyConnection() async throws
    func openLoginItemsSettings()
}

@MainActor
final class SystemPrivilegedHelperService: PrivilegedHelperServicing {
    private var service: SMAppService {
        SMAppService.daemon(plistName: PowerHelperConstants.launchDaemonPlistName)
    }

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

    func unregisterForRecovery() async throws {
        try await service.unregister()
    }

    func verifyConnection() async throws {
        _ = try await XPCPrivilegedHelperClient().readLowPowerMode()
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
    @Published private(set) var isHelperResponsive = false

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
    private var verificationTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var recoveryAttempts = 0
    private var approvalRetryAttempts = 0
    private var recoveringGeneration: UInt64?
    private static let maximumRecoveryAttempts = 2
    private static let maximumApprovalRetryAttempts = 3

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
        checkHelperIfNeeded()
    }

    /// True while the system is waiting for the user to approve the helper.
    var requiresApproval: Bool {
        status == .requiresApproval
    }

    /// True only once the helper is approved and launchd can start it. The Low
    /// Power Mode control is offered on this, not on `isEnabled`: a registration
    /// that still awaits approval has no daemon behind it yet.
    var isApproved: Bool {
        isEnabled && status == .enabled && isHelperResponsive
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
        invalidateVerification()
        recoveryAttempts = 0
        approvalRetryAttempts = 0
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
        checkHelperIfNeeded()
    }

    /// Restores a saved opt-in without mutating registration during startup.
    func restoreUserIntent(_ enabled: Bool) {
        if isEnabled != enabled { invalidateVerification() }
        isEnabled = enabled
        updateStatusPolling()
        checkHelperIfNeeded()
    }

    /// Activation and polling observe approval without changing registration.
    func refresh() {
        publishSystemState()
        updateStatusPolling()
        checkHelperIfNeeded()
    }

    /// Retry only registration when returning from the approval UI. Never
    /// unregister a pending service, and stop after three attempts per opt-in.
    func refreshAfterActivation() {
        if verificationTask == nil, isEnabled, status == .enabled {
            isHelperResponsive = false
        }
        refresh()
        if status == .enabled { checkHelperIfNeeded(forceRead: true) }
        guard isEnabled, isAvailable, status == .requiresApproval,
              approvalRetryAttempts < Self.maximumApprovalRetryAttempts else { return }
        approvalRetryAttempts += 1
        registerIfNeeded()
        refresh()
    }

    /// Pending approval is expected. A usable helper or a completed unregister
    /// retires a failure; an owned recovery's intermediate removal is ignored.
    private func publishSystemState() {
        guard recoveringGeneration != generation else { return }
        let observed = service.status
        if observed != status {
            invalidateVerification()
            status = observed
            if observed == .enabled { checkHelperIfNeeded(forceRead: true) }
        }

        if let target = failedOperationTarget {
            let satisfied = target
                ? status == .requiresApproval || (status == .enabled && isHelperResponsive)
                : status == .notRegistered
            if satisfied {
                failedOperationTarget = nil
                didFailLastOperation = false
                lastErrorMessage = nil
            }
        }
    }

    /// A pending approval is an expected intermediate state, including when
    /// macOS reports EPERM from register(). Leave its registration intact.
    private func registerIfNeeded() {
        guard isEnabled, isAvailable, status != .enabled else { return }
        do {
            try service.register()
        } catch {
            recordRegistrationError(error)
        }
    }

    private func recordRegistrationError(_ error: any Error) {
        guard service.status != .requiresApproval else { return }
        didFailLastOperation = true
        lastErrorMessage = error.localizedDescription
        failedOperationTarget = true
    }

    private func invalidateVerification() {
        generation &+= 1
        verificationTask?.cancel()
        verificationTask = nil
        isHelperResponsive = false
    }

    /// Only a failed read from an approved service can trigger recovery. A
    /// daemon that has idle-exited will answer the read after launchd starts it.
    private func checkHelperIfNeeded(forceRead: Bool = false) {
        guard isEnabled, isAvailable, status == .enabled, !isHelperResponsive,
              verificationTask == nil,
              forceRead || recoveryAttempts < Self.maximumRecoveryAttempts else { return }
        let requestGeneration = generation
        verificationTask = Task { [weak self] in
            guard let self, !Task.isCancelled, self.isEnabled,
                  self.generation == requestGeneration else { return }
            defer {
                if self.recoveringGeneration == requestGeneration {
                    self.recoveringGeneration = nil
                }
                if self.generation == requestGeneration { self.verificationTask = nil }
            }
            do {
                try await self.service.verifyConnection()
            } catch {
                guard !Task.isCancelled, self.generation == requestGeneration,
                      self.isEnabled, self.service.status == .enabled else { return }
                guard self.recoveryAttempts < Self.maximumRecoveryAttempts else {
                    self.recordRegistrationError(error)
                    return
                }
                self.recoveryAttempts += 1
                NSLog("StatusTrio power helper recovery %d/%d after failed XPC read: %@",
                      self.recoveryAttempts, Self.maximumRecoveryAttempts,
                      error.localizedDescription)
                do {
                    // Await completion before registering again. A synchronous
                    // unregister may still be removing the job when it returns.
                    self.recoveringGeneration = requestGeneration
                    try await self.service.unregisterForRecovery()
                    guard !Task.isCancelled, self.generation == requestGeneration,
                          self.isEnabled else { return }
                    try self.service.register()
                    self.recoveringGeneration = nil
                    guard self.service.status == .enabled else {
                        self.publishSystemState()
                        return
                    }
                    try await self.service.verifyConnection()
                } catch {
                    guard !Task.isCancelled, self.generation == requestGeneration else { return }
                    self.recoveringGeneration = nil
                    self.recordRegistrationError(error)
                    self.publishSystemState()
                    return
                }
            }
            guard !Task.isCancelled, self.generation == requestGeneration,
                  self.isEnabled, self.service.status == .enabled else { return }
            self.isHelperResponsive = true
            NSLog("StatusTrio power helper verified by XPC")
            self.publishSystemState()
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
