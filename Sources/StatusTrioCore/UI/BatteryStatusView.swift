import SwiftUI

struct BatteryStatusView: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelSummaryState
    var cautionColor: Color = .yellow
    let onOpenBatteryDetails: () -> Void
    let onOpenBatterySettings: () -> Void
    /// The Low Power Mode write path, shown as a quick toggle beside the gear.
    /// Nil in previews and layout tests, where the row stays read-only.
    var lowPowerMode: LowPowerModeController?
    var showsLowPowerToggle: Bool = false

    private var hasDetails: Bool { state.intent == .batteryDetails }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenBatteryDetails) {
                HStack(spacing: 10) {
                    PanelSymbolView(source: state.symbol)
                        .foregroundStyle(state.tint.color(caution: cautionColor))
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title)
                            .font(.headline)
                            .monospacedDigit()
                        Text(state.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    if hasDetails {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasDetails)
            .accessibilityLabel(state.accessibilityLabel)
            .accessibilityValue(state.accessibilityValue)

            if showsLowPowerToggle, let lowPowerMode {
                lowPowerToggleButton(lowPowerMode)
            }

            if state.showsSettings {
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

    /// A one-click Low Power Mode switch, mirroring the system battery menu's
    /// quick toggle. Filled when on, outlined when off.
    private func lowPowerToggleButton(_ controller: LowPowerModeController) -> some View {
        Button {
            controller.setLowPowerMode(!controller.isLowPowerMode)
        } label: {
            Image(systemName: controller.isLowPowerMode ? "leaf.fill" : "leaf")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(controller.isLowPowerMode ? Color.green : Color.secondary)
        .help(localization.string(.lowPowerModeToggleDescription))
        .disabled(controller.isApplying)
        .accessibilityLabel(localization.string(.lowPowerModeToggle))
        .accessibilityValue(
            localization.string(controller.isLowPowerMode ? .batteryDetailsOn : .batteryDetailsOff)
        )
        .frame(width: 24, height: 24)
    }

    var showsDetailAffordance: Bool { hasDetails }
}
