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
