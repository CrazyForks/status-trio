import SwiftUI

/// The network row while the primary connection is a cable.
///
/// The wired counterpart of `WiFiStatusView`: same slot, same affordances, and
/// the subtitle is the LAN address instead of a network name and signal.
struct EthernetStatusView: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var primaryLink: PrimaryLinkController
    let onOpenDetails: () -> Void
    let onOpenNetworkSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onOpenDetails()
            } label: {
                HStack(spacing: 10) {
                    EthernetStatusIcon()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.string(.ethernetTitle))
                            .font(.headline)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localization.string(.ethernetTitle))
            .accessibilityValue(subtitle)

            Button(
                localization.string(.ethernetActionOpenSettings),
                systemImage: "gearshape",
                action: onOpenNetworkSettings
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(localization.string(.ethernetActionOpenSettings))
            .frame(width: 24, height: 24)
        }
    }

    /// The address is the answer this row exists to give. Until the store has
    /// one — a cable that is up before DHCP answers — it falls back to the
    /// state, never to an address it does not have.
    private var subtitle: String {
        primaryLink.details?.displayAddress
            ?? localization.string(.ethernetSubtitleConnected)
    }
}

/// The wired counterpart of `WiFiStatusIcon`, sized for the same slot.
struct EthernetStatusIcon: View {
    var body: some View {
        Image(systemName: "cable.connector")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }
}
