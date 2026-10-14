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

/// Separates the feature opt-in from the helper's registration and approval.
///
/// Registering a LaunchDaemon does not start it: launchd only bootstraps the
/// daemon once an administrator approves it and the app first connects. So the
/// first opt-in requests registration. Opting out stops requests and leaves the
/// registration intact, so the daemon idle-exits without invalidating approval.
/// System Settings owns background authorization independently of this switch.
@MainActor
final class PrivilegedHelperManager: ObservableObject {
    static let shared = PrivilegedHelperManager()

    @Published private(set) var status: PrivilegedHelperStatus
    @Published private(set) var didFailLastOperation = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isHelperResponsive = false

    private let service: PrivilegedHelperServicing

    /// Whether the user wants Low Power Mode control. Seeded from the system
    /// state so a registration that an earlier session left waiting for approval
    /// is still shown as on.
    @Published private(set) var isEnabled: Bool

    /// How often the system state is re-read while a registration is pending.
    private let pollInterval: Duration
    private let healthCheckInterval: Duration
    private var nextPendingHealthCheck: ContinuousClock.Instant?
    private var pollTask: Task<Void, Never>?
    private var verificationTask: Task<Void, Never>?
    private var registrationRetryTask: Task<Void, Never>?
    private var registrationRetryGeneration: UInt64 = 0
    private var registrationNeedsApproval = false
    private var provisionalRegistrationError: String?
    private var generation: UInt64 = 0
    private var recoveryAttempts = 0
    private var recoveringGeneration: UInt64?
    private static let maximumRecoveryAttempts = 2

    init(
        service: PrivilegedHelperServicing = SystemPrivilegedHelperService(),
        pollInterval: Duration = .seconds(2),
        healthCheckInterval: Duration = .seconds(10)
    ) {
        self.service = service
        let initialStatus = service.status
        self.status = initialStatus
        self.isEnabled = initialStatus != .notRegistered
        self.pollInterval = pollInterval
        self.healthCheckInterval = healthCheckInterval
        // A previous session may have quit while the registration was still
        // waiting for approval, so start watching for the system to accept it.
        updateStatusPolling()
        checkHelperIfNeeded()
    }

    /// True while the system is waiting for the user to approve the helper.
    var requiresApproval: Bool {
        isEnabled && (status == .requiresApproval || registrationNeedsApproval)
    }

    /// Actual usability, independent of the native approval report. On some
    /// systems the report remains pending even after launchd permits XPC.
    /// A successful read is evidence of availability, not a rewritten approval.
    var isReady: Bool {
        isEnabled && status != .notRegistered && isHelperResponsive
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
        cancelRegistrationRetry()
        recoveryAttempts = 0
        registrationNeedsApproval = false
        provisionalRegistrationError = nil
        publishSystemState()
        didFailLastOperation = false
        lastErrorMessage = nil
        isEnabled = enabled

        if enabled {
            registerIfNeeded()
        }

        publishSystemState()
        updateStatusPolling()
        checkHelperIfNeeded()
        startRegistrationRetryWindow()
    }

    /// Restores intent; pending registration gets the same delayed retries.
    func restoreUserIntent(_ enabled: Bool) {
        if isEnabled != enabled { invalidateVerification() }
        isEnabled = enabled
        updateStatusPolling()
        checkHelperIfNeeded()
        if enabled { startRegistrationRetryWindow() } else { cancelRegistrationRetry() }
    }

    /// Activation and polling observe approval without changing registration.
    func refresh() {
        publishSystemState()
        updateStatusPolling()
        let pendingHealthCheckDue = status == .requiresApproval && isHelperResponsive
            && nextPendingHealthCheck.map { ContinuousClock.now >= $0 } == true
        checkHelperIfNeeded(forceRead: pendingHealthCheckDue)
    }

    /// Returning from approval can precede the system's permission update.
    /// Give it a bounded retry window without removing the pending service.
    func refreshAfterActivation() {
        refresh()
        checkHelperIfNeeded(forceRead: true)
        startRegistrationRetryWindow()
    }

    /// Pending approval or a usable helper retires a registration failure.
    /// An owned recovery's intermediate removal is ignored.
    private func publishSystemState() {
        guard recoveringGeneration != generation else { return }
        let observed = service.status
        if observed == .enabled {
            registrationNeedsApproval = false
            provisionalRegistrationError = nil
        }
        if observed != status {
            invalidateVerification()
            status = observed
            if observed == .enabled { checkHelperIfNeeded(forceRead: true) }
        }

        if didFailLastOperation,
           status == .requiresApproval || isReady {
            didFailLastOperation = false
            lastErrorMessage = nil
        }
    }

