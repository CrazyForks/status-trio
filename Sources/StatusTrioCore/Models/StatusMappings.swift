import Foundation

enum BatteryColorRole: Equatable, Sendable {
    case foreground
    case critical
    case lowPower
    case charging
}

/// The glyph that fills the battery arc's top gap.
enum BatteryTopIndicator: Equatable, Sendable {
    /// Charging: the lightning bolt.
    case bolt
    /// Connected to power without charging: the plug.
    case plug
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
    /// charging — including a battery that is already full — shows the plug
    /// when the option is enabled, and falls back to the bolt when it is not.
    static func batteryTopIndicator(
        _ battery: BatteryStatus,
        options: BatteryIconOptions
    ) -> BatteryTopIndicator? {
        guard battery.isPresent, options.showsChargingIndicator else { return nil }
        if battery.isCharging { return .bolt }
        guard battery.isConnectedToPower else { return nil }
        return options.showsPlugForConnectedPower ? .plug : .bolt
    }

    static func batteryProgress(_ battery: BatteryStatus) -> Double {
        Double(battery.percentage) / 100.0
    }
}
