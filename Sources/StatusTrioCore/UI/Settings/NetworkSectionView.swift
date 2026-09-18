import SwiftUI

/// Settings for how the network indicator is drawn in the status icon.
struct NetworkSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    @EnvironmentObject private var localization: Localization

    @State private var showsNetworkIconOptions: Bool = false

    var body: some View {
        SettingsPage(pinnedHeader: {
            StatusIconPreviewCard(
                store: store,
                statusStore: statusStore,
                isDarkBackground: $previewIsDark
            )
        }) {
            connectionIconsGroup
        }
    }

    private var connectionIconsGroup: some View {
        SettingsGroup(localization.string(.settingsNetworkConnectionIcons)) {
            SettingsRow(
                "wifi",
                tint: .blue,
                title: localization.string(.settingsWiFiSymbolScale),
                subtitle: localization.string(.settingsWiFiSymbolScaleDescription)
            ) {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { store.wifiSymbolScale },
                            set: { store.wifiSymbolScale = (round($0 * 20) / 20) }
                        ),
                        in: SettingsStore.wifiSymbolScaleRange
                    )
                    .frame(width: 130)
                    .controlSize(.small)
                    .accessibilityLabel(localization.string(.settingsWiFiSymbolScale))
                    .accessibilityValue("\(Int(round(store.wifiSymbolScale * 100)))%")

                    Text("\(Int(round(store.wifiSymbolScale * 100)))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }

            SettingsDivider()

            SettingsDisclosureRow(
                "cable.connector",
                tint: .teal,
                title: localization.string(.settingsNetworkConnectionIcons),
                subtitle: localization.string(.settingsNetworkConnectionIconsDescription),
                isExpanded: $showsNetworkIconOptions
            )

            if showsNetworkIconOptions {
                VStack(spacing: 0) {
                    SettingsDivider()

                    SettingsToggleRow(
                        symbol: "cable.connector",
                        tint: .teal,
                        title: localization.string(.settingsNetworkWiFiIconForEthernet),
                        isOn: $store.showsWiFiIconForEthernet
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        symbol: "personalhotspot",
                        tint: .blue,
                        title: localization.string(.settingsNetworkWiFiIconForHotspot),
                        isOn: $store.showsWiFiIconForHotspot
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        symbol: "network",
                        tint: .purple,
                        title: localization.string(.settingsNetworkWiFiIconForTemporaryConnection),
                        isOn: $store.showsWiFiIconForTemporaryConnection
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        symbol: "antenna.radiowaves.left.and.right",
                        tint: .indigo,
                        title: localization.string(.settingsNetworkWiFiIconForInternetSharing),
                        isOn: $store.showsWiFiIconForInternetSharing
                    )
                }
            }
        }
    }
}