    /// A pending approval is an expected intermediate state, including when
    /// macOS reports EPERM from register(). Leave its registration intact.
    private func registerIfNeeded() {
        guard isEnabled, isAvailable, status != .enabled, !isReady else { return }
        do {
            try service.register()
        } catch {
            recordRegistrationError(error)
        }
    }

    private func recordRegistrationError(_ error: any Error) {
        let observed = service.status
        // EPERM may precede requiresApproval. Keep the native status intact,
        // but don't present the same approval denial as two different errors.
        let nsError = error as NSError
        // The exported domain constant requires macOS 15; its string also
        // identifies errors on the older macOS releases we support.
        let approvalDenied = nsError.domain == "SMAppServiceErrorDomain" && nsError.code == 1
        if observed == .requiresApproval || (observed == .notRegistered && approvalDenied) {
            registrationNeedsApproval = true
            provisionalRegistrationError = observed == .notRegistered ? error.localizedDescription : nil
            didFailLastOperation = false
            lastErrorMessage = nil
            return
        }
        registrationNeedsApproval = false
        provisionalRegistrationError = nil
        didFailLastOperation = true
        lastErrorMessage = error.localizedDescription
    }

    private func cancelRegistrationRetry() {
        registrationRetryGeneration &+= 1
        registrationRetryTask?.cancel()
        registrationRetryTask = nil
    }

    /// Retry only register(), at 2, 6, 14, 30 and 60 seconds by default.
    /// Polling stays read-only; a new user interaction may start another window.
    private func startRegistrationRetryWindow() {
        guard isAvailable, isEnabled, status != .enabled, !isReady,
              registrationRetryTask == nil else { return }
        let retryGeneration = registrationRetryGeneration
        registrationRetryTask = Task { [weak self, pollInterval] in
            for multiplier in [1, 2, 4, 8, 15] {
                do { try await Task.sleep(for: pollInterval * multiplier) }
                catch { return }
                guard !Task.isCancelled, let self,
                      self.registrationRetryGeneration == retryGeneration else { return }
                self.refresh()
                guard self.isEnabled, self.isAvailable else { break }
                if self.status == .enabled || self.isReady { break }
                self.registerIfNeeded()
                self.refresh()
                if self.status == .enabled || self.isReady { break }
            }
            guard let self, self.registrationRetryGeneration == retryGeneration else { return }
            self.registrationRetryTask = nil
            // EPERM alone is not proof of pending consent. If the service
            // never registered, retire the provisional hint and expose why.
            if self.isEnabled, self.status == .notRegistered,
               let error = self.provisionalRegistrationError {
                self.registrationNeedsApproval = false
                self.provisionalRegistrationError = nil
                self.didFailLastOperation = true
                self.lastErrorMessage = error
            }
        }
    }

    private func invalidateVerification() {
        generation &+= 1
        verificationTask?.cancel()
        verificationTask = nil
        isHelperResponsive = false
        nextPendingHealthCheck = nil
    }

    /// Probe registered helpers even while native approval lags. Only a failed
    /// read with native approval enabled can trigger registration recovery;
    /// pending failures are expected and never unregister the service.
    private func checkHelperIfNeeded(forceRead: Bool = false) {
        guard isEnabled, isAvailable, status != .notRegistered,
              forceRead || !isHelperResponsive,
              verificationTask == nil,
              status == .requiresApproval || forceRead
                || recoveryAttempts < Self.maximumRecoveryAttempts else { return }
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
                      self.isEnabled else { return }
                self.isHelperResponsive = false
                self.nextPendingHealthCheck = nil
                guard self.service.status == .enabled else { return }
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
                        self.startRegistrationRetryWindow()
                        return
                    }
                    try await self.service.verifyConnection()
                } catch {
                    guard !Task.isCancelled, self.generation == requestGeneration else { return }
                    self.recoveringGeneration = nil
                    self.recordRegistrationError(error)
                    self.publishSystemState()
                    self.startRegistrationRetryWindow()
                    return
                }
            }
            guard !Task.isCancelled, self.generation == requestGeneration,
                  self.isEnabled, self.service.status != .notRegistered else { return }
            self.isHelperResponsive = true
            self.nextPendingHealthCheck = ContinuousClock.now.advanced(by: self.healthCheckInterval)
            self.cancelRegistrationRetry()
            NSLog("StatusTrio power helper verified by XPC")
            self.publishSystemState()
        }
    }

    /// Watches the system state while a registration is pending.
    ///
    /// The state the app waits for can only be reached from System Settings, and
    /// macOS posts no notification when it changes, so re-reading on a timer is
    /// the only way the settings pane catches up without the user having to
    /// touch the app's switch again. The poll is read-only on purpose.
    private func updateStatusPolling() {
        guard isAvailable, isEnabled else {
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
        cancelRegistrationRetry()
        startRegistrationRetryWindow()
    }
}
