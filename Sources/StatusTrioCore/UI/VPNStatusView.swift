import SwiftUI

/// The VPN summary row.
///
/// Icon, title and subtitle, the same shape as the battery and Wi-Fi rows. What
/// it deliberately does not have is their button: this row has nowhere to go.
/// macOS keeps VPN services inside the Network pane's service list rather than
/// giving them a Settings pane of their own, so a gear here would open the
/// wrong page — see the pane-route rule in AGENTS.md.
struct VPNStatusView: View {
    @EnvironmentObject private var localization: Localization
    let vpn: VPNStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(symbolColor)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(StatusPresentation.vpnTitle(vpn, localization: localization))
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localization.string(.vpnTitle))
        .accessibilityValue(
            "\(StatusPresentation.vpnTitle(vpn, localization: localization)), \(subtitle)"
        )
    }

    private var subtitle: String {
        StatusPresentation.vpnSubtitle(vpn, localization: localization)
    }

    /// Filled only for a tunnel: a proxy is a weaker signal and keeps the
    /// outline symbol, which is why the two are also coloured differently.
    private var symbolName: String {
        vpn.isTunnelConnected ? "lock.shield.fill" : "lock.shield"
    }

    private var symbolColor: Color {
        if vpn.isTunnelConnected { return .green }
        if vpn.proxy != nil { return .orange }
        return .secondary
    }
}
