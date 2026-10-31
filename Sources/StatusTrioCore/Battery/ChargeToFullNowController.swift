import Combine
import Foundation

struct ChargeToFullNowDemand: Equatable, Sendable {
    let settingEnabled: Bool
    let popoverVisible: Bool
    let batterySectionVisible: Bool
    let battery: BatteryStatus

    var showsSurface: Bool {
        settingEnabled
            && popoverVisible
            && batterySectionVisible
            && battery.isPresent
    }

    var canStartChargeToFull: Bool {
        showsSurface
            && battery.isConnectedToPower
            && !battery.isCharged
            && battery.percentage < 100
    }
}

enum ChargeToFullNowPresentation: Equatable, Sendable {
    case hidden
    case available
    case applying
    case chargingToFull
    case failed
    case unavailable
    case cancelConfirmationRequired(limit: Int, usedFallback: Bool)
    case cancelPending
    case cancelling
    case cancelFailed(message: String?)
    /// The limit is back and the battery is still charging toward it. No button
    /// is offered until that charge completes or the system stops it.
    case limitRestored(limit: Int, usedFallback: Bool)

    var showsButton: Bool {
        switch self {
        case .hidden, .unavailable, .limitRestored:
            false
        case .available,
             .applying,
             .chargingToFull,
             .failed,
             .cancelConfirmationRequired,
             .cancelPending,
             .cancelling,
             .cancelFailed:
            true
        }
    }

    var isRestoredLimit: Bool {
        if case .limitRestored = self {
            return true
        }
        return false
    }

    var isApplying: Bool {
        self == .applying
    }

    var isChargingToFull: Bool {
        self == .chargingToFull
    }

    var isCancelling: Bool {
        self == .cancelling
    }
}

@MainActor
final class ChargeToFullNowController: ObservableObject {
    @Published private(set) var presentation: ChargeToFullNowPresentation = .hidden

    var capability: ChargeToFullNowCapability {
        backend.capability
    }

    var isSettingAvailable: Bool {
        capability.isAvailable
    }

    private let backend: any BatteryChargeControlling
    private let sessionStore: any ChargeToFullNowSessionStoring
    /// The user's persisted charge limit, used only to restore a temporary
    /// override that macOS itself started. It never writes until the user asks.
    private let persistedChargeLimit: () -> Int?
    /// Last limit observed before macOS removed the persisted policy.
    private let limitMemory: any ChargeLimitMemoryStoring
    private let now: () -> Date
    private var currentDemand: ChargeToFullNowDemand?
    private var session: ChargeToFullNowSession?
    private var rememberedLimit: Int?
    private var restoredLimit: RestoredLimitState?
    private var sessionNeedsConfirmation = false
    private var isApplying = false
    private var isCancelling = false
    private var hasObservedTemporaryOverride = false

    private struct RestoredLimitState {
        let limit: Int
        let usedFallback: Bool
        let restoredAt: Date
        var hasObservedCharging: Bool
    }

    private struct ExternalRestoreTarget {
        let limit: Int
        /// True when the live plist value is gone and the remembered value is
        /// the only source; the user must confirm that guess before a write.
        let isFromMemory: Bool
    }

    init(
        backend: any BatteryChargeControlling,
        sessionStore: any ChargeToFullNowSessionStoring =
            VolatileChargeToFullNowSessionStore(),
        persistedChargeLimit: @escaping () -> Int? = { nil },
        limitMemory: any ChargeLimitMemoryStoring =
            VolatileChargeLimitMemoryStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.backend = backend
        self.sessionStore = sessionStore
        self.persistedChargeLimit = persistedChargeLimit
        self.limitMemory = limitMemory
        self.now = now
        session = sessionStore.load()
        sessionNeedsConfirmation = session != nil
        rememberedLimit = limitMemory.load()
    }

