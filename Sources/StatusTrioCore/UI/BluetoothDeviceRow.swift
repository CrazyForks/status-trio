import SwiftUI

/// One paired-device row. The status panel's list and the detail page share it
/// so the two surfaces cannot drift, and a device the report carries no level
/// for simply draws no battery text.
struct BluetoothDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let device: BluetoothDevice
    let batteryLevels: [String: BluetoothBatteryLevel]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: BluetoothDeviceRowIcon.symbolName(for: device))
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(device.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if let level = BluetoothDevicePresentation.batteryLevelText(
                for: device,
                batteryLevels: batteryLevels
            ) {
                Text(level)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(
                device.isConnected
                    ? localization.string(.bluetoothConnected)
                    : localization.string(.bluetoothNotConnected)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
