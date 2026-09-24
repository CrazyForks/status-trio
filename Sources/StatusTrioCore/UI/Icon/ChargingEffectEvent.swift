import Foundation

enum ChargingEffectEvent: Equatable, Sendable {
    case pluggedIn
    case levelAdvanced

    static func between(
        previous: BatteryStatus,
        current: BatteryStatus
    ) -> ChargingEffectEvent? {
        guard current.isCharging, !current.isCharged else { return nil }

        if !previous.isCharging {
            return .pluggedIn
        }
        guard !previous.isCharged,
              current.percentage > previous.percentage else {
            return nil
        }
        return .levelAdvanced
    }
}
