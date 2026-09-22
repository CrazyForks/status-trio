import AppKit
import SwiftUI

/// The network section of the popover.
///
/// One row whose subject is whatever carries the primary connection: the Wi-Fi
/// row while Wi-Fi is primary, the wired link's row while Ethernet is. Both open
/// a panel with the link's technical details, so the section answers "what am I
/// connected through, and with which address" for either cable.
struct NetworkStatusView: View {
    @ObservedObject var primaryLink: PrimaryLinkController
    let connection: NetworkConnection
    let wifi: WiFiStatus
    let isResolvingName: Bool
    let onOpenWiFiDetails: (Bool) -> Void
    let onOpenWiredDetails: () -> Void
    let onRequestNameAccess: () -> Void
    let onOpenWiFiSettings: () -> Void
    let onOpenNetworkSettings: () -> Void
    let onOpenLocationSettings: () -> Void

    var body: some View {
        if connection == .ethernet {
            EthernetStatusView(
                primaryLink: primaryLink,
                onOpenDetails: onOpenWiredDetails,
                onOpenNetworkSettings: onOpenNetworkSettings
            )
        } else {
            WiFiStatusView(
                wifi: wifi,
                connection: connection,
                isResolvingName: isResolvingName,
                onOpenDetails: onOpenWiFiDetails,
                onRequestNameAccess: onRequestNameAccess,
                onOpenWiFiSettings: onOpenWiFiSettings,
                onOpenLocationSettings: onOpenLocationSettings
            )
        }
    }
}
