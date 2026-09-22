import SwiftUI

/// The paired-device list shown inside the status panel, under the Bluetooth
/// row. It mirrors the volume output list: the first `limit` devices are always
/// visible and anything beyond them is revealed by an expansion control. Each
/// row is a control: tapping it connects or disconnects that device, and an
/// input device's disconnect is confirmed in place first.
struct BluetoothDeviceList: View {
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let devices: [BluetoothDevice]
    let batteryLevels: [String: BluetoothBatteryLevel]
    let actionStates: [String: BluetoothDeviceActionState]
    /// The device whose disconnect is waiting for confirmation, by normalized
    /// address. The controller owns it so that closing the panel cancels it even
    /// though the popover keeps this view alive.
    let confirmingAddress: String?
    let options: BluetoothDeviceListOptions
    let onPerformAction: (BluetoothDevice) -> Void
    let onRequestDisconnect: (BluetoothDevice) -> Void
    let onCancelDisconnect: () -> Void

    @State private var isExpanded = false

    /// How tall the rows may grow before they scroll, matching the Wi-Fi list's
    /// own bound so the two lists in the panel stop at the same place.
    static let maximumRowsHeight: CGFloat = 330

    var body: some View {
        let model = BluetoothDeviceListModel.make(
            devices: devices,
            order: options.order,
            limit: options.maxVisibleDevices,
            isExpanded: isExpanded
        )

        VStack(spacing: 2) {
            // The rows scroll only once they outgrow the panel. The summary
            // popover has no scroll view of its own, so without a bound a long
            // list — an expanded one, or a limit the user raised — would keep
            // growing past the screen. This is the bound the Wi-Fi list uses, and
            // the panel's scroll-wheel handling already leaves a pointer over an
            // `NSScrollView` to that view instead of adjusting the volume.
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.visibleDevices) { device in
                        let address = BluetoothBatteryReader.normalizedAddress(device.id)
                        BluetoothDeviceRow(
                            device: device,
                            batteryLevels: batteryLevels,
                            actionState: actionStates[address],
                            isConfirmingDisconnect: confirmingAddress == address
                                && BluetoothDeviceActionPolicy.requiresConfirmation(for: device),
                            onPerformAction: { onPerformAction(device) },
                            onRequestDisconnect: { onRequestDisconnect(device) },
                            onCancelDisconnect: onCancelDisconnect
                        )
                    }
                }
            }
            .frame(maxHeight: Self.maximumRowsHeight)

            // Deliberately outside the scroll region: collapsing a long list must
            // not require scrolling to the bottom first.
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
                                isExpanded ? .bluetoothListCollapse : .bluetoothListExpand
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
