import Foundation

/// The address configuration of one network service in the system
/// configuration store.
struct NetworkServiceConfiguration: Equatable, Sendable {
    let interfaceName: String?
    let ipv4Addresses: [String]
    let ipv6Addresses: [String]
    let router: String?
    let dnsServers: [String]

    static let unavailable = Self(
        interfaceName: nil,
        ipv4Addresses: [],
        ipv6Addresses: [],
        router: nil,
        dnsServers: []
    )
}

/// Selects a network service out of a `SCDynamicStore` snapshot.
///
/// The store is handed in as a plain dictionary so the selection rules stay a
/// pure function: the Wi-Fi link details and the wired link details both
/// resolve through here, and a test can supply the exact snapshot it means to
/// pin down without a live system.
enum NetworkServiceResolver {
    private static let servicePrefix = "State:/Network/Service/"
    private static let globalIPv4Key = "State:/Network/Global/IPv4"

    /// The service that carries a given BSD interface.
    ///
    /// Returns `nil` when the snapshot holds no service for the interface, or
    /// when several do and none of them is the primary service: an ambiguous
    /// match is not a guess worth making, because the addresses on the wrong
    /// service belong to a different link.
    static func resolve(
        interface: String,
        snapshot: [String: [String: Any]]
    ) -> NetworkServiceConfiguration? {
        guard let serviceID = selectService(interface: interface, snapshot: snapshot) else {
            return nil
        }
        return configuration(serviceID: serviceID, snapshot: snapshot)
    }

    /// The service the system is currently using for IPv4.
    ///
    /// While a VPN tunnel is up it claims the primary service, so this is the
    /// tunnel and not the physical link underneath it.
    static func resolvePrimary(
        snapshot: [String: [String: Any]]
    ) -> NetworkServiceConfiguration? {
        guard let primary = string(snapshot[globalIPv4Key], key: "PrimaryService") else {
            return nil
        }
        let base = servicePrefix + primary
        // A primary service that left no trace in the snapshot is not a service
        // this read can describe; reporting empty addresses for it would look
        // like a link with no address rather than a missing one.
        guard snapshot[base + "/Interface"] != nil
                || snapshot[base + "/IPv4"] != nil
                || snapshot[base + "/IPv6"] != nil else {
            return nil
        }
        return configuration(serviceID: primary, snapshot: snapshot)
    }

    private static func selectService(
        interface: String,
        snapshot: [String: [String: Any]]
    ) -> String? {
        let serviceIDs = Set(snapshot.keys.compactMap { key -> String? in
            guard key.hasPrefix(servicePrefix) else { return nil }
            return key.dropFirst(servicePrefix.count)
                .split(separator: "/", maxSplits: 1)
                .first
                .map(String.init)
        })
        let candidates = serviceIDs.filter { serviceID in
            let base = servicePrefix + serviceID
            return string(snapshot[base + "/Interface"], key: "DeviceName") == interface
                || string(snapshot[base + "/IPv4"], key: "InterfaceName") == interface
                || string(snapshot[base + "/IPv6"], key: "InterfaceName") == interface
        }
        if candidates.count == 1 { return candidates.first }
        let primary = string(snapshot[globalIPv4Key], key: "PrimaryService")
        if let primary, candidates.contains(primary) { return primary }
        return nil
    }

    private static func configuration(
        serviceID: String,
        snapshot: [String: [String: Any]]
    ) -> NetworkServiceConfiguration {
        let base = servicePrefix + serviceID
        let ipv4 = snapshot[base + "/IPv4"]
        let ipv6 = snapshot[base + "/IPv6"]
        let dns = snapshot[base + "/DNS"]
        return NetworkServiceConfiguration(
            interfaceName: deviceName(ipv4: ipv4, ipv6: ipv6, service: snapshot[base + "/Interface"]),
            ipv4Addresses: strings(ipv4, key: "Addresses"),
            ipv6Addresses: strings(ipv6, key: "Addresses"),
            router: string(ipv4, key: "Router"),
            dnsServers: strings(dns, key: "ServerAddresses")
        )
    }

    private static func string(_ dictionary: [String: Any]?, key: String) -> String? {
        dictionary?[key] as? String
    }

    /// The BSD interface a service is configured on.
    ///
    /// The address dictionaries carry the name on macOS 27 (verified on a live
    /// system: `IPv4.InterfaceName` and `IPv4.ConfirmedInterfaceName` are both
    /// present for the primary service). The
    /// `State:/Network/Service/<id>/Interface` dictionary that this read used to
    /// rely on is not published at all any more — the same mapping now lives
    /// under `Setup:/Network/Service/<id>/Interface`, a domain this snapshot
    /// does not collect. Reading the name off the addresses is what keeps the
    /// wired row's Interface line and `PrimaryLinkResolver`'s "is the primary
    /// service the wired link" check working; the old key stays last so a system
    /// that still publishes it resolves the same way.
    private static func deviceName(
        ipv4: [String: Any]?,
        ipv6: [String: Any]?,
        service: [String: Any]?
    ) -> String? {
        string(ipv4, key: "InterfaceName")
            ?? string(ipv6, key: "InterfaceName")
            ?? string(service, key: "DeviceName")
    }

    private static func strings(_ dictionary: [String: Any]?, key: String) -> [String] {
        if let values = dictionary?[key] as? [String] { return values }
        if let value = dictionary?[key] as? String { return [value] }
        return []
    }
}
