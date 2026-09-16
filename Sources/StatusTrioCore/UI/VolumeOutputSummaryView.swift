import SwiftUI

/// Keeps the active output visible even when it falls outside the user's list limit.
struct VolumeOutputSummaryView: View {
    @EnvironmentObject private var localization: Localization
    let volume: VolumeStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let device = volume.outputDevices.first(where: \.isCurrent) {
                    AudioOutputDeviceIconView(device: device, glyphSize: 17)
                } else {
                    Image(systemName: "speaker.wave.2.fill")
                }
            }
            .frame(width: 24, height: 24)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(StatusPresentation.volumeSubtitle(volume, localization: localization))
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(StatusPresentation.volumeSubtitle(volume, localization: localization))

                Text(volume.isMuted
                     ? localization.string(.volumeMuted)
                     : StatusPresentation.volumeTitle(volume, localization: localization))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
