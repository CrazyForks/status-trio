import SwiftUI

struct VolumeControlsView: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var settings: SettingsStore
    let volume: VolumeStatus
    let isEnabled: Bool
    let onVolumeChange: (Double) -> Void
    let onToggleMute: () -> Void
    let onSelectOutputDevice: (AudioOutputDevice) -> Void
    let onOpenSoundSettings: () -> Void

    @State private var draftVolume = 0.0
    @State private var isAdjusting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2.fill")
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(StatusPresentation.volumeTitle(volume, localization: localization))
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()

                Spacer()

                Button(
                    localization.string(.volumeActionOpenSettings),
                    systemImage: "gearshape",
                    action: onOpenSoundSettings
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(localization.string(.volumeActionOpenSettings))
                .accessibilityLabel(localization.string(.volumeActionOpenSettings))
                .frame(width: 24, height: 24)
            }

            HStack(spacing: 10) {
                Button(
                    volume.isMuted ? localization.string(.volumeUnmuted) : localization.string(.volumeMuted),
                    systemImage: volume.isMuted ? "speaker.slash.fill" : "speaker.fill",
                    action: onToggleMute
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(volume.isMuted ? Color.red : Color.secondary)
                .help(volume.isMuted ? localization.string(.volumeUnmuted) : localization.string(.volumeMuted))
                .disabled(!isEnabled)
                .frame(width: 24)

                Slider(
                    value: $draftVolume,
                    in: 0...1,
                    onEditingChanged: handleVolumeEditing
                )
                .tint(volume.isMuted ? Color.secondary : Color.accentColor)
                .disabled(!isEnabled)
                .accessibilityLabel(localization.string(.volumeAccessibilityLabel))
                .accessibilityValue(percentageText)

                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Divider()

            HStack(spacing: 10) {
                Image(systemName: "hifispeaker.fill")
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(localization.string(.volumeOutputTitle))
                    .font(.headline.weight(.semibold))
            }

            OutputDeviceList(
                settings: settings,
                devices: volume.outputDevices,
                onSelect: onSelectOutputDevice
            )
        }
        .onAppear(perform: synchronizeVolume)
        .onChange(of: draftVolume) { _, newValue in
            updateVolume(newValue)
        }
        .onChange(of: volume.scalar) { _, _ in
            guard !isAdjusting else { return }
            synchronizeVolume()
        }
    }

    private var percentageText: String {
        guard draftVolume.isFinite else { return "—" }
        return "\(Int((min(1, max(0, draftVolume)) * 100).rounded()))%"
    }

    private func handleVolumeEditing(_ isEditing: Bool) {
        isAdjusting = isEditing
    }

    private func updateVolume(_ newValue: Double) {
        let scalar = volume.scalar ?? -1
        guard scalar.isFinite,
              abs(newValue - min(1, max(0, scalar))) >= 0.0005 else {
            return
        }
        onVolumeChange(newValue)
    }

    private func synchronizeVolume() {
        guard let scalar = volume.scalar, scalar.isFinite else {
            draftVolume = 0
            return
        }
        draftVolume = min(1, max(0, scalar))
    }
}
