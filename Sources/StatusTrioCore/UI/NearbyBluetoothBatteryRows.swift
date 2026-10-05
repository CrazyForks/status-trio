import SwiftUI

struct NearbyBluetoothBatteryRows: View {
    @EnvironmentObject private var localization: Localization
    let rows: [NearbyBLEPanelRow]

    static let maximumRowsHeight: CGFloat = 168
    private static let rowSpacing: CGFloat = 2
    private static let rowPitch = BluetoothPanelMetrics.iconColumnWidth + rowSpacing
    private static var rowsThatFit: Int { Int(maximumRowsHeight / rowPitch) }

    var body: some View {
        if rows.count > Self.rowsThatFit {
            ScrollView { rowStack }
                .frame(maxHeight: Self.maximumRowsHeight)
        } else {
            rowStack
        }
    }

    private var rowStack: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(rows) { row in
                let name = row.device.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? localization.string(.bluetoothNearbyDeviceFallback)
                    : row.device.name
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

                    Text(row.batteryLevel.map { "\($0)%" } ?? "")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(name)
                .accessibilityValue(row.batteryLevel.map {
                    localization.format(.batteryAccessibilityValue, $0)
                } ?? "")
            }
        }
    }
}
