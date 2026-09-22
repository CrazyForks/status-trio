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

    /// How tall one row is: the badge sets its height, because the name is a
    /// single line and never taller. The list can therefore tell whether it needs
    /// a scroll view at all without measuring anything.
    private static let rowSpacing: CGFloat = 2
    private static let rowPitch = BluetoothPanelMetrics.iconColumnWidth + rowSpacing
    private static var rowsThatFit: Int { Int(maximumRowsHeight / rowPitch) }

    var body: some View {
        let model = BluetoothDeviceListModel.make(
            devices: devices,
            order: options.order,
            limit: options.maxVisibleDevices,
            isExpanded: isExpanded
        )

        VStack(spacing: Self.rowSpacing) {
            rows(model.visibleDevices)

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

    /// The rows, bounded.
    ///
    /// The scroll view appears only once the rows outgrow the panel. The summary
    /// popover has no scroll view of its own, so without a bound a long list — an
    /// expanded one, or a limit the user raised — would keep growing the popover
    /// past the screen. A scroll view that is not needed is not free either: its
    /// scroller flashes while an expansion animates through the moment where the
    /// content is taller than the shrinking frame, which a list of six devices
    /// should never show. Below the bound the rows are laid out directly, so
    /// there is nothing to flash. The panel's scroll-wheel handling already
    /// leaves a pointer over an `NSScrollView` to that view instead of adjusting
    /// the volume.
    @ViewBuilder
    private func rows(_ visibleDevices: [BluetoothDevice]) -> some View {
        if visibleDevices.count > Self.rowsThatFit {
            ScrollView { rowStack(visibleDevices) }
                .frame(maxHeight: Self.maximumRowsHeight)
        } else {
            rowStack(visibleDevices)
        }
    }

    private func rowStack(_ visibleDevices: [BluetoothDevice]) -> some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(visibleDevices) { device in
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
}
