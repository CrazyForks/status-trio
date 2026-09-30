import SwiftUI

struct OutputDeviceList: View {
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var settings: SettingsStore
    let devices: [AudioOutputDevice]
    let onSelect: (AudioOutputDevice) -> Void
    /// Synthetic AirPods output rows the preview injects below the real list. They
    /// render like any other row but bypass ordering and the expansion control,
    /// because they only exist to exercise the listening-mode control's layout.
    var previewDevices: [AudioOutputDevice] = []
    /// A language override applied only to the preview rows, so one preview can show
    /// a different locale's mode names than the panel around it. `nil` leaves them on
    /// the panel's own localization.
    var previewLocalization: Localization? = nil
    /// Resolves the listening-mode control for a row's endpoint, or `nil`. Defaults
    /// to no control so a plain list is byte-for-byte what it was before.
    var controlProvider: (AudioOutputDevice) -> BluetoothListeningModePresentation? = { _ in nil }
    /// Where a row's mode tap is forwarded. Defaults to a no-op.
    var onSelectListeningMode: (AudioOutputDevice, BluetoothListeningMode) -> Void = { _, _ in }

    @State private var isExpanded = false

    var body: some View {
        let model = OutputDeviceListModel.make(
            devices: devices,
            order: settings.outputDeviceOrder,
            limit: settings.visibleOutputDeviceLimit,
            isExpanded: isExpanded
        )

        if devices.isEmpty && previewDevices.isEmpty {
            Label(localization.string(.volumeOutputEmpty), systemImage: "questionmark.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else {
            VStack(spacing: 2) {
                deviceRows(model.visibleDevices)

                // Preview rows sit under the real ones, outside the ordering and the
                // expansion control — they are display scaffolding, not devices. The
                // language override, when set, is scoped to just this subtree so the
                // synthetic capsules show that locale while the real rows above do not.
                ForEach(previewDevices) { device in
                    row(device)
                }
                .environmentObject(previewLocalization ?? localization)

                if model.canToggleExpansion {
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))

                            Text(
                                localization.string(
                                    isExpanded
                                        ? .volumeOutputCollapse
                                        : .volumeOutputExpand
                                )
                            )
                            .font(.callout)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func deviceRows(_ devices: [AudioOutputDevice]) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(devices) { device in
                row(device)
            }
        }
    }

    private func row(_ device: AudioOutputDevice) -> some View {
        OutputDeviceRow(
            device: device,
            onSelect: onSelect,
            listeningMode: device.isCurrent ? controlProvider(device) : nil,
            onSelectListeningMode: { mode in onSelectListeningMode(device, mode) }
        )
    }
}