    func update(_ demand: ChargeToFullNowDemand) {
        currentDemand = demand
        guard !isApplying, !isCancelling else { return }
        guard demand.showsSurface, capability.isAvailable else {
            publish(.hidden)
            return
        }

        let state = backend.readState()
        if var restored = restoredLimit {
            if demand.battery.isCharging {
                restored.hasObservedCharging = true
                restoredLimit = restored
            }
            if shouldHoldRestoredLimit(restored, demand: demand, state: state) {
                publish(
                    .limitRestored(
                        limit: restored.limit,
                        usedFallback: restored.usedFallback
                    )
                )
                return
            }
            restoredLimit = nil
        }

        // A confirmation is an explicit user step. Keep it across live battery
        // ticks; the next tap re-reads the state before any write.
        if case .cancelConfirmationRequired = presentation {
            return
        }

        if state.errorMessage != nil {
            if session != nil {
                sessionNeedsConfirmation = true
                publish(.cancelFailed(message: state.errorMessage))
            } else {
                publish(.unavailable)
            }
            return
        }

        if state.hasActiveChargeLimit,
           let reportedLimit = state.reportedChargeLimit {
            rememberLimit(reportedLimit)
        }

        if session != nil, state.hasActiveChargeLimit {
            if mayBeStaleActiveLimit(state) {
                publish(.chargingToFull)
                return
            }
            // A later valid active limit means the override was ended or
            // replaced, including by the user or another app. Never overwrite it.
            clearSession()
        }

        if session != nil {
            hasObservedTemporaryOverride =
                hasObservedTemporaryOverride || state.indicatesTemporaryOverride
            publish(.chargingToFull)
            return
        }

        // macOS can start the same temporary override from its own battery
        // menu. There is no session, but a known user limit lets us offer the
        // same cancellation instead of hiding the row.
        if externalRestoreTarget(in: state) != nil {
            publish(.chargingToFull)
            return
        }

        guard demand.canStartChargeToFull else {
            publish(.hidden)
            return
        }
        publish(state.hasActiveChargeLimit ? .available : .hidden)
    }

    func clearDemand() {
        currentDemand = nil
        if !isApplying, !isCancelling {
            publish(.hidden)
        }
    }

    func performPrimaryAction() {
        switch presentation {
        case .chargingToFull, .cancelConfirmationRequired, .cancelPending, .cancelFailed:
            requestCancelChargeToFullNow()
        case .available, .failed:
            requestChargeToFullNow()
        case .hidden, .applying, .cancelling, .unavailable, .limitRestored:
            break
        }
    }

