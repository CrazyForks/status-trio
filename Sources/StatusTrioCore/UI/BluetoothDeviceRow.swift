import SwiftUI

struct BluetoothDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelBluetoothDeviceRow
    let isConfirmingDisconnect: Bool
    let onRowTapped: (String) -> Void
    let onConfirmDisconnect: (String) -> Void
    let onCancelDisconnect: () -> Void

    var body: some View {
        if isConfirmingDisconnect {
            HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
                badge
                name
                Spacer(minLength: 8)
                Text(localization.string(.bluetoothActionConfirmDisconnect))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(state.actionTitle) { onConfirmDisconnect(state.address) }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                Button(localization.string(.bluetoothActionCancel), action: onCancelDisconnect)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .contain)
        } else {
            Button { onRowTapped(state.address) } label: {
                switch state.batteryLayout {
                case .inline:
                    inlineContent
                case .components:
                    componentContent
                }
            }
            .buttonStyle(.plain)
            .disabled(!state.actionEnabled)
            .help(state.actionTitle)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(state.accessibilityLabel)
            .accessibilityValue(state.accessibilityValue)
            .accessibilityHint(state.actionTitle)
        }
    }

    private var inlineContent: some View {
        HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
            badge
            name
            Spacer(minLength: 8)
            batteryText
            trailingStatus
        }
        .contentShape(Rectangle())
    }

    private var componentContent: some View {
        HStack(alignment: .center, spacing: BluetoothPanelMetrics.iconTextSpacing) {
            badge
            VStack(alignment: .leading, spacing: BluetoothPanelMetrics.componentBatteryLineSpacing) {
                name
                batteryText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailingStatus
        }
        .contentShape(Rectangle())
        .padding(.bottom, BluetoothPanelMetrics.componentRowBottomPadding)
    }

    private var badge: some View {
        ZStack {
            Circle().fill(state.isConnected ? Color.accentColor : Color.secondary.opacity(0.14))
            PanelSymbolView(source: state.icon, size: 15, weight: .semibold)
                .foregroundStyle(state.isConnected ? Color.white : Color.secondary)
        }
        .frame(width: BluetoothPanelMetrics.iconColumnWidth, height: BluetoothPanelMetrics.iconColumnWidth)
        .accessibilityHidden(true)
    }

    private var name: some View {
        Text(state.title)
            .font(.body.weight(state.isConnected ? .semibold : .regular))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private var batteryText: some View {
        if let segments = state.batterySegments {
            BluetoothBatteryLevelText.drawn(segments)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if let statusText = state.statusText {
            HStack(spacing: 4) {
                if state.isBusy { ProgressView().controlSize(.small) }
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(state.statusTint.color(caution: .red))
                    .lineLimit(1)
            }
            .accessibilityLabel(statusText)
        }
    }
}
