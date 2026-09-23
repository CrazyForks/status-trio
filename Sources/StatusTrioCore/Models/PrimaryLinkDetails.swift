import Foundation

/// The address configuration of the wired link, as the popover reports it.
///
/// Resolved from the service that carries the wired interface rather than from
/// whatever holds the primary service, so a VPN tunnel claiming the primary
/// service does not turn the row into the tunnel's address. Every field may be
/// absent: a cable that is up before DHCP answers has an interface and no
/// address, and the panel says so per row instead of inventing one.
struct PrimaryLinkDetails: Equatable, Sendable {
    let interfaceName: String?
    /// What macOS calls the port — "iPhone USB", "USB 10/100/1000 LAN" — read
    /// off the interface, not off the service: the service is keyed by a BSD
    /// name, and a BSD name is not a heading. Absent on a system that reports
    /// only the BSD name, and the row falls back to the generic wired label.
    let interfaceDisplayName: String?
    let ipv4Addresses: [String]
    let ipv6Addresses: [String]
    let router: String?
    let dnsServers: [String]

    init(
        interfaceName: String?,
        interfaceDisplayName: String? = nil,
        ipv4Addresses: [String],
        ipv6Addresses: [String],
        router: String?,
        dnsServers: [String]
    ) {
        self.interfaceName = interfaceName
        self.interfaceDisplayName = interfaceDisplayName
        self.ipv4Addresses = ipv4Addresses
        self.ipv6Addresses = ipv6Addresses
        self.router = router
        self.dnsServers = dnsServers
    }

    init(configuration: NetworkServiceConfiguration, interfaceDisplayName: String?) {
        self.init(
            interfaceName: configuration.interfaceName,
            interfaceDisplayName: interfaceDisplayName,
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
}

/// Picks the wired link out of a system configuration snapshot.
///
/// A pure function over the snapshot for the same reason
/// `NetworkServiceResolver` is: the interesting cases — a VPN holding the
/// primary service, a stale primary service, several Ethernet interfaces — are
/// all reachable in a test only if the system is behind a dictionary.
enum PrimaryLinkResolver {
    static func resolve(
        wiredInterfaces: [WiredInterface],
        snapshot: [String: [String: Any]]
    ) -> PrimaryLinkDetails? {
        if let primary = NetworkServiceResolver.resolvePrimary(snapshot: snapshot),
           let name = primary.interfaceName,
           let matched = wiredInterfaces.first(where: { $0.name == name }) {
            return PrimaryLinkDetails(
                configuration: primary,
                interfaceDisplayName: matched.displayName
            )
        }

        // The primary service is not the wired link. That is the ordinary case
        // while a VPN tunnel is up, and the momentary case right after a cable
        // comes up while Wi-Fi is still primary. Report the wired service.
        let wired = wiredInterfaces.compactMap { interface -> PrimaryLinkDetails? in
            guard let configuration = NetworkServiceResolver.resolve(
                interface: interface.name,
                snapshot: snapshot
            ) else { return nil }
            return PrimaryLinkDetails(
                configuration: configuration,
                interfaceDisplayName: interface.displayName
            )
        }
        // Nothing in the snapshot belongs to an interface this Mac reports as
        // Ethernet. An address from another link would be worse than no
        // address, so the row goes without one.
        return wired.first
    }
}
