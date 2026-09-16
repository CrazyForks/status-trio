import AppKit
import SwiftUI

struct WiFiStatusView: View {
    @EnvironmentObject private var localization: Localization
    let wifi: WiFiStatus
    var isResolvingName: Bool = false
    let onOpenDetails: (Bool) -> Void
    let onRequestNameAccess: () -> Void
    let onOpenWiFiSettings: () -> Void
    let onOpenLocationSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                switch StatusMappings.wifiSummaryAction(for: wifi) {
                case .openDetails:
                    onOpenDetails(NSEvent.modifierFlags.contains(.option))
                case .requestNameAccess:
                    onRequestNameAccess()
                case .openLocationSettings:
                    onOpenLocationSettings()
                }
            } label: {
                HStack(spacing: 10) {
                    WiFiStatusIcon(wifi: wifi)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.string(.wifiTitle))
                            .font(.headline)
                        subtitle
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(wifiAccessibilityLabel)

            Button(
                localization.string(.wifiActionOpenSettings),
                systemImage: "gearshape",
                action: onOpenWiFiSettings
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(localization.string(.wifiActionOpenSettings))
            .frame(width: 24, height: 24)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if let ssid = wifi.ssid, !ssid.isEmpty {
            Text(ssid)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if isResolvingName {
            // The fresh name is still being read: keep the line empty instead of
            // flashing the generic state, and keep its height so the row does not jump.
            Text(verbatim: " ")
                .font(.caption)
                .accessibilityHidden(true)
        } else if wifi.state.isNetworkAssociated && wifi.nameAccess == .notDetermined {
            Button(localization.string(.wifiActionRequestNameAccess), action: onRequestNameAccess)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if wifi.state.isNetworkAssociated
                    && (wifi.nameAccess == .denied || wifi.nameAccess == .restricted) {
            Button(localization.string(.wifiActionOpenLocationSettings), action: onOpenLocationSettings)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text(StatusPresentation.wifiSubtitle(wifi, localization: localization))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var wifiAccessibilityLabel: String {
        if let ssid = wifi.ssid, !ssid.isEmpty {
            return localization.format(.wifiAccessibilityWithSSID, ssid, StatusPresentation.wifiValue(wifi, localization: localization))
        }
        return localization.format(.commonLabelValue, localization.string(.wifiTitle), StatusPresentation.wifiValue(wifi, localization: localization))
    }
}
