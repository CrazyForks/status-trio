import SwiftUI

@MainActor
enum StatusPresentation {
    static let statusItemAccessibilityLabel = "Status Trio"

    static func statusItemAccessibilityValue(
        _ snapshot: StatusSnapshot,
        localization: Localization
    ) -> String {
        let battery = snapshot.battery
        let batterySummary: String
        if battery.isPresent {
            let percentage = localization.format(
                .batteryAccessibilityValue,
                battery.percentage
            )
            let subtitle = batterySubtitle(battery, localization: localization)
            if isOrdinaryBatteryState(battery) {
                batterySummary = percentage
            } else {
                batterySummary = localization.format(
                    .commonParenthetical,
                    percentage,
                    subtitle
                )
            }
        } else {
            batterySummary = localization.string(.batteryStateNotPresent)
        }

        let wifiSummary = wifiAccessibilitySummary(
            snapshot.wifi,
            localization: localization
        )
        let volumeSummary = localization.format(
            .accessibilityVolume,
            volumeValue(snapshot.volume, localization: localization)
        )

        return localization.format(
            .accessibilityStatus,
            batterySummary,
            wifiSummary,
            volumeSummary
        )
    }

    static func batteryTitle(
        _ battery: BatteryStatus,
        localization: Localization
    ) -> String {
        localization.format(.batteryTitle, battery.percentage)
    }

    static func batteryTimeToFullText(
        minutes: Int?,
        localization: Localization
    ) -> String {
        guard let minutes, minutes > 0 else {
            return localization.string(.batteryStateCalculatingTimeToFull)
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours == 0 {
            return localization.format(
                .batteryTimeToFullMinutes,
                remainingMinutes
            )
        }
        if remainingMinutes == 0 {
            return localization.format(.batteryTimeToFullHours, hours)
        }
        return localization.format(
            .batteryTimeToFullHoursMinutes,
            hours,
            remainingMinutes
        )
    }

    static func batterySubtitle(
        _ battery: BatteryStatus,
        localization: Localization
    ) -> String {
        if !battery.isPresent {
            return localization.string(.batteryStateNotPresent)
        }
        if battery.isCharged {
            return localization.string(.batteryStateCharged)
        }
        if battery.isCharging {
            return batteryTimeToFullText(
                minutes: battery.timeToFullChargeMinutes,
                localization: localization
            )
        }
        if battery.isLowPowerMode {
            return localization.string(.batteryStateLowPowerMode)
        }
        if battery.isConnectedToPower {
            return localization.string(.batteryStateConnectedToPower)
        }
        return localization.string(.batteryStateOnBattery)
    }

    static func wifiValue(
        _ wifi: WiFiStatus,
        localization: Localization
    ) -> String {
        switch wifi.state {
        case .connected:
            return localization.format(
                .wifiValueBars,
                StatusMappings.wifiBars(rssi: wifi.rssi)
            )
        case .notAssociated:
            return localization.string(.wifiValueNotAssociated)
        case .off:
            return localization.string(.wifiValueOff)
        case .noInternet:
            return localization.string(.wifiValueNoInternet)
        case .hotspot:
            return localization.string(.wifiValueHotspot)
        case .temporary:
            return localization.string(.wifiValueTemporary)
        case .shared:
            return localization.string(.wifiValueShared)
        case .unavailable:
            return localization.string(.wifiValueUnavailable)
        }
    }

    static func wifiSubtitle(
        _ wifi: WiFiStatus,
        localization: Localization
    ) -> String {
        if let ssid = wifi.ssid, !ssid.isEmpty {
            return ssid
        }

        switch wifi.state {
        case .connected:
            return localization.string(.wifiSubtitleConnected)
        case .notAssociated:
            return localization.string(.wifiSubtitleNotAssociated)
        case .off:
            return localization.string(.wifiSubtitleOff)
        case .noInternet:
            return localization.string(.wifiSubtitleNoInternet)
        case .hotspot:
            return localization.string(.wifiSubtitleHotspot)
        case .temporary:
            return localization.string(.wifiSubtitleTemporary)
        case .shared:
            return localization.string(.wifiSubtitleShared)
        case .unavailable:
            return localization.string(.wifiSubtitleUnavailable)
        }
    }

    static func volumeTitle(
        _ volume: VolumeStatus,
        localization: Localization
    ) -> String {
        guard let scalar = volume.scalar, scalar.isFinite else {
            return localization.string(.volumeTitleUnavailable)
        }
        let percentage = Int((min(1, max(0, scalar)) * 100).rounded())
        return localization.format(.volumeTitle, percentage)
    }

    static func volumeValue(
        _ volume: VolumeStatus,
        localization: Localization
    ) -> String {
        guard let scalar = volume.scalar, scalar.isFinite else { return "—" }
        let clampedScalar = min(1, max(0, scalar))
        let percentage = Int((clampedScalar * 100).rounded())
        if volume.isMuted {
            return localization.string(.volumeMuted)
        }
        let steps = StatusMappings.volumeSteps(
            scalar: clampedScalar,
            isMuted: volume.isMuted
        ) ?? 0
        return localization.format(.volumeValue, percentage, steps)
    }

    static func volumeSubtitle(
        _ volume: VolumeStatus,
        localization: Localization
    ) -> String {
        volume.deviceName ?? localization.string(.volumeNoDefaultDevice)
    }

    private static func wifiAccessibilitySummary(
        _ wifi: WiFiStatus,
        localization: Localization
    ) -> String {
        let value = wifiValue(wifi, localization: localization)
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

struct StatusPopoverView: View {
    @ObservedObject var store: SystemStatusStore
    @EnvironmentObject private var localization: Localization
    let requestWiFiNameAccess: () -> Void
    let openBatterySettings: () -> Void
    let openWiFiSettings: () -> Void
    let openLocationSettings: () -> Void
    let openSettings: () -> Void
    let openSoundSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BatteryStatusView(
                battery: store.popupSnapshot.battery,
                onOpenBatterySettings: openBatterySettings
            )
            Divider()
            WiFiStatusView(
                wifi: store.popupSnapshot.wifi,
                onRequestNameAccess: requestWiFiNameAccess,
                onOpenWiFiSettings: openWiFiSettings,
                onOpenLocationSettings: openLocationSettings
            )
            Divider()
            VolumeControlsView(
                volume: store.liveVolume,
                isEnabled: store.isVolumeControlAvailable,
                onVolumeChange: store.setVolume,
                onToggleMute: store.toggleMute,
                onSelectOutputDevice: store.selectOutputDevice,
                onOpenSoundSettings: openSoundSettings
            )

            Divider()

            Button(localization.string(.menuSettings)) {
                openSettings()
            }
            .buttonStyle(.plain)

            Button(localization.string(.menuQuit)) {
                quit()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 300)
    }
}
