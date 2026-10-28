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
    var chargeToFullNow: ChargeToFullNowPresentation = .hidden
    var onChargeToFullNow: () -> Void = {}

    private var hasDetails: Bool { state.intent == .batteryDetails }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow

            if chargeToFullNow.showsButton {
                chargeToFullNowButton
            } else if let key = chargeToFullNowUnavailableKey {
                chargeToFullNowNotice(key)
            }
        }
    }

    private var summaryRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onOpenBatteryDetails) {
                HStack(spacing: 10) {
                    PanelSymbolView(source: state.symbol)
                        .foregroundStyle(state.tint.color(caution: cautionColor))
                        .frame(
                            width: PanelSummaryActionMetrics.hitTarget,
                            height: PanelSummaryActionMetrics.hitTarget
                        )
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

            // The chevron sits immediately left of the gear so its right edge
            // lines up with the same affordance in the rows below; the leaf would
            // otherwise push it one slot to the left.
            if hasDetails {
                Button(action: onOpenBatteryDetails) {
                    PanelActionGlyph(
                        systemName: "chevron.right",
                        font: .caption.weight(.semibold)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(localization.string(.batteryDetailsTitle))
                .help(localization.string(.batteryDetailsTitle))
            }

            if state.showsSettings {
                Button(action: onOpenBatterySettings) {
                    PanelActionGlyph(
                        systemName: "gearshape",
                        verticalOpticalOffset: 0
                    )
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(localization.string(.batteryActionOpenSettings))
                .accessibilityLabel(localization.string(.batteryActionOpenSettings))
            }
        }
    }

    private var chargeToFullNowButton: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: onChargeToFullNow) {
                HStack(spacing: 7) {
                    if chargeToFullNow.isApplying || chargeToFullNow.isCancelling {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else if chargeToFullNowShowsBolt {
                        Image(systemName: "bolt.fill")
                            .frame(width: 14, height: 14)
                    }

                    if let chargingLabel = chargeToFullNowChargingLabel {
                        Text(chargingLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Spacer(minLength: 8)

                        Text(chargeToFullNowLabel)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Text(chargeToFullNowLabel)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Spacer(minLength: 0)
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.12))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(chargeToFullNow.isApplying || chargeToFullNow.isCancelling)
            .accessibilityLabel(chargeToFullNowLabel)

            switch chargeToFullNow {
            case .failed:
                chargeToFullNowNotice(.batteryActionChargeToFullNowFailed)
            case .cancelConfirmationRequired:
                chargeToFullNowNotice(
                    localization.string(
                        .batteryActionCancelChargeToFullNowConfirmation
                    ),
                    color: .secondary
                )
            case .cancelPending:
                chargeToFullNowNotice(
                    localization.string(.batteryActionCancelChargeToFullNowPending),
                    color: .secondary,
                    showsIcon: false
                )
            case .cancelFailed(let message):
                chargeToFullNowNotice(
                    localization.format(
                        .batteryActionCancelChargeToFullNowFailed,
                        message ?? ""
                    )
                )
            case .cancelSucceeded(let limit, let usedFallback):
                chargeToFullNowNotice(
                    localization.format(
                        usedFallback
                            ? .batteryActionCancelChargeToFullNowFallback
                            : .batteryActionCancelChargeToFullNowRestored,
                        limit
                    ),
                    color: .secondary,
                    showsIcon: false
                )
            case .hidden,
                 .available,
                 .applying,
                 .chargingToFull,
                 .cancelling,
                 .unavailable:
                EmptyView()
            }
        }
    }

    private var chargeToFullNowChargingLabel: String? {
        chargeToFullNow == .chargingToFull
            ? localization.string(.batteryActionChargeToFullNowCharging)
            : nil
    }

    private var chargeToFullNowLabel: String {
        switch chargeToFullNow {
        case .applying:
            localization.string(.batteryActionChargeToFullNowApplying)
        case .chargingToFull:
            localization.string(.batteryActionCancelChargeToFullNow)
        case .cancelling:
            localization.string(.batteryActionCancelChargeToFullNowApplying)
        case .cancelFailed, .cancelPending:
            localization.string(.batteryActionCancelChargeToFullNow)
        case .cancelConfirmationRequired(let limit, let usedFallback):
            localization.format(
                usedFallback
                    ? .batteryActionCancelChargeToFullNowConfirmFallback
                    : .batteryActionCancelChargeToFullNowConfirm,
                limit
            )
        case .hidden, .available, .failed, .unavailable, .cancelSucceeded:
            localization.string(.batteryActionChargeToFullNow)
        }
    }

    private var chargeToFullNowShowsBolt: Bool {
        switch chargeToFullNow {
        case .available, .failed, .cancelSucceeded:
            true
        case .hidden,
             .applying,
             .chargingToFull,
             .unavailable,
             .cancelConfirmationRequired,
             .cancelPending,
             .cancelling,
             .cancelFailed:
            false
        }
    }

    private var chargeToFullNowUnavailableKey: LocalizationKey? {
        chargeToFullNow == .unavailable
            ? .batteryActionChargeToFullNowUnavailable
            : nil
    }

    private func chargeToFullNowNotice(_ key: LocalizationKey) -> some View {
        chargeToFullNowNotice(
            localization.string(key),
            color: .red
        )
    }

    private func chargeToFullNowNotice(
        _ text: String,
        color: Color = .red,
        showsIcon: Bool = true
    ) -> some View {
        Group {
            if showsIcon {
                Label(
                    text,
                    systemImage: "exclamationmark.triangle.fill"
                )
            } else {
                Text(text)
            }
        }
        .font(.caption2)
        .foregroundStyle(color)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A one-click Low Power Mode switch, mirroring the system battery menu's
    /// quick toggle. Filled when on, outlined when off.
    private func lowPowerToggleButton(_ controller: LowPowerModeController) -> some View {
        // A dedicated observing subview: the row itself holds the controller as a
        // plain value, so reading `isLowPowerMode` here would not re-render the
        // leaf when the state changes.
        LowPowerModeToggleButton(controller: controller, localization: localization)
    }

    var showsDetailAffordance: Bool { hasDetails }
}

/// The leaf switch, split out so it observes the controller and re-renders when
/// the Low Power Mode state changes.
private struct LowPowerModeToggleButton: View {
    @ObservedObject var controller: LowPowerModeController
    let localization: Localization

    var body: some View {
        Button {
            controller.setLowPowerMode(!controller.isLowPowerMode)
        } label: {
            PanelActionGlyph(
                systemName: controller.isLowPowerMode ? "leaf.fill" : "leaf"
            )
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
        .frame(
            width: PanelSummaryActionMetrics.hitTarget,
            height: PanelSummaryActionMetrics.hitTarget
        )
    }
}
