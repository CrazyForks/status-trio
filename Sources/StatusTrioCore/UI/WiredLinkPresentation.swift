import Foundation

/// What the wired row and its panel call the link.
///
/// The port's name heads the row and the address does not: an address is the
/// reader's own business, and a menubar popover is a thing someone can read
/// over a shoulder. The address stays one deliberate tap away, in the panel.
@MainActor
enum WiredLinkPresentation {
    /// The port's own name when macOS reports one — "iPhone USB",
    /// "USB 10/100/1000 LAN" — and the generic wired label when it does not.
    static func title(_ details: PrimaryLinkDetails?, localization: Localization) -> String {
        nonEmpty(details?.interfaceDisplayName)
            ?? localization.string(.ethernetTitle)
    }

    /// The BSD name of the port — "en9". It is the name a reader matches
    /// against `ifconfig`, and it is not an address. Until the read names the
    /// interface, the row falls back to the state rather than to a blank line.
    static func subtitle(_ details: PrimaryLinkDetails?, localization: Localization) -> String {
        nonEmpty(details?.interfaceName)
            ?? localization.string(.ethernetSubtitleConnected)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
