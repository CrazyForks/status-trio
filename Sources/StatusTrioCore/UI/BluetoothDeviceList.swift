import SwiftUI

struct BluetoothDeviceList: View {
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: BluetoothPanelState
    let onExpandedChange: (Bool) -> Void
    let onRowTapped: (String) -> Void
    let onConfirmDisconnect: (String) -> Void
    let onCancelDisconnect: () -> Void

    @State private var isExpanded = false

    static let maximumRowsHeight: CGFloat = 330
    private static let rowSpacing: CGFloat = 2

    var body: some View {
        VStack(spacing: Self.rowSpacing) {
            rows(state.pairedRows)

            if state.canExpand {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                    onExpandedChange(isExpanded)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        Text(localization.string(isExpanded ? .bluetoothListCollapse : .bluetoothListExpand))
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
        .onChange(of: state.canExpand) { _, canExpand in
            if !canExpand, isExpanded {
                isExpanded = false
                onExpandedChange(false)
            }
        }
    }

    @ViewBuilder
    private func rows(_ visibleRows: [PanelBluetoothDeviceRow]) -> some View {
        if estimatedContentHeight(for: visibleRows) > Self.maximumRowsHeight {
            ScrollView { rowStack(visibleRows) }
                .frame(maxHeight: Self.maximumRowsHeight)
        } else {
            rowStack(visibleRows)
        }
    }

    private func estimatedContentHeight(for visibleRows: [PanelBluetoothDeviceRow]) -> CGFloat {
        guard !visibleRows.isEmpty else { return 0 }
        return visibleRows.reduce(CGFloat(0)) { total, row in
            total + BluetoothDeviceRowMetrics.estimatedHeight(for: row.batteryLayout)
        } + Self.rowSpacing * CGFloat(visibleRows.count - 1)
    }

    private func rowStack(_ visibleRows: [PanelBluetoothDeviceRow]) -> some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(visibleRows, id: \.address) { row in
                BluetoothDeviceRow(
                    state: row,
                    isConfirmingDisconnect: state.confirmationAddress == row.address && row.requiresConfirmation,
                    onRowTapped: onRowTapped,
                    onConfirmDisconnect: onConfirmDisconnect,
                    onCancelDisconnect: onCancelDisconnect
                )
            }
        }
    }
}
