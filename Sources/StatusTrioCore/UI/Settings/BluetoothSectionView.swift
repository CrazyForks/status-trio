import AppKit
import SwiftUI

/// Settings for Bluetooth audio icon and panel behavior.
struct BluetoothSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage {
            StatusIconPreviewCard(
                store: store,
                statusStore: statusStore,
                isDarkBackground: $previewIsDark
            )

            SettingsGroup(localization.string(.settingsBluetoothTitle)) {
                SettingsToggleRow(
                    symbol: "list.bullet.rectangle",
                    tint: .purple,
                    title: localization.string(.settingsBluetoothShowInStatusPanel),
                    subtitle: localization.string(.settingsBluetoothShowInStatusPanelDescription),
                    isOn: showInStatusPanelBinding
                )

                SettingsDivider()

                SettingsRow(
                    "wave.3.right.circle.fill",
                    tint: .blue,
                    title: localization.string(.settingsBluetoothSymbolScale),
                    subtitle: localization.string(.settingsBluetoothSymbolScaleDescription)
                ) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { store.bluetoothSymbolScale },
                                set: { store.bluetoothSymbolScale = (round($0 * 20) / 20) }
                            ),
                            in: SettingsStore.bluetoothSymbolScaleRange
                        )
                        .frame(width: 130)
                        .controlSize(.small)
                        .accessibilityLabel(localization.string(.settingsBluetoothSymbolScale))
                        .accessibilityValue(
                            "\(Int(round(store.bluetoothSymbolScale * 100)))%"
                        )

                        Text("\(Int(round(store.bluetoothSymbolScale * 100)))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "wave.3.right.circle.fill",
                    tint: .blue,
                    title: localization.string(.settingsBluetoothReplaceNetworkIcon),
                    subtitle: localization.string(.settingsBluetoothReplaceNetworkIconDescription),
                    isOn: $store.replacesNetworkIconWithBluetoothAudio
                )

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "speaker.wave.2.fill",
                    tint: .cyan,
                    title: localization.string(.settingsBluetoothVolumeColor),
                    subtitle: localization.string(.settingsBluetoothVolumeColorDescription),
                    isOn: $store.usesBluetoothAudioVolumeColor
                )

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "wifi.exclamationmark",
                    tint: .orange,
                    title: localization.string(.settingsBluetoothNetworkErrorPriority),
                    subtitle: localization.string(.settingsBluetoothNetworkErrorPriorityDescription),
                    isOn: $store.prioritizesNetworkErrorsOverBluetoothAudio
                )

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "battery.75percent",
                    tint: .green,
                    title: localization.string(.settingsBluetoothBatteryLevels),
                    subtitle: localization.string(.settingsBluetoothBatteryLevelsDescription),
                    isOn: $store.showsBluetoothBatteryLevels
                )
            }
        }
    }

    private var showInStatusPanelBinding: Binding<Bool> {
        Binding(
            get: { store.enabledPopupSections.contains(.bluetooth) },
            set: { enabled in
                let wasEnabled = store.enabledPopupSections.contains(.bluetooth)
                store.setPopupSection(.bluetooth, enabled: enabled)

                guard enabled != wasEnabled else { return }
                if enabled {
                    NSApp.activate()
                }
                statusStore.setBluetoothEnabled(enabled)
            }
        )
    }
}
