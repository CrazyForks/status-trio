import SwiftUI

struct BatteryStatusView: View {
    @EnvironmentObject private var localization: Localization
    let battery: BatteryStatus
    let detailsController: BatteryDetailsController
    let isPresented: Bool
    let onOpenBatterySettings: () -> Void

    @State private var isExpanded = false

    init(
        battery: BatteryStatus, detailsController: BatteryDetailsController,
        isPresented: Bool, onOpenBatterySettings: @escaping () -> Void,
        showsDetailsInitially: Bool = false
    ) {
        self.battery = battery
        self.detailsController = detailsController
        self.isPresented = isPresented
        self.onOpenBatterySettings = onOpenBatterySettings
        _isExpanded = State(initialValue: showsDetailsInitially)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summary
            if battery.isPresent {
                DisclosureGroup(isExpanded: $isExpanded) {
                    // Conditional creation guarantees no collection while collapsed.
                    if isExpanded && isPresented { BatteryDetailsView(controller: detailsController, battery: battery).padding(.top, 6) }
                } label: {
                    Text(localization.string(.batteryDetailsTitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            Image(systemName: batterySymbolName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(batterySymbolColor)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(StatusPresentation.batteryTitle(battery, localization: localization))
                    .font(.system(size: 13.5, weight: .semibold))
                    .monospacedDigit()
                Text(StatusPresentation.batterySubtitle(battery, localization: localization))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if battery.isPresent {
                Button(action: onOpenBatterySettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(localization.string(.batteryActionOpenSettings))
                .accessibilityLabel(localization.string(.batteryActionOpenSettings))
            }
        }
    }

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
