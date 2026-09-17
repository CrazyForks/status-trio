import SwiftUI

struct OutputDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let device: AudioOutputDevice
    let onSelect: (AudioOutputDevice) -> Void

    var body: some View {
        Button {
            onSelect(device)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(device.isCurrent ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.14))

                    AudioOutputDeviceIconView(device: device)
                        .foregroundStyle(device.isCurrent ? Color.accentColor : Color.secondary)
                }
                // Stay inside the icon column when the disclosure clips its content.
                .frame(width: 24, height: 24)

                Text(displayName)
                    .font(.body.weight(device.isCurrent ? .semibold : .regular))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let volume = device.volume, volume.isFinite {
                    Text(
                        volume.formatted(
                            .percent
                                .precision(.fractionLength(0))
                                .locale(localization.resolvedLanguage.locale)
                        )
                    )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if device.isCurrent {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            device.isCurrent
                ? localization.format(.commonLabelValue, displayName, localization.string(.volumeOutputCurrent))
                : localization.format(.volumeOutputSwitchTo, displayName)
        )
        .accessibilityValue(device.isCurrent ? localization.string(.volumeOutputCurrent) : "")
    }

    private var displayName: String {
        device.name ?? localization.string(.volumeOutputUnknownDevice)
    }
}
