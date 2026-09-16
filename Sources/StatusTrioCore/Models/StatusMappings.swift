import Foundation

enum BatteryColorRole: Equatable, Sendable {
    case foreground
    case critical
    case lowPower
    case charging
}

/// What fills the battery arc's top gap.
enum BatteryGapContent: Equatable, Sendable {
    /// Charging: the lightning bolt.
    case bolt
    /// Connected to power without charging: the plug.
    case plug
    /// The percentage numerals.
    case percentage
    /// Nothing: the arc closes into a full circle.
    case empty
}

enum WiFiSummaryAction: Equatable, Sendable {
    case openDetails
    case requestNameAccess
    case openLocationSettings
}

enum StatusMappings {
    static func wifiBars(rssi: Int?) -> Int {
        guard let rssi else { return 0 }
        switch rssi {
        // Parentheses are required for this negative partial range in Swift 6.
        case (-60)...:
            return 3
        case -78 ... -61:
            return 2
        case -88 ... -79:
            return 1
        default:
            return 0
        }
    }

    static func wifiSummaryAction(for wifi: WiFiStatus) -> WiFiSummaryAction {
        guard wifi.state.isNetworkAssociated else { return .openDetails }

        switch wifi.nameAccess {
        case .authorized:
            return .openDetails
        case .notDetermined:
            return .requestNameAccess
        case .denied, .restricted:
            return .openLocationSettings
        }
    }

    static func volumeSteps(scalar: Double?, isMuted: Bool) -> Int? {
        guard let scalar else { return nil }
        let clamped = min(1, max(0, scalar))
        if isMuted || clamped == 0 { return 0 }
        if clamped <= 0.25 { return 1 }
        if clamped <= 0.50 { return 2 }
        if clamped <= 0.75 { return 3 }
        return 4
    }

    static func batteryColorRole(
        _ battery: BatteryStatus,
        criticalThreshold: Int = 20
    ) -> BatteryColorRole {
        let threshold = min(100, max(0, criticalThreshold))
        if battery.percentage < threshold { return .critical }
        if battery.isLowPowerMode { return .lowPower }
        if battery.isCharging || battery.isConnectedToPower { return .charging }
        return .foreground
    }

    /// A charging battery keeps the bolt. A connected power source that is not
    /// charging — including a battery that is already full — shows the plug,
    /// or the percentage when the user asked for the number in that state and
    /// the percentage is available at all.
    static func batteryGapContent(
        _ battery: BatteryStatus,
        options: BatteryIconOptions
    ) -> BatteryGapContent {
        if battery.isPresent, options.showsChargingIndicator {
            if battery.isCharging { return .bolt }
            let showsPercentageForPower = options.showsPercentageWhenConnected
                && options.showsPercentage
            if battery.isConnectedToPower, !showsPercentageForPower {
                return .plug
            }
        }

        return options.showsPercentage ? .percentage : .empty
    }

    static func batteryProgress(_ battery: BatteryStatus) -> Double {
        Double(battery.percentage) / 100.0
    }
}
