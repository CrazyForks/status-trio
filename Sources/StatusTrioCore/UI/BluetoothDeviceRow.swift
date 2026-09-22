import SwiftUI

/// One paired-device row. The status panel's list and the detail page share it
/// so the two surfaces cannot drift, and a device the report carries no level
/// for simply draws no battery text.
///
/// The row is a pure function of its inputs: which action is in flight (or which
/// failure is on screen), and whether it is currently asking to confirm a
/// disconnect. The controller owns that confirmation, so the question cannot
/// outlive the panel that asked it.
///
/// A connected device is drawn the way the volume output list draws the device
/// in use: its glyph ringed in the accent colour, its name in semibold, and a
/// checkmark after it. That is what says "connected" — the row does not also
/// spell it out, which leaves its trailing space to the battery level and to
/// whatever an action is doing.
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
        let status = BluetoothDeviceActionPolicy.status(for: device, actionState: actionState)
        if isConfirmingDisconnect {
            HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
                badge
                name
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
                    badge
                    name
                    Spacer(minLength: 8)
                    batteryText
                    if status.drawsText {
                        statusText(status)
                    } else if device.isConnected {
                        connectedMark
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isActionInFlight)
            .help(actionHelp)
            .accessibilityElement(children: .combine)
            // The word is gone from the row, so the state lives here instead: a
            // screen reader still hears whether the device is connected.
            .accessibilityValue(stateAccessibilityValue)
            .accessibilityHint(actionHelp)
        }
    }

    /// The device's glyph in the section's own icon column, ringed when the
    /// device is connected — the volume output list's treatment for the device in
    /// use, scaled to the column the section icon already uses.
    private var badge: some View {
        ZStack {
            Circle()
                .fill(
                    device.isConnected
                        ? Color.accentColor.opacity(0.15)
                        : Color.secondary.opacity(0.14)
                )
            Image(systemName: BluetoothDeviceRowIcon.symbolName(for: device))
                .foregroundStyle(device.isConnected ? Color.accentColor : Color.secondary)
        }
        .frame(
            width: BluetoothPanelMetrics.iconColumnWidth,
            height: BluetoothPanelMetrics.iconColumnWidth
        )
        .accessibilityHidden(true)
    }

    private var name: some View {
        Text(device.name)
            .font(.body.weight(device.isConnected ? .semibold : .regular))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// Says the device is connected without a word, the way the volume list marks
    /// the device in use. The badge already carries the colour, so this is not
    /// the only indicator.
    private var connectedMark: some View {
        Image(systemName: "checkmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
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

    /// Only the states `drawsText` accepts reach this: what the row cannot say by
    /// appearance alone.
    @ViewBuilder
    private func statusText(_ status: BluetoothDeviceRowStatus) -> some View {
        switch status {
        case .connecting:
            workingLabel(localization.string(.bluetoothStateConnecting))
        case .disconnecting:
            workingLabel(localization.string(.bluetoothStateDisconnecting))
        case .connectFailed:
            failureLabel(localization.string(.bluetoothStateConnectFailed))
        case .disconnectFailed:
            failureLabel(localization.string(.bluetoothStateDisconnectFailed))
        case .connected, .notConnected:
            EmptyView()
        }
    }

    /// What this row's status says, for the accessibility value that replaced the
    /// visible word.
    private var stateAccessibilityValue: String {
        switch BluetoothDeviceActionPolicy.status(for: device, actionState: actionState) {
        case .connected:
            localization.string(.bluetoothConnected)
        case .notConnected:
            localization.string(.bluetoothNotConnected)
        case .connecting:
            localization.string(.bluetoothStateConnecting)
        case .disconnecting:
            localization.string(.bluetoothStateDisconnecting)
        case .connectFailed:
            localization.string(.bluetoothStateConnectFailed)
        case .disconnectFailed:
            localization.string(.bluetoothStateDisconnectFailed)
        }
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
