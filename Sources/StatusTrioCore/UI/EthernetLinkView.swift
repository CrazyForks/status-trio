import SwiftUI

/// The wired link's detail panel.
///
/// Unlike the Wi-Fi page there is nothing to join or switch here: which wired
/// network a cable reaches is a cabling job and, for anything macOS has to be
/// told about, a System Settings one. The panel is therefore the link's
/// addresses and the way to the Network pane, and nothing else.
struct EthernetLinkView: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var primaryLink: PrimaryLinkController
    let onBack: () -> Void
    let onOpenNetworkSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationBackRow(
                accessibilityLabel: localization.string(.commonBack),
                title: localization.string(.ethernetTitle),
                action: onBack
            )

            // The same five rows whichever way the read went: a row the link
            // cannot report says Unavailable, so the panel never shrinks to a
            // state line that leaves the reader wondering what is missing.
            LinkDetailsList(
                rows: LinkDetailPresentation.wiredRows(primaryLink.details ?? .unavailable)
            )
            .padding(.leading, 26)
            .font(.caption)

            Divider()
            Button(localization.string(.ethernetActionOpenSettings), action: onOpenNetworkSettings)
                .buttonStyle(.plain)
        }
    }
}
