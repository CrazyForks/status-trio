import SwiftUI

struct AudioSettingsPane: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        PreferencesPane {
            PreferenceRow(
                label: .settingsAudioMaximumVisible,
                description: .settingsAudioMaximumVisibleDescription
            ) {
                HStack(spacing: 10) {
                    Text("\(store.maxVisibleOutputDevices)")
                        .monospacedDigit()
                        .frame(minWidth: 22, alignment: .trailing)

                    Stepper(
                        localization.string(.settingsAudioMaximumVisible),
                        value: $store.maxVisibleOutputDevices,
                        in: SettingsStore.outputDeviceLimitRange
                    )
                    .labelsHidden()
                    .accessibilityValue("\(store.maxVisibleOutputDevices)")
                }
                .disabled(store.alwaysShowsAllOutputDevices)
            }

            PreferenceCheckboxRow(
                label: .settingsAudioShowAll,
                description: .settingsAudioShowAllDescription,
                isOn: $store.alwaysShowsAllOutputDevices
            )

            Divider()

            outputDeviceOrderSection
        }
        .onAppear {
            statusStore.refreshAll()
        }
    }

    private var outputDeviceOrderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string(.settingsAudioOrderTitle))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(localization.string(.settingsAudioOrderDescription))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if orderedDevices.isEmpty {
                Label(
                    localization.string(.settingsAudioOrderEmpty),
                    systemImage: "questionmark.circle"
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(orderedDevices) { device in
                        outputDeviceRow(device)
                    }
                    .onMove { source, destination in
                        store.moveOutputDevices(
                            fromOffsets: source,
                            toOffset: destination,
                            in: orderedDevices
                        )
                    }
                }
                .listStyle(.inset)
                .frame(height: orderListHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func outputDeviceRow(_ device: AudioOutputDevice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: device.isCurrent ? "hifispeaker.fill" : "hifispeaker")
                .foregroundStyle(device.isCurrent ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            Text(device.name ?? localization.string(.volumeOutputUnknownDevice))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }

    private var orderedDevices: [AudioOutputDevice] {
        store.orderedOutputDevices(statusStore.snapshot.volume.outputDevices)
    }

    private var orderListHeight: CGFloat {
        min(max(CGFloat(orderedDevices.count) * 28 + 8, 44), 168)
    }
}
