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

    var body: some View {
        let model = BluetoothDeviceListModel.make(
            devices: devices,
            order: options.order,
            limit: options.maxVisibleDevices,
            isExpanded: isExpanded
        )

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
