import AppKit
import SwiftUI

struct MenuBarSettingsPane: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        PreferencesPane {
            PreferenceRow(label: .settingsIconSize) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Slider(
                            value: $store.iconSize,
                            in: SettingsStore.iconSizeRange,
                            step: 1
                        )
                        .accessibilityLabel(localization.string(.settingsIconSize))
                        .accessibilityValue(
                            localization.format(
                                .settingsIconSizeAccessibilityValue,
                                Int(store.iconSize)
                            )
                        )

                        Text("\(Int(store.iconSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }

                    HStack(alignment: .center, spacing: 14) {
                        IconSizePreview(
                            size: store.iconSize,
                            options: store.batteryIconOptions
                        )

                        Text(localization.string(.settingsIconSizeDescription))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()

            PreferenceRow(
                label: .settingsMenuBarConnectionIcons,
                description: .settingsMenuBarConnectionIconsDescription
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    PreferenceCheckboxRow(
                        label: .settingsMenuBarWiFiIconForEthernet,
                        isOn: $store.showsWiFiIconForEthernet
                    )

                    PreferenceCheckboxRow(
                        label: .settingsMenuBarWiFiIconForHotspot,
                        isOn: $store.showsWiFiIconForHotspot
                    )

                    PreferenceCheckboxRow(
                        label: .settingsMenuBarWiFiIconForTemporaryConnection,
                        isOn: $store.showsWiFiIconForTemporaryConnection
                    )

                    PreferenceCheckboxRow(
                        label: .settingsMenuBarWiFiIconForInternetSharing,
                        isOn: $store.showsWiFiIconForInternetSharing
                    )
                }
            }
        }
    }
}
