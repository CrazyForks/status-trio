import SwiftUI

struct PreviewSettingsPane: View {
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization
    @State private var newOutputName = ""

    var body: some View {
        PreferencesPane {
            PreferenceCheckboxRow(
                label: .settingsPreviewEnabled,
                description: .settingsPreviewEnabledDescription,
                isOn: Binding(
                    get: { statusStore.isPreviewEnabled },
                    set: statusStore.setPreviewEnabled
                )
            )

            PreferenceRow(
                label: .settingsPreviewBatteryAnimation,
                description: .settingsPreviewBatteryAnimationDescription
            ) {
                Button(
                    localization.string(
                        statusStore.isPreviewBatteryAnimationRunning
                            ? .settingsPreviewBatteryAnimationStop
                            : .settingsPreviewBatteryAnimationPlay
                    ),
                    systemImage: statusStore.isPreviewBatteryAnimationRunning
                        ? "stop.fill"
                        : "play.fill",
                    action: statusStore.togglePreviewBatteryAnimation
                )
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                sectionTitle(.settingsPreviewBatterySection)

                PreferenceRow(label: .settingsPreviewBatteryPercentage) {
                    HStack(spacing: 12) {
                        Slider(
                            value: batteryPercentageBinding,
                            in: 0...100,
                            step: 1
                        )
                        .accessibilityLabel(
                            localization.string(.settingsPreviewBatteryPercentage)
                        )
                        .accessibilityValue("\(statusStore.previewStatus.batteryPercentage)%")

                        Text("\(statusStore.previewStatus.batteryPercentage)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                PreferenceCheckboxRow(
                    label: .settingsPreviewBatteryPresent,
                    isOn: previewBinding(\.isBatteryPresent)
                )
                PreferenceCheckboxRow(
                    label: .settingsPreviewBatteryCharging,
                    isOn: previewBinding(\.isCharging)
                )
                PreferenceCheckboxRow(
                    label: .settingsPreviewBatteryCharged,
                    isOn: previewBinding(\.isCharged)
                )
                PreferenceCheckboxRow(
                    label: .settingsPreviewBatteryLowPowerMode,
                    isOn: previewBinding(\.isLowPowerMode)
                )
                PreferenceCheckboxRow(
                    label: .settingsPreviewBatteryConnectedToPower,
                    isOn: previewBinding(\.isConnectedToPower)
                )
            }
            .disabled(!statusStore.isPreviewEnabled)
            .opacity(statusStore.isPreviewEnabled ? 1 : 0.55)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                sectionTitle(.settingsPreviewWiFiSection)

                PreferenceRow(
                    label: .settingsPreviewWiFiState,
                    placesControlInline: true
                ) {
                    Picker("", selection: previewBinding(\.wifiState)) {
                        ForEach(WiFiState.allCases, id: \.self) { state in
                            Text(wifiStateTitle(state))
                                .tag(state)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                PreferenceRow(label: .settingsPreviewWiFiSignal) {
                    HStack(spacing: 12) {
                        Slider(
                            value: wifiSignalBinding,
                            in: -100...(-40),
                            step: 1
                        )
                        .accessibilityLabel(
                            localization.string(.settingsPreviewWiFiSignal)
                        )
                        .accessibilityValue("\(statusStore.previewStatus.wifiRSSI) dBm")

                        Text("\(statusStore.previewStatus.wifiRSSI) dBm")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                    }
                }

                PreferenceRow(label: .settingsPreviewWiFiSSID) {
                    TextField(
                        localization.string(.settingsPreviewWiFiSSIDPlaceholder),
                        text: previewBinding(\.wifiSSID)
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }
            .disabled(!statusStore.isPreviewEnabled)
            .opacity(statusStore.isPreviewEnabled ? 1 : 0.55)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                sectionTitle(.settingsPreviewVolumeSection)

                PreferenceRow(label: .settingsPreviewVolumeLevel) {
                    HStack(spacing: 12) {
                        Slider(
                            value: volumeBinding,
                            in: 0...100,
                            step: 1
                        )
                        .accessibilityLabel(
                            localization.string(.settingsPreviewVolumeLevel)
                        )
                        .accessibilityValue("\(volumePercentage)%")

                        Text("\(volumePercentage)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                PreferenceCheckboxRow(
                    label: .settingsPreviewVolumeMuted,
                    isOn: previewBinding(\.isMuted)
                )
            }
            .disabled(!statusStore.isPreviewEnabled)
            .opacity(statusStore.isPreviewEnabled ? 1 : 0.55)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(.settingsPreviewVirtualOutputsSection)

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
                }

                ForEach(statusStore.previewStatus.virtualOutputDevices) { device in
                    HStack(spacing: 8) {
                        Button {
                            statusStore.selectPreviewOutputDevice(id: device.id)
                        } label: {
                            Image(
                                systemName: device.id == statusStore.previewStatus.selectedVirtualOutputDeviceID
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .foregroundStyle(
                                device.id == statusStore.previewStatus.selectedVirtualOutputDeviceID
                                    ? Color.accentColor
                                    : Color.secondary
                            )
                        }
                        .buttonStyle(.plain)
                        .help(
                            device.id == statusStore.previewStatus.selectedVirtualOutputDeviceID
                                ? localization.string(.volumeOutputCurrent)
                                : localization.format(.volumeOutputSwitchTo, device.name)
                        )

                        TextField(
                            localization.string(.settingsPreviewVirtualOutputsNamePlaceholder),
                            text: Binding(
                                get: { device.name },
                                set: {
                                    statusStore.renamePreviewOutputDevice(
                                        id: device.id,
                                        name: $0
                                    )
                                }
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
                    .padding(.vertical, 2)
                }
            }
            .disabled(!statusStore.isPreviewEnabled)
            .opacity(statusStore.isPreviewEnabled ? 1 : 0.55)
        }
    }

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

    private func sectionTitle(_ key: LocalizationKey) -> some View {
        Text(localization.string(key))
            .font(.headline)
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
