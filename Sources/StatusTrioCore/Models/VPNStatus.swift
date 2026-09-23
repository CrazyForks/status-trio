import Darwin
import Foundation

/// A system-wide proxy configuration, as `State:/Network/Global/Proxies`
/// reports it.
///
/// A proxy is deliberately a separate signal from a tunnel: nothing is routed
/// through a virtual interface and the machine gains no new address, so a
/// proxied machine is not "on a VPN" in the sense the first signal measures.
/// The row reports it anyway — a user who turned a proxy on wants to see that
/// traffic is being relayed — but the two stay distinguishable in the model so
/// the presentation can lead with whichever one is up.
struct VPNProxyStatus: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case http
        case https
        case socks
        /// A proxy auto-configuration script rather than a fixed endpoint.
        case automaticConfiguration
    }

    let kind: Kind
    let host: String?
    let port: Int?

    /// `127.0.0.1:10808`, the bare host when no port was set, or `nil` for a
    /// PAC-driven proxy: a script URL is not an endpoint the row can print.
    var endpoint: String? {
        guard kind != .automaticConfiguration else { return nil }
        guard let host, !host.isEmpty else { return nil }
        guard let port else { return host }
        return "\(host):\(port)"
    }
}

/// What the VPN row reports.
///
/// Three signals feed it: tunnel interfaces, system VPN services, and the
/// system-wide proxy. The first two mean the same thing to a user ("traffic
/// goes through a tunnel"), which is why they share `isTunnelConnected`; the
/// proxy is weaker and only shows up in `isActive`.
struct VPNStatus: Equatable, Sendable {
    /// Tunnel interfaces that are up and carry a routable address
    /// (`utun4`, `ppp0`, …), sorted so the value is stable across reads.
    let tunnelInterfaces: [String]
    /// The name of the connected system VPN service, when one is up.
    let serviceName: String?
    /// The active system-wide proxy, when one is configured.
    let proxy: VPNProxyStatus?

    static let placeholder = VPNStatus(
        tunnelInterfaces: [],
        serviceName: nil,
        proxy: nil
    )

    /// True when traffic is going through a tunnel or a system VPN service.
    var isTunnelConnected: Bool {
        !tunnelInterfaces.isEmpty || serviceName != nil
    }

    /// True when there is anything at all to report, tunnel or proxy.
    var isActive: Bool {
        isTunnelConnected || proxy != nil
    }
}

/// A system VPN service and whether it reports itself connected.
struct VPNServiceReading: Equatable, Sendable {
    let name: String
    let isConnected: Bool
}

/// One raw reading of the three signals, before any rule is applied.
///
/// Splitting the reading from the rules keeps every decision testable without a
/// live system: the readers do I/O and nothing else, and `VPNStatusResolver`
/// turns their output into the row's value.
struct VPNProbeReading: Equatable, Sendable {
    var tunnelInterfaces: [String] = []
    var services: [VPNServiceReading] = []
    var proxy: VPNProxyStatus?

    static let empty = VPNProbeReading()
}

enum VPNStatusResolver {
    static func resolve(_ reading: VPNProbeReading) -> VPNStatus {
        VPNStatus(
            tunnelInterfaces: reading.tunnelInterfaces.sorted(),
            serviceName: reading.services.first { $0.isConnected }?.name,
            proxy: reading.proxy
        )
    }
}

/// Decides which interfaces count as a tunnel.
enum TunnelInterfaceClassifier {
    /// Interface name prefixes that carry a tunnel rather than a physical link.
    /// `utun` covers the built-in and third-party VPN clients on macOS 15 and
    /// later; the rest are the older point-to-point names a system VPN service
    /// can still create.
    static let namePrefixes = ["utun", "ppp", "ipsec", "tap", "tun"]

    static func isTunnelInterface(_ name: String) -> Bool {
        namePrefixes.contains { name.hasPrefix($0) }
    }

    /// A tunnel counts as connected only when it is up *and* holds a routable
    /// IPv4 address.
    ///
    /// The address test is what keeps macOS's own tunnels out of the result.
    /// Measured on macOS 26.6.1: `utun0`–`utun3` (Back to My Mac and
    /// Continuity) are all `UP,RUNNING` with an empty IPv4 list, while a VPN
    /// that is actually carrying traffic has an address on its `utun`. A
    /// hard-coded list of system interface names would have to be maintained on
    /// every macOS release and would still miss a new one; the address is the
    /// property that separates a tunnel carrying traffic from a tunnel that is
    /// merely present.
    static func isActiveTunnel(flags: UInt32, ipv4Addresses: [String]) -> Bool {
        guard flags & UInt32(IFF_UP) != 0 else { return false }
        return ipv4Addresses.contains { !isLinkLocal($0) }
    }

    /// `169.254.0.0/16`, which an interface assigns itself when DHCP fails. An
    /// interface holding only a link-local address is not carrying traffic.
    static func isLinkLocal(_ address: String) -> Bool {
        address.hasPrefix("169.254.")
    }
}
