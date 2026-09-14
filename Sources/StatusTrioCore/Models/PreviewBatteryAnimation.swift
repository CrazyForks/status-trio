import Foundation

struct PreviewBatteryAnimationFrame: Equatable, Sendable {
    let percentage: Int
    let isCharging: Bool
    let isCharged: Bool
    let isLowPowerMode: Bool
    let isConnectedToPower: Bool

    static func discharging(percentage: Int) -> PreviewBatteryAnimationFrame {
        PreviewBatteryAnimationFrame(
            percentage: percentage,
            isCharging: false,
            isCharged: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
    }

    static func charging(percentage: Int) -> PreviewBatteryAnimationFrame {
        PreviewBatteryAnimationFrame(
            percentage: percentage,
            isCharging: true,
            isCharged: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
    }

    static let fullyCharged = PreviewBatteryAnimationFrame(
        percentage: 100,
        isCharging: false,
        isCharged: true,
        isLowPowerMode: false,
        isConnectedToPower: true
    )
}

enum PreviewBatteryAnimation {
    static let frameInterval: Duration = .milliseconds(50)

    static let frames: [PreviewBatteryAnimationFrame] = {
        let drain = stride(from: 100, through: 1, by: -1).map {
            PreviewBatteryAnimationFrame.discharging(percentage: $0)
        }
        let charge = (0...99).map {
            PreviewBatteryAnimationFrame.charging(percentage: $0)
        }
        return drain + charge + [.fullyCharged]
    }()
}
