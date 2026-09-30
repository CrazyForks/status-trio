import SwiftUI

struct BluetoothStatusView: View {
    @EnvironmentObject private var localization: Localization
    let state: BluetoothPanelState
    let actions: StatusPanelActions
    let onSetExpanded: (Bool) -> Void
    let onRequestAuthorization: () -> Void
    let onOpenBluetoothSettings: () -> Void
    let onOpenBluetoothPermissionSettings: () -> Void

    private var showsNearbyBatteryLevels: Bool {
        state.showsBatteryLevels && state.showsNearbyBatteryDevices
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                titleBlock

                Button(action: { actions.refreshBluetooth() }) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 24, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help(localization.string(.bluetoothRefresh))
                .accessibilityLabel(localization.string(.bluetoothRefresh))

                Button(localization.string(.bluetoothActionOpenSettings), systemImage: "gearshape", action: onOpenBluetoothSettings)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(localization.string(.bluetoothActionOpenSettings))
                    .frame(width: 24, height: 24)
            }

            if !state.pairedRows.isEmpty {
                if state.showsPairedHeading {
                    Text(localization.string(.bluetoothPairedDevicesTitle))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                }

                BluetoothDeviceList(
                    state: state,
                    onExpandedChange: onSetExpanded,
                    onRowTapped: { actions.rowTapped(address: $0) },
                    onConfirmDisconnect: { actions.confirmBluetoothDisconnect(address: $0) },
                    onCancelDisconnect: { actions.cancelDisconnect() }
                )

                if let errorText = state.errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !state.nearbyRows.isEmpty {
                NearbyBluetoothBatteryList(rows: state.nearbyRows)
            }
        }
        .onAppear { actions.bluetoothSummaryAppeared() }
        .task(id: state.batteryReadTaskID) {
            actions.updateBluetoothBatteryLevelsClaim(
                enabled: state.showsBatteryLevels && state.hasConnectedDevices
            )
        }
        .task(id: showsNearbyBatteryLevels) {
            actions.updateBluetoothNearbyBatteryClaim(enabled: showsNearbyBatteryLevels)
        }
        .onDisappear { actions.bluetoothSummaryDisappeared() }
    }

    @ViewBuilder
    private var titleBlock: some View {
        switch state.summary.intent {
        case .requestBluetoothAuthorization:
            Button(action: onRequestAuthorization) { titleContent }
                .buttonStyle(.plain)
                .accessibilityLabel(state.summary.accessibilityLabel)
        case .openBluetoothPermissionSettings:
            Button(action: onOpenBluetoothPermissionSettings) { titleContent }
                .buttonStyle(.plain)
                .accessibilityLabel(state.summary.accessibilityLabel)
        case .none:
            titleContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel(state.summary.accessibilityLabel)
        case .batteryDetails, .wifiDetails, .requestWiFiNameAccess, .locationSettings, .wiredDetails:
            titleContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel(state.summary.accessibilityLabel)
        }
    }

    private var titleContent: some View {
        HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
            BluetoothIcon(size: BluetoothPanelMetrics.iconColumnWidth)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.summary.title).font(.headline)
                subtitle
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var subtitle: some View {
        if let segments = state.summaryBatterySegments {
            BluetoothBatteryLevelText.drawn(segments)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if !state.summary.subtitle.isEmpty {
            Text(state.summary.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
