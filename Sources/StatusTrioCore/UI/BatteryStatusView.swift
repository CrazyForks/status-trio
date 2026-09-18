import SwiftUI

/// The battery summary row. Like the Wi-Fi and Bluetooth rows, the row itself
/// is the affordance: activating it switches the popover to the battery page.
struct BatteryStatusView: View {
    @EnvironmentObject private var localization: Localization
    let battery: BatteryStatus
    let onOpenBatteryDetails: () -> Void
    let onOpenBatterySettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenBatteryDetails) {
                HStack(spacing: 10) {
                    Image(systemName: batterySymbolName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(batterySymbolColor)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(StatusPresentation.batteryTitle(battery, localization: localization))
                            .font(.headline)
                            .monospacedDigit()
                        Text(StatusPresentation.batterySubtitle(battery, localization: localization))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    if showsDetailAffordance {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!showsDetailAffordance)
            .accessibilityLabel(StatusPresentation.batteryTitle(battery, localization: localization))
            .accessibilityValue(StatusPresentation.batterySubtitle(battery, localization: localization))

            if battery.isPresent {
                Button(
                    localization.string(.batteryActionOpenSettings),
                    systemImage: "gearshape",
                    action: onOpenBatterySettings
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(localization.string(.batteryActionOpenSettings))
                .frame(width: 24, height: 24)
            }
        }
    }

    /// A Mac without a battery has no details to open, so the row stays inert
    /// and shows no chevron — the same shape as an unavailable Bluetooth radio.
    var showsDetailAffordance: Bool { battery.isPresent }

    private var batterySymbolName: String {
        guard battery.isPresent else { return "battery.slash" }
        if battery.isCharging || battery.isConnectedToPower {
            return "battery.100.bolt"
        }
        switch battery.percentage {
        case 88...100: return "battery.100"
        case 63..<88:  return "battery.75"
        case 38..<63:  return "battery.50"
        case 13..<38:  return "battery.25"
        default:       return "battery.0"
        }
    }

    private var batterySymbolColor: Color {
        guard battery.isPresent else { return .secondary }
        if battery.isCharging || battery.isConnectedToPower {
            return .green
        }
        if battery.isLowPowerMode {
            return .yellow
        }
        if battery.percentage <= 20 {
            return .red
        }
        return .primary
    }
}
