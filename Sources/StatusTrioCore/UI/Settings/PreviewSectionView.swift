import SwiftUI

/// Edits the preview-mode status values that replace live data while preview mode is on.
struct PreviewSectionView: View {
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization
    @State private var newOutputName = ""

    var body: some View {
        SettingsPage {
            modeGroup
            batteryGroup
            networkGroup
            volumeGroup
            virtualOutputsGroup
        }
    }

    // MARK: - Groups

    private var modeGroup: some View {
        SettingsGroup {
            SettingsToggleRow(
                symbol: "sparkles",
                tint: .purple,
                title: localization.string(.settingsPreviewEnabled),
                subtitle: localization.string(.settingsPreviewEnabledDescription),
                isOn: Binding(
                    get: { statusStore.isPreviewEnabled },
                    set: { statusStore.setPreviewEnabled($0) }
                )
            )

            SettingsDivider()

            SettingsRow(
                "play.circle",
                tint: .purple,
                title: localization.string(.settingsPreviewBatteryAnimation),
                subtitle: localization.string(.settingsPreviewBatteryAnimationDescription)
            ) {
                Button {
                    statusStore.togglePreviewBatteryAnimation()
                } label: {
                    Label(
                        localization.string(
                            statusStore.isPreviewBatteryAnimationRunning
                                ? .settingsPreviewBatteryAnimationStop
                                : .settingsPreviewBatteryAnimationPlay
                        ),
                        systemImage: statusStore.isPreviewBatteryAnimationRunning
                            ? "stop.fill"
                            : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)
            }
        }
    }

    private var batteryGroup: some View {
        SettingsGroup(localization.string(.settingsPreviewBatterySection)) {
            SettingsRow(
                "battery.100percent",
                tint: .green,
                title: localization.string(.settingsPreviewBatteryPercentage)
            ) {
                percentageControl(
                    value: batteryPercentageBinding,
                    accessibilityLabel: localization.string(.settingsPreviewBatteryPercentage),
                    accessibilityValue: "\(statusStore.previewStatus.batteryPercentage)%",
                    displayText: "\(statusStore.previewStatus.batteryPercentage)%"
                )
            }

            SettingsDivider()

            SettingsToggleRow(
                symbol: "battery.100percent",
                tint: .green,
                title: localization.string(.settingsPreviewBatteryPresent),
                isOn: previewBinding(\.isBatteryPresent)
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "bolt.fill",
                tint: .yellow,
                title: localization.string(.settingsPreviewBatteryCharging),
                isOn: previewBinding(\.isCharging)
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "checkmark.circle.fill",
                tint: .green,
                title: localization.string(.settingsPreviewBatteryCharged),
                isOn: previewBinding(\.isCharged)
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "leaf.fill",
                tint: .teal,
                title: localization.string(.settingsPreviewBatteryLowPowerMode),
                isOn: previewBinding(\.isLowPowerMode)
            )

            SettingsDivider()

            SettingsToggleRow(
                symbol: "powerplug.fill",
                tint: .orange,
                title: localization.string(.settingsPreviewBatteryConnectedToPower),
                isOn: previewBinding(\.isConnectedToPower)
            )
        }
        .disabled(!statusStore.isPreviewEnabled)
        .opacity(statusStore.isPreviewEnabled ? 1 : 0.55)
    }

    private var networkGroup: some View {
        SettingsGroup(localization.string(.settingsPreviewWiFiSection)) {
            SettingsToggleRow(
                symbol: "cable.connector",
                tint: .blue,
                title: localization.string(.ethernetAccessibilityConnected),
                isOn: previewBinding(\.isWiredConnection)
            )

            SettingsDivider()

            SettingsRow(
                "wifi",
                tint: .blue,
                title: localization.string(.settingsPreviewWiFiState)
            ) {
                Picker("", selection: previewBinding(\.wifiState)) {
                    ForEach(WiFiState.allCases, id: \.self) { state in
                        Text(wifiStateTitle(state)).tag(state)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            SettingsDivider()

            SettingsRow(
                "wifi",
                tint: .blue,
                title: localization.string(.settingsPreviewWiFiSignal)
            ) {
                percentageControl(
                    value: wifiSignalBinding,
                    range: -100...(-40),
                    accessibilityLabel: localization.string(.settingsPreviewWiFiSignal),
                    accessibilityValue: "\(statusStore.previewStatus.wifiRSSI) dBm",
                    displayText: "\(statusStore.previewStatus.wifiRSSI) dBm",
                    textWidth: 72
                )
            }

            SettingsDivider()

            SettingsRow(
                "network",
                tint: .blue,
                title: localization.string(.settingsPreviewWiFiSSID)
            ) {
                TextField(
                    localization.string(.settingsPreviewWiFiSSIDPlaceholder),
                    text: previewBinding(\.wifiSSID)
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
            }
        }
        .disabled(!statusStore.isPreviewEnabled)
        .opacity(statusStore.isPreviewEnabled ? 1 : 0.55)
    }

    private var volumeGroup: some View {
        SettingsGroup(localization.string(.settingsPreviewVolumeSection)) {
            SettingsRow(
                "speaker.wave.2.fill",
                tint: .cyan,
                title: localization.string(.settingsPreviewVolumeLevel)
            ) {
                percentageControl(
                    value: volumeBinding,
                    accessibilityLabel: localization.string(.settingsPreviewVolumeLevel),
                    accessibilityValue: "\(volumePercentage)%",
                    displayText: "\(volumePercentage)%"
                )
            }

            SettingsDivider()

            SettingsToggleRow(
                symbol: "speaker.slash.fill",
                tint: .gray,
                title: localization.string(.settingsPreviewVolumeMuted),
                isOn: previewBinding(\.isMuted)
            )
        }
        .disabled(!statusStore.isPreviewEnabled)
        .opacity(statusStore.isPreviewEnabled ? 1 : 0.55)
    }

    private var virtualOutputsGroup: some View {
        SettingsGroup(
            localization.string(.settingsPreviewVirtualOutputsSection),
            footnote: localization.string(.settingsPreviewVirtualOutputsAdd)
        ) {
            SettingsCustomRow(title: localization.string(.settingsPreviewVirtualOutputsSection)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField(
                            localization.string(.settingsPreviewVirtualOutputsNamePlaceholder),
                            text: $newOutputName
                        )
                        .textFieldStyle(.roundedBorder)

                        Button(localization.string(.settingsPreviewVirtualOutputsAdd)) {
                            statusStore.addPreviewOutputDevice(named: newOutputName)
                            newOutputName = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    ForEach(statusStore.previewStatus.virtualOutputDevices) { device in
                        virtualOutputRow(device)
                    }
                }
            }
        }
        .disabled(!statusStore.isPreviewEnabled)
        .opacity(statusStore.isPreviewEnabled ? 1 : 0.55)
    }

    // MARK: - Rows

    private func virtualOutputRow(_ device: PreviewVirtualOutputDevice) -> some View {
        let isSelected = device.id == statusStore.previewStatus.selectedVirtualOutputDeviceID

        return HStack(spacing: 8) {
            Button {
                statusStore.selectPreviewOutputDevice(id: device.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(
                isSelected
                    ? localization.string(.volumeOutputCurrent)
                    : localization.format(.volumeOutputSwitchTo, device.name)
            )

            TextField(
                localization.string(.settingsPreviewVirtualOutputsNamePlaceholder),
                text: Binding(
                    get: { device.name },
                    set: { statusStore.renamePreviewOutputDevice(id: device.id, name: $0) }
                )
            )
            .textFieldStyle(.plain)

            Button {
                statusStore.removePreviewOutputDevice(id: device.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(localization.string(.settingsPreviewVirtualOutputsRemove))
        }
        .padding(.vertical, 1)
    }

    private func percentageControl(
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...100,
        accessibilityLabel: String,
        accessibilityValue: String,
        displayText: String,
        textWidth: CGFloat = 48
    ) -> some View {
        HStack(spacing: 8) {
            Slider(value: value, in: range, step: 1)
                .frame(width: 170)
                .controlSize(.small)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)

            Text(displayText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: textWidth, alignment: .trailing)
        }
    }

    // MARK: - Bindings

    private var volumePercentage: Int {
        Int((min(1, max(0, statusStore.previewStatus.volumeScalar)) * 100).rounded())
    }

    private var batteryPercentageBinding: Binding<Double> {
        Binding(
            get: { Double(statusStore.previewStatus.batteryPercentage) },
            set: { statusStore.updatePreview(\.batteryPercentage, to: Int($0.rounded())) }
        )
    }

    private var wifiSignalBinding: Binding<Double> {
        Binding(
            get: { Double(statusStore.previewStatus.wifiRSSI) },
            set: { statusStore.updatePreview(\.wifiRSSI, to: Int($0.rounded())) }
        )
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { statusStore.previewStatus.volumeScalar * 100 },
            set: { statusStore.updatePreview(\.volumeScalar, to: $0 / 100) }
        )
    }

    private func previewBinding<Value>(
        _ keyPath: WritableKeyPath<PreviewStatusConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { statusStore.previewStatus[keyPath: keyPath] },
            set: { statusStore.updatePreview(keyPath, to: $0) }
        )
    }

    private func wifiStateTitle(_ state: WiFiState) -> String {
        switch state {
        case .connected:
            localization.string(.wifiSubtitleConnected)
        case .notAssociated:
            localization.string(.wifiValueNotAssociated)
        case .off:
            localization.string(.wifiValueOff)
        case .noInternet:
            localization.string(.wifiValueNoInternet)
        case .hotspot:
            localization.string(.wifiValueHotspot)
        case .temporary:
            localization.string(.wifiValueTemporary)
        case .shared:
            localization.string(.wifiValueShared)
        case .unavailable:
            localization.string(.wifiValueUnavailable)
        }
    }
}
