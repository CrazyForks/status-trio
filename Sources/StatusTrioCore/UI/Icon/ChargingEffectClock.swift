import Combine
import Foundation

@MainActor
final class ChargingEffectClock: ObservableObject {
    static let tickInterval = Duration.milliseconds(50)
    // Subtracting two Date values can compound their ~120-ns absolute precision
    // near the present epoch; allow a 500-ns clock-edge snap (1e-5 of a frame).
    private static let frameBoundaryTolerance = 1e-5 / Double(ChargingEffectTimeline.framesPerSecond)
    private static let frameBoundaryToleranceInFrames = 1e-5
    private static let heartbeatDuration: TimeInterval = 0.25

    @Published private(set) var phase: ChargingEffectPhase?
    @Published private(set) var dockPhase: ChargingEffectPhase?
    @Published private(set) var isRunning = false

    private let now: () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var task: Task<Void, Never>?
    private var battery: BatteryStatus = .placeholder
    private var previousBattery: BatteryStatus? = .placeholder
    private var enabled = false
    private var reduceMotion = false
    private var displayAsleep = false
    private var burstStartedAt: Date?
    private var burstEvent: ChargingEffectEvent?
    private var steadyStartedAt: Date?
    private var boostedHeartbeatCycle: Int?

    init(
        now: @escaping () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.now = now
        self.sleep = sleep
    }

    func update(
        battery: BatteryStatus,
        enabled: Bool,
        reduceMotion: Bool,
        displayAsleep: Bool
    ) {
        let priorBattery = previousBattery
        previousBattery = battery
        self.battery = battery
        self.enabled = enabled
        self.reduceMotion = reduceMotion
        self.displayAsleep = displayAsleep

        guard ChargingEffectPolicy.shouldAnimate(
            battery: battery,
            enabled: enabled,
            reduceMotion: reduceMotion,
            displayAsleep: displayAsleep
        ) else {
            stop()
            return
        }

        let event = priorBattery.map {
            ChargingEffectEvent.between(previous: $0, current: battery)
        } ?? nil

        if task == nil {
            let eventDate = now()
            beginTimeline(for: event, at: eventDate)
            if event == .levelAdvanced {
                scheduleHeartbeatBoost(at: eventDate)
            }
            start()
            return
        }

        let eventDate = now()
        switch event {
        case .pluggedIn:
            beginTimeline(for: .pluggedIn, at: eventDate)
        case .levelAdvanced:
            scheduleHeartbeatBoost(at: eventDate)
            burstStartedAt = eventDate
            burstEvent = .levelAdvanced
        case nil:
            break
        }
        let phaseDate = now()
        phase = phase(at: phaseDate)
        dockPhase = dockPhase(at: phaseDate)
    }

    func start() {
        guard task == nil,
              ChargingEffectPolicy.shouldAnimate(
                battery: battery,
                enabled: enabled,
                reduceMotion: reduceMotion,
                displayAsleep: displayAsleep
              ) else {
            return
        }

        if steadyStartedAt == nil {
            beginTimeline(for: nil, at: now())
        }
        isRunning = true
        let phaseDate = now()
        phase = phase(at: phaseDate)
        dockPhase = dockPhase(at: phaseDate)

        let sleep = self.sleep
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(Self.tickInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                let phaseDate = self.now()
                self.phase = self.phase(at: phaseDate)
                self.dockPhase = self.dockPhase(at: phaseDate)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        phase = nil
        dockPhase = nil
        burstStartedAt = nil
        burstEvent = nil
        steadyStartedAt = nil
        boostedHeartbeatCycle = nil
    }

    private func beginTimeline(for event: ChargingEffectEvent?, at date: Date) {
        boostedHeartbeatCycle = nil
        switch event {
        case .pluggedIn:
            burstStartedAt = date
            burstEvent = .pluggedIn
            steadyStartedAt = date.addingTimeInterval(ChargingEffectTimeline.burstDuration)
        case .levelAdvanced:
            burstStartedAt = date
            burstEvent = .levelAdvanced
            steadyStartedAt = date
        case nil:
            burstStartedAt = nil
            burstEvent = nil
            steadyStartedAt = date
        }
    }

    private func scheduleHeartbeatBoost(at date: Date) {
        guard let steadyStartedAt else { return }
        let elapsed = max(0, date.timeIntervalSince(steadyStartedAt))
        let adjustedElapsed = elapsed + Self.frameBoundaryTolerance
        let cycleDuration = ChargingEffectTimeline.steadyCycleDuration
        let cycleIndex = Int((adjustedElapsed / cycleDuration).rounded(.down))
        let cycleElapsed = adjustedElapsed.truncatingRemainder(dividingBy: cycleDuration)
        let heartbeatStartsAt = cycleDuration - Self.heartbeatDuration
        boostedHeartbeatCycle = cycleIndex + (cycleElapsed >= heartbeatStartsAt ? 1 : 0)
    }

    private func phase(at date: Date) -> ChargingEffectPhase? {
        guard let steadyStartedAt else { return nil }

        if burstEvent == .pluggedIn, let burstPhase = dockPhase(at: date) {
            return burstPhase
        }

        let steadyElapsed = max(0, date.timeIntervalSince(steadyStartedAt))
        let adjustedElapsed = steadyElapsed + Self.frameBoundaryTolerance
        let cycleDuration = ChargingEffectTimeline.steadyCycleDuration
        let cycleIndex = Int((adjustedElapsed / cycleDuration).rounded(.down))
        let multiplier = cycleIndex == boostedHeartbeatCycle ? 1.35 : 1
        return ChargingEffectTimeline.phase(
            elapsed: adjustedElapsed,
            kind: .steady,
            heartbeatMultiplier: multiplier
        )
    }

    private func dockPhase(at date: Date) -> ChargingEffectPhase? {
        guard let burstStartedAt, let burstEvent else { return nil }
        let burstElapsed = max(0, date.timeIntervalSince(burstStartedAt))
        let adjustedElapsed = burstElapsed + Self.frameBoundaryTolerance
        let burstFramePosition = adjustedElapsed * Double(ChargingEffectTimeline.framesPerSecond)
        let burstDuration = ChargingEffectTimeline.cycleDuration(for: .burst, event: burstEvent)
        let burstFrameCount = Double(
            (burstDuration * Double(ChargingEffectTimeline.framesPerSecond)).rounded()
        )
        guard burstFramePosition + Self.frameBoundaryToleranceInFrames < burstFrameCount else {
            return nil
        }
        return ChargingEffectTimeline.phase(
            elapsed: adjustedElapsed,
            kind: .burst,
            event: burstEvent
        )
    }
}
