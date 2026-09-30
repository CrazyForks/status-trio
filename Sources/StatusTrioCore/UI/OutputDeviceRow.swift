import SwiftUI

struct OutputDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let device: AudioOutputDevice
    let onSelect: (AudioOutputDevice) -> Void
    /// The AirPods listening-mode control, shown only for the current output row the
    /// controller resolved a controllable presentation for. `nil` (the default) draws
    /// the row exactly as any other output device — a single selectable line.
    var listeningMode: BluetoothListeningModePresentation? = nil
    var onSelectListeningMode: ((BluetoothListeningMode) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            selectionButton

            // The capsules are their own buttons, so they deliberately sit outside
            // the selection button (nesting a Button in a Button would swallow the
            // inner taps). Only the current, controllable output gets the second
            // line; every other row is one line, unchanged.
            if let listeningMode, listeningMode.isControllable, let onSelectListeningMode {
                BluetoothListeningModeControl(
                    presentation: listeningMode,
                    onSelect: onSelectListeningMode
                )
                .padding(.leading, Self.modeLeadingInset)
            }
        }
    }

    private var selectionButton: some View {
        Button {
            onSelect(device)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(device.isCurrent ? Color.accentColor : Color.secondary.opacity(0.14))

                    AudioOutputDeviceIconView(device: device)
                        .foregroundStyle(device.isCurrent ? Color.white : Color.secondary)
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

    /// Aligns the mode capsules under the device name — past the 24-point icon
    /// column and the 10-point icon gap — the same column the Bluetooth rows use.
    private static let modeLeadingInset: CGFloat =
        BluetoothPanelMetrics.iconColumnWidth + BluetoothPanelMetrics.iconTextSpacing
}
