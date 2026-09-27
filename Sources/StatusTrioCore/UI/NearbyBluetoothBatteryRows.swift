import SwiftUI

struct NearbyBluetoothBatteryRows: View {
    @EnvironmentObject private var localization: Localization
    let devices: [NearbyBluetoothBatteryDevice]

    static let maximumRowsHeight: CGFloat = 168
    private static let rowSpacing: CGFloat = 2
    private static let rowPitch = BluetoothPanelMetrics.iconColumnWidth + rowSpacing
    private static var rowsThatFit: Int { Int(maximumRowsHeight / rowPitch) }

    var body: some View {
        if devices.count > Self.rowsThatFit {
            ScrollView { rows }
                .frame(maxHeight: Self.maximumRowsHeight)
        } else {
            rows
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(devices) { device in
                let name = device.displayName(fallback: localization.string(.bluetoothNearbyDeviceFallback))
                HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                        .frame(
                            width: BluetoothPanelMetrics.iconColumnWidth,
                            height: BluetoothPanelMetrics.iconColumnWidth
                        )
                        .accessibilityHidden(true)

                    Text(name)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Text("\(device.batteryLevel)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(name)
                .accessibilityValue(localization.format(.batteryAccessibilityValue, device.batteryLevel))
            }
        }
    }
}
