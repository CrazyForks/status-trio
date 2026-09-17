import SwiftUI

/// Keeps the active output visible even when it falls outside the user's list limit.
struct VolumeOutputSummaryView: View {
    @EnvironmentObject private var localization: Localization
    let volume: VolumeStatus

    // Volume readings are live; device metadata may be cached between device events.
    var displayDeviceName: String? {
        volume.deviceName ?? currentDevice?.name
    }

    var iconDevice: AudioOutputDevice? {
        guard let currentDevice else { return nil }
        if let liveName = volume.deviceName, let cachedName = currentDevice.name,
           liveName != cachedName {
            return nil
        }
        return currentDevice
    }

    private var currentDevice: AudioOutputDevice? {
        volume.outputDevices.first(where: \.isCurrent)
    }

    var body: some View {
        let name = displayDeviceName ?? localization.string(.volumeNoDefaultDevice)
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let device = iconDevice {
                    AudioOutputDeviceIconView(device: device, glyphSize: 17)
                } else {
                    Image(systemName: "speaker.wave.2.fill")
                }
            }
            .frame(width: 24, height: 24)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(name)

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
