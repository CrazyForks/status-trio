import Foundation

/// One power row: its label, value and timestamp must all refer to the same source.
struct BatteryPowerPresentation {
    let title: LocalizationKey
    let watts: Double?
    let timestamp: Date?
    let timestampTitle: LocalizationKey
    let unavailableTitle: LocalizationKey

    init(details: BatteryDetails, isConnectedToPower: Bool) {
        if isConnectedToPower {
            title = .batteryDetailsSystemPower
            watts = details.systemPower?.watts
            timestamp = details.systemPower?.readAt
            timestampTitle = .batteryDetailsSystemReadAt
            unavailableTitle = .batteryDetailsUnavailable
        } else {
            // The view can see a power-source change before its appearance
            // task clears the preceding sample. Never relabel charging as discharge.
            let discharge = details.power.flatMap { $0.watts < 0 ? $0 : nil }
            title = .batteryDetailsDischarging
            watts = discharge.map { -$0.watts }
            timestamp = discharge?.updatedAt
            timestampTitle = .batteryDetailsSampled
            unavailableTitle = details.powerAvailability == .collecting || details.power != nil
                ? .batteryDetailsCollecting : .batteryDetailsUnavailable
        }
    }
}
