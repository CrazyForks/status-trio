import Foundation

@MainActor
enum AccessibilityPresentation {
    static let statusItemLabel = "Status Trio"

    static func statusItemValue(
        _ snapshot: StatusSnapshot,
        localization: Localization
    ) -> String {
        let battery = snapshot.battery
        let batterySummary: String
        if battery.isPresent {
            let percentage = localization.format(.batteryAccessibilityValue, battery.percentage)
            let subtitle = StatusPresentation.batterySubtitle(battery, localization: localization)
            if isOrdinaryBatteryState(battery) {
                batterySummary = percentage
            } else {
                batterySummary = localization.format(.commonParenthetical, percentage, subtitle)
            }
        } else {
            batterySummary = localization.string(.batteryStateNotPresent)
        }

        let networkSummary = snapshot.connection == .ethernet
            ? localization.string(.ethernetAccessibilityConnected)
            : wifiAccessibilitySummary(snapshot.wifi, localization: localization)
        let volumeSummary = localization.format(
            .accessibilityVolume,
            StatusPresentation.volumeValue(snapshot.volume, localization: localization)
        )

        return localization.format(.accessibilityStatus, batterySummary, networkSummary, volumeSummary)
    }

    private static func wifiAccessibilitySummary(
        _ wifi: WiFiStatus,
        localization: Localization
    ) -> String {
        let value = StatusPresentation.wifiValue(wifi, localization: localization)
        if let ssid = wifi.ssid, !ssid.isEmpty {
            return localization.format(.wifiAccessibilityWithSSID, ssid, value)
        }
        return localization.format(
            .commonLabelValue,
            localization.string(.wifiTitle),
            value
        )
    }

    private static func isOrdinaryBatteryState(_ battery: BatteryStatus) -> Bool {
        battery.isPresent
            && !battery.isCharged
            && !battery.isCharging
            && !battery.isLowPowerMode
            && !battery.isConnectedToPower
    }
}
