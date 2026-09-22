import Foundation

/// The address configuration of the wired link, as the popover reports it.
///
/// Resolved from the service that carries the wired interface rather than from
/// whatever holds the primary service, so a VPN tunnel claiming the primary
/// service does not turn the row into the tunnel's address. Every field may be
/// absent: a cable that is up before DHCP answers has an interface and no
/// address, and the row says so instead of inventing one.
struct PrimaryLinkDetails: Equatable, Sendable {
    let interfaceName: String?
    let ipv4Addresses: [String]
    let ipv6Addresses: [String]
    let router: String?
    let dnsServers: [String]

    init(
        interfaceName: String?,
        ipv4Addresses: [String],
        ipv6Addresses: [String],
        router: String?,
        dnsServers: [String]
    ) {
        self.interfaceName = interfaceName
        self.ipv4Addresses = ipv4Addresses
        self.ipv6Addresses = ipv6Addresses
        self.router = router
        self.dnsServers = dnsServers
    }

    init(configuration: NetworkServiceConfiguration) {
        self.init(
            interfaceName: configuration.interfaceName,
            ipv4Addresses: configuration.ipv4Addresses,
            ipv6Addresses: configuration.ipv6Addresses,
            router: configuration.router,
            dnsServers: configuration.dnsServers
        )
    }

    /// Nothing read yet, or nothing to read. The panel still draws its rows
    /// against this, so a link with no address reports Unavailable per row
    /// instead of vanishing.
    static let unavailable = Self(
        interfaceName: nil,
        ipv4Addresses: [],
        ipv6Addresses: [],
        router: nil,
        dnsServers: []
    )

    /// The address the row shows while the link is up. IPv4 first, because the
    /// question the row answers is the LAN address, and a link that has only an
    /// IPv6 address is still worth showing.
    var displayAddress: String? {
        if let ipv4 = ipv4Addresses.first, !ipv4.isEmpty { return ipv4 }
        return ipv6Addresses.first
    }
}

/// Picks the wired link out of a system configuration snapshot.
///
/// A pure function over the snapshot for the same reason
/// `NetworkServiceResolver` is: the interesting cases — a VPN holding the
/// primary service, a stale primary service, several Ethernet interfaces — are
/// all reachable in a test only if the system is behind a dictionary.
enum PrimaryLinkResolver {
    static func resolve(
        wiredInterfaces: [String],
        snapshot: [String: [String: Any]]
    ) -> PrimaryLinkDetails? {
        if let primary = NetworkServiceResolver.resolvePrimary(snapshot: snapshot),
           let name = primary.interfaceName,
           wiredInterfaces.contains(name) {
            return PrimaryLinkDetails(configuration: primary)
        }

        // The primary service is not the wired link. That is the ordinary case
        // while a VPN tunnel is up, and the momentary case right after a cable
        // comes up while Wi-Fi is still primary. Report the wired service.
        let wired = wiredInterfaces.compactMap { interface in
            NetworkServiceResolver.resolve(interface: interface, snapshot: snapshot)
        }
        guard let configuration = wired.first else {
            // Nothing in the snapshot belongs to an interface this Mac reports
            // as Ethernet. An address from another link would be worse than no
            // address, so the row goes without one.
            return nil
        }
        return PrimaryLinkDetails(configuration: configuration)
    }
}
