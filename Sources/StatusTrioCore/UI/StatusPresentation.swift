import Foundation

/// Temporary compatibility surface for summary views that have not yet
/// migrated to `PanelSummaryState`.
@MainActor
enum StatusPresentation {
    static func batteryTitle(_ battery: BatteryStatus, localization: Localization) -> String {
        PanelPresentationMapper.batteryTitle(battery, localization: localization)
    }

    static func batteryTimeToFullText(minutes: Int?, localization: Localization) -> String {
        PanelPresentationMapper.batteryTimeToFullText(minutes: minutes, localization: localization)
    }

    static func batterySubtitle(_ battery: BatteryStatus, localization: Localization) -> String {
        PanelPresentationMapper.batterySubtitle(battery, localization: localization)
    }

    static func wifiValue(_ wifi: WiFiStatus, localization: Localization) -> String {
        PanelPresentationMapper.wifiValue(wifi, localization: localization)
    }

    static func wifiSubtitle(_ wifi: WiFiStatus, localization: Localization) -> String {
        PanelPresentationMapper.wifiSubtitle(wifi, localization: localization)
    }

    static func volumeTitle(_ volume: VolumeStatus, localization: Localization) -> String {
        volumeTitle(MenuBarVolumeStatus(volume: volume), localization: localization)
    }

    static func volumeTitle(_ volume: MenuBarVolumeStatus, localization: Localization) -> String {
        guard let scalar = volume.scalar, scalar.isFinite else {
            return localization.string(.volumeTitleUnavailable)
        }
        let percentage = Int((min(1, max(0, scalar)) * 100).rounded())
        return localization.format(.volumeTitle, percentage)
    }

    static func volumeValue(_ volume: VolumeStatus, localization: Localization) -> String {
        volumeValue(MenuBarVolumeStatus(volume: volume), localization: localization)
    }

    static func volumeValue(_ volume: MenuBarVolumeStatus, localization: Localization) -> String {
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

    static func volumeSubtitle(_ volume: VolumeStatus, localization: Localization) -> String {
        volume.deviceName ?? localization.string(.volumeNoDefaultDevice)
    }

    static func vpnTitle(_ vpn: VPNStatus, localization: Localization) -> String {
        PanelPresentationMapper.vpnTitle(vpn, localization: localization)
    }

    static func vpnSubtitle(_ vpn: VPNStatus, localization: Localization) -> String {
        PanelPresentationMapper.vpnSubtitle(vpn, localization: localization)
    }
}
