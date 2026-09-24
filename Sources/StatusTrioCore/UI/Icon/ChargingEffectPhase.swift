import Foundation

struct ChargingEffectPhase: Equatable, Hashable, Sendable {
    enum Kind: Equatable, Hashable, Sendable {
        case burst
        case steady
    }

    let step: Int
    let stepsPerCycle: Int
    let kind: Kind
    let heartbeatMultiplier: Double

    init(
        step: Int,
        stepsPerCycle: Int,
        kind: Kind,
        heartbeatMultiplier: Double = 1
    ) {
        self.step = step
        self.stepsPerCycle = stepsPerCycle
        self.kind = kind
        self.heartbeatMultiplier = heartbeatMultiplier
    }
}
