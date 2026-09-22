import SwiftUI

/// One paired-device row. The status panel's list and the detail page share it
/// so the two surfaces cannot drift, and a device the report carries no level
/// for simply draws no battery text.
///
/// The row is a pure function of its inputs: which action is in flight (or which
/// failure is on screen), and whether it is currently asking to confirm a
/// disconnect. Both parents hold that confirmation themselves, so the state
/// cannot outlive the surface showing it.
struct BluetoothDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let device: BluetoothDevice
    let batteryLevels: [String: BluetoothBatteryLevel]
    let actionState: BluetoothDeviceActionState?
    let isConfirmingDisconnect: Bool
    let onPerformAction: () -> Void
    let onRequestDisconnect: () -> Void
    let onCancelDisconnect: () -> Void

    var body: some View {
        if isConfirmingDisconnect {
            HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
                leading
                Spacer(minLength: 8)
                Text(localization.string(.bluetoothActionConfirmDisconnect))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(localization.string(.bluetoothActionDisconnect), action: onPerformAction)
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
            Button(action: { handleTap() }) {
                HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
                    leading
                    Spacer(minLength: 8)
                    batteryText
                    statusText
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isActionInFlight)
            .help(actionHelp)
            .accessibilityElement(children: .combine)
            .accessibilityHint(actionHelp)
        }
    }

    private var leading: some View {
        HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
            Image(systemName: BluetoothDeviceRowIcon.symbolName(for: device))
                .frame(width: BluetoothPanelMetrics.iconColumnWidth)
                .foregroundStyle(.secondary)
            Text(device.name)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var batteryText: some View {
        if let level = BluetoothDevicePresentation.batteryLevelText(
            for: device,
            batteryLevels: batteryLevels
        ) {
            Text(level)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch BluetoothDeviceActionPolicy.status(for: device, actionState: actionState) {
        case .connected:
            stateLabel(localization.string(.bluetoothConnected))
        case .notConnected:
            stateLabel(localization.string(.bluetoothNotConnected))
        case .connecting:
            workingLabel(localization.string(.bluetoothStateConnecting))
        case .disconnecting:
            workingLabel(localization.string(.bluetoothStateDisconnecting))
        case .connectFailed:
            failureLabel(localization.string(.bluetoothStateConnectFailed))
        case .disconnectFailed:
            failureLabel(localization.string(.bluetoothStateDisconnectFailed))
        }
    }

    private func stateLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func workingLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityLabel(text)
    }

    private func failureLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(1)
    }

    /// Whether an action is already running for this device. A failure that is
    /// still on screen is not in flight: tapping it retries.
    private var isActionInFlight: Bool {
        switch actionState {
        case .connecting, .disconnecting: true
        case .failed, .none: false
        }
    }

    private var actionHelp: String {
        BluetoothDeviceActionPolicy.action(for: device) == .connect
            ? localization.string(.bluetoothActionConnect)
            : localization.string(.bluetoothActionDisconnect)
    }

    private func handleTap() {
        guard !isActionInFlight else { return }
        if BluetoothDeviceActionPolicy.requiresConfirmation(for: device) {
            onRequestDisconnect()
        } else {
            onPerformAction()
        }
    }
}
