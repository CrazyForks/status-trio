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
    let options: BluetoothDeviceListOptions
    let onPerformAction: (BluetoothDevice) -> Void

    @State private var confirmingAddress: String?

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
                    onPerformAction: {
                        confirmingAddress = nil
                        onPerformAction(device)
                    },
                    onRequestDisconnect: { confirmingAddress = address },
                    onCancelDisconnect: { confirmingAddress = nil }
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
        .onDisappear {
            // The popover's content view controller is retained after a close so
            // a reopen is cheap, so these view objects — and this `@State` — live
            // on past the close. A confirmation therefore has to be cancelled
            // explicitly instead of relying on the view being torn down, or
            // reopening the panel would show the prompt still open and one more
            // click would send the disconnect the close was meant to cancel. This
            // mirrors how the Bluetooth surfaces release their claims in their
            // own `onDisappear`.
            confirmingAddress = nil
        }
    }
}