    func requestChargeToFullNow() {
        guard !isApplying,
              !isCancelling,
              session == nil,
              let requestedDemand = currentDemand,
              requestedDemand.canStartChargeToFull,
              capability.isAvailable else {
            return
        }

        let state = backend.readState()
        if state.errorMessage != nil {
            publish(.unavailable)
            return
        }
        guard state.hasActiveChargeLimit else {
            publish(.hidden)
            return
        }

        let originalLimit = state.reportedChargeLimit
        isApplying = true
        publish(.applying)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await backend.chargeToFullNow()
            isApplying = false
            if result.succeeded {
                let accepted = ChargeToFullNowSession(
                    originalLimit: originalLimit,
                    acceptedAt: now()
                )
                session = accepted
                sessionNeedsConfirmation = false
                hasObservedTemporaryOverride = false
                sessionStore.save(accepted)
            }

            guard let currentDemand,
                  currentDemand.showsSurface else {
                publish(.hidden)
                return
            }
            publish(result.succeeded ? .chargingToFull : .failed)
        }
    }

    func requestCancelChargeToFullNow() {
        guard !isApplying,
              !isCancelling,
              let requestedDemand = currentDemand,
              requestedDemand.showsSurface,
              capability.isAvailable else {
            return
        }

        let state = backend.readState()

        if let activeSession = session {
            if state.hasActiveChargeLimit {
                if mayBeStaleActiveLimit(state) {
                    publish(.cancelPending)
                    return
                }
                clearSession()
                publish(
                    requestedDemand.canStartChargeToFull
                        ? .available
                        : .hidden
                )
                return
            }

            let target = validatedLimit(
                state.reportedChargeLimit ?? activeSession.originalLimit,
                in: state
            )
            let limit = target ?? 80
            let usedFallback = target == nil
            let needsConfirmation = sessionNeedsConfirmation
                || state.errorMessage != nil
                || usedFallback
                || (state.errorMessage == nil
                    && !state.indicatesTemporaryOverride)

            if needsConfirmation,
               presentation != .cancelConfirmationRequired(
                   limit: limit,
                   usedFallback: usedFallback
               ) {
                publish(
                    .cancelConfirmationRequired(
                        limit: limit,
                        usedFallback: usedFallback
                    )
                )
                return
            }

            beginRestore(limit: limit, usedFallback: usedFallback)
            return
        }

        // No session: the temporary override was started by macOS itself, for
        // example from the system battery menu. Restore the limit the user
        // picked in System Settings without pretending we started the request.
        guard state.errorMessage == nil,
              state.indicatesTemporaryOverride,
              let target = externalRestoreTarget(in: state) else {
            publish(
                requestedDemand.canStartChargeToFull
                    && state.hasActiveChargeLimit
                    ? .available
                    : .hidden
            )
            return
        }
        if target.isFromMemory,
           presentation != .cancelConfirmationRequired(
               limit: target.limit,
               usedFallback: false
           ) {
            publish(
                .cancelConfirmationRequired(
                    limit: target.limit,
                    usedFallback: false
                )
            )
            return
        }
        beginRestore(limit: target.limit, usedFallback: false)
    }

    private func beginRestore(limit: Int, usedFallback: Bool) {
        isCancelling = true
        publish(.cancelling)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await backend.restoreChargeLimit(to: limit)
            isCancelling = false
            let verification = backend.readState()
            let verified = result.succeeded
                && verification.hasActiveChargeLimit
                && verification.reportedChargeLimit == limit

            if verified {
                clearSession()
                rememberLimit(limit)
                restoredLimit = RestoredLimitState(
                    limit: limit,
                    usedFallback: usedFallback,
                    restoredAt: now(),
                    hasObservedCharging: false
                )
            }

            guard let currentDemand,
                  currentDemand.showsSurface else {
                publish(.hidden)
                return
            }

            if verified {
                publish(
                    .limitRestored(
                        limit: limit,
                        usedFallback: usedFallback
                    )
                )
            } else {
                publish(
                    .cancelFailed(
                        message: result.errorMessage
                            ?? verification.errorMessage
                            ?? "PowerUI did not confirm the restored charge limit."
                    )
                )
            }
        }
    }

    /// The restored limit stays visible while the system keeps charging toward
    /// it. The action comes back once the battery reaches the limit or the
    /// system stops charging before it.
    private func shouldHoldRestoredLimit(
        _ restored: RestoredLimitState,
        demand: ChargeToFullNowDemand,
        state: ChargeToFullNowDeviceState
    ) -> Bool {
        guard state.errorMessage == nil,
              state.hasActiveChargeLimit,
              state.reportedChargeLimit == restored.limit,
              demand.canStartChargeToFull,
              demand.battery.percentage < restored.limit else {
            return false
        }
        if restored.hasObservedCharging {
            return demand.battery.isCharging
        }
        // The system needs a moment to resume charging after the restore. Give
        // it a bounded grace period instead of keeping an inert row forever.
        return now().timeIntervalSince(restored.restoredAt) < 30
    }

    /// macOS can remove the persisted policy while its own temporary override
    /// runs. Prefer the live plist value, then fall back to the last limit the
    /// app observed; a remembered value always requires confirmation.
    private func externalRestoreTarget(
        in state: ChargeToFullNowDeviceState
    ) -> ExternalRestoreTarget? {
        guard state.indicatesTemporaryOverride else {
            return nil
        }
        if let persisted = persistedChargeLimit(),
           let limit = validatedLimit(persisted, in: state) {
            rememberLimit(limit)
            return ExternalRestoreTarget(limit: limit, isFromMemory: false)
        }
        if let remembered = rememberedLimit,
           let limit = validatedLimit(remembered, in: state) {
            return ExternalRestoreTarget(limit: limit, isFromMemory: true)
        }
        return nil
    }

    private func rememberLimit(_ limit: Int) {
        guard (80..<100).contains(limit), rememberedLimit != limit else {
            return
        }
        rememberedLimit = limit
        limitMemory.save(limit)
    }

    private func validatedLimit(
        _ candidate: Int?,
        in state: ChargeToFullNowDeviceState
    ) -> Int? {
        guard let candidate, (80..<100).contains(candidate) else {
            return nil
        }
        if !state.availableChargeLimits.isEmpty {
            return state.availableChargeLimits.contains(candidate) ? candidate : nil
        }
        return [80, 85, 90, 95].contains(candidate) ? candidate : nil
    }

    private func clearSession() {
        session = nil
        sessionNeedsConfirmation = false
        hasObservedTemporaryOverride = false
        sessionStore.clear()
    }

    private func mayBeStaleActiveLimit(
        _ state: ChargeToFullNowDeviceState
    ) -> Bool {
        guard let session,
              !hasObservedTemporaryOverride,
              state.reportedChargeLimit == session.originalLimit else {
            return false
        }
        // The measured override took up to 10 seconds to appear in PowerUI.
        // A bounded grace period is evaluated only on demand, with no timer.
        let elapsed = now().timeIntervalSince(session.acceptedAt)
        return (0..<15).contains(elapsed)
    }

    private func publish(_ next: ChargeToFullNowPresentation) {
        guard presentation != next else { return }
        presentation = next
    }
}
