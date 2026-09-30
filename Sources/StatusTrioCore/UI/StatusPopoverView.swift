import SwiftUI

private enum PopoverPanel {
    case summary
    case battery
    case wifi(showDetails: Bool)
    case ethernet
}

struct StatusPopoverView: View {
    @ObservedObject var store: SystemStatusStore
    @ObservedObject var settings: SettingsStore
    let scrollTargets: PopoverScrollTargets
    @EnvironmentObject private var localization: Localization
    let requestWiFiNameAccess: () -> Void
    let requestBluetoothAuthorization: () -> Void
    let openBatterySettings: () -> Void
    let openWiFiSettings: () -> Void
    let openNetworkSettings: () -> Void
    let openLocationSettings: () -> Void
    let openBluetoothSettings: () -> Void
    let openBluetoothPermissionSettings: () -> Void
    let openSettings: () -> Void
    let openSoundSettings: () -> Void
    let quit: () -> Void
    @State private var panel: PopoverPanel = .summary

    var body: some View {
        Group {
            switch panel {
            case .summary:
                summary
            case .battery:
                BatteryDetailsView(
                    controller: store.batteryDetails,
                    battery: store.popupSnapshot.battery,
                    onBack: {
                        store.closeBatteryDetails()
                        panel = .summary
                    },
                    onOpenBatterySettings: openBatterySettings
                )
            case .wifi(let showDetails):
                WiFiNetworkListView(
                    controller: store.wifiNetworks,
                    wifi: store.popupSnapshot.wifi,
                    onBack: {
                        store.closeWiFiDetails()
                        panel = .summary
                    },
                    onRequestNameAccess: requestWiFiNameAccess,
                    onOpenWiFiSettings: openWiFiSettings,
                    onOpenLocationSettings: openLocationSettings,
                    showsDetailsInitially: showDetails
                )
            case .ethernet:
                EthernetLinkView(
                    primaryLink: store.primaryLink,
                    onBack: {
                        store.closePrimaryLinkPanel()
                        panel = .summary
                    },
                    onOpenNetworkSettings: openNetworkSettings
                )
            }
        }
        .padding(14)
        .frame(width: 330)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(settings.visiblePopupSections) { section in
                popupSection(section)

                if section != settings.visiblePopupSections.last {
                    Divider()
                }
            }

            if !settings.visiblePopupSections.isEmpty {
                Divider()
                    .opacity(0.6)
                    .padding(.vertical, 2)
            }

            PopoverFooterView(openSettings: openSettings, quit: quit)
        }
    }

    @ViewBuilder
    private func popupSection(_ section: PopupSection) -> some View {
        switch section {
        case .battery:
            BatteryStatusView(
                battery: store.popupSnapshot.battery,
                onOpenBatteryDetails: { panel = .battery },
                onOpenBatterySettings: openBatterySettings
            )
        case .network:
            NetworkStatusView(
                primaryLink: store.primaryLink,
                connection: store.popupSnapshot.connection,
                isConstrained: store.isNetworkConstrained,
                wifi: store.popupSnapshot.wifi,
                isResolvingName: store.isResolvingWiFiName,
                onOpenWiFiDetails: { showDetails in
                    store.activateWiFiPanel()
                    panel = .wifi(showDetails: showDetails)
                },
                onOpenWiredDetails: {
                    store.activatePrimaryLinkPanel()
                    panel = .ethernet
                },
                onRequestNameAccess: requestWiFiNameAccess,
                onOpenWiFiSettings: openWiFiSettings,
                onOpenNetworkSettings: openNetworkSettings,
                onOpenLocationSettings: openLocationSettings
            )
        case .vpn:
            VPNStatusView(vpn: store.vpnStatus)
        case .bluetooth:
            BluetoothStatusView(
                controller: store.bluetoothDevices,
                showsBatteryLevels: settings.showsBluetoothBatteryLevels,
                showsNearbyBatteryDevices: settings.showsNearbyBluetoothBatteryDevices,
                listOptions: settings.bluetoothDeviceListOptions,
                onRequestAuthorization: requestBluetoothAuthorization,
                onOpenBluetoothSettings: openBluetoothSettings,
                onOpenBluetoothPermissionSettings: openBluetoothPermissionSettings
            )
        case .volume:
            VolumeControlsView(
                settings: settings,
                bluetoothController: store.bluetoothDevices,
                listeningModes: store.bluetoothListeningModes,
                scrollTargets: scrollTargets,
                volume: store.liveVolume,
                isControllerAvailable: store.isVolumeControllerAvailable,
                onVolumeChange: { store.setVolume($0) },
                onVolumeEditingEnded: { store.finishVolumeAdjustment() },
                onToggleMute: { store.toggleMute() },
                onSelectOutputDevice: { store.selectOutputDevice($0) },
                onOpenSoundSettings: openSoundSettings
            )
        case .audioInput:
            AudioInputControlsView(
                status: store.liveInput,
                onSelect: { store.selectInputDevice($0) },
                onScalarChange: { store.setInputScalar($0) },
                onToggleMute: { store.toggleInputMute() },
                onOpenSoundSettings: openSoundSettings
            )
        }
    }
}
