// Status Trio — network link probe
//
// Runs the wired-link decision path against the live system, outside the app, so
// the answer to "why does the wired row show that" is data rather than a guess.
// It mirrors SystemWiredInterfaceProvider / NetworkServiceResolver /
// PrimaryLinkResolver; it is a diagnostic, not a test — the logic it copies is
// pinned by PrimaryLinkTests.
//
// Usage: swift scripts/probe-network-link.swift
//
// Run it before and after plugging a cable (or tethering a phone over USB) and
// compare. Section 1 answers whether the feature will appear at all, section 2
// which interface it will read, sections 3 and 4 what the panel will show.

import Foundation
import Network
import SystemConfiguration

final class Box<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ new: Value) { lock.lock(); value = new; lock.unlock() }
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func section(_ title: String) {
    print("\n" + String(repeating: "-", count: 72))
    print(title)
    print(String(repeating: "-", count: 72))
}

// MARK: - 1. NWPathMonitor — decides whether the wired row appears

section("1. NWPathMonitor — does the feature trigger?")

let monitor = NWPathMonitor()
let pathBox = Box<NWPath?>(nil)
monitor.pathUpdateHandler = { path in pathBox.set(path) }
monitor.start(queue: DispatchQueue(label: "probe.path"))
RunLoop.current.run(until: Date().addingTimeInterval(1.5))

if let path = pathBox.get() {
    print("  status                        = \(path.status)")
    print("  usesInterfaceType(.wired)     = \(path.usesInterfaceType(.wiredEthernet))   <- gates the row")
    print("  usesInterfaceType(.wifi)      = \(path.usesInterfaceType(.wifi))")
    print("  usesInterfaceType(.cellular)  = \(path.usesInterfaceType(.cellular))")
    print("  isExpensive / isConstrained   = \(path.isExpensive) / \(path.isConstrained)")
    print("  availableInterfaces:")
    for interface in path.availableInterfaces {
        print("      \(pad(interface.name, 8)) type=\(interface.type)")
    }
} else {
    print("  (no path update within 1.5s)")
}
monitor.cancel()

// MARK: - 2. SCNetworkInterfaceCopyAll — which interfaces count as wired

section("2. SCNetworkInterfaceCopyAll — which interfaces count as wired")

let ethernetType = kSCNetworkInterfaceTypeEthernet as String
let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
var wiredNames: [String] = []
for interface in interfaces {
    let name = (SCNetworkInterfaceGetBSDName(interface) as String?) ?? "-"
    let type = (SCNetworkInterfaceGetInterfaceType(interface) as String?) ?? "-"
    let display = (SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?) ?? "-"
    let isWired = type == ethernetType
    if isWired { wiredNames.append(name) }
    print("  \(pad(name, 7)) \(pad(type, 11)) \(isWired ? "WIRED" : "  -  ")  \(display)")
}
print("\n  -> wiredInterfaces = \(wiredNames)")

// MARK: - 3. SCDynamicStore — where the address comes from

section("3. SCDynamicStore — where the address comes from")

guard let store = SCDynamicStoreCreate(nil, "probe" as CFString, nil, nil),
      let allKeys = SCDynamicStoreCopyKeyList(store, "State:/Network/.*" as CFString) as? [String] else {
    print("  no SCDynamicStore")
    exit(1)
}

func value(_ key: String) -> [String: Any]? {
    SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
}

// The same keys SystemPrimaryLinkReader collects.
var snapshot: [String: [String: Any]] = [:]
for key in allKeys where key == "State:/Network/Global/IPv4" || key.hasPrefix("State:/Network/Service/") {
    if let dictionary = value(key) { snapshot[key] = dictionary }
}
print("  snapshot keys = \(snapshot.count) (reader scope)")

let global = snapshot["State:/Network/Global/IPv4"]
print("  Global/IPv4.PrimaryService   = \(global?["PrimaryService"] ?? "-")")
print("  Global/IPv4.PrimaryInterface = \(global?["PrimaryInterface"] ?? "-")")

let prefix = "State:/Network/Service/"
let serviceIDs = Array(Set(snapshot.keys.compactMap { key -> String? in
    guard key.hasPrefix(prefix) else { return nil }
    return key.dropFirst(prefix.count).split(separator: "/", maxSplits: 1).first.map(String.init)
})).sorted()

func string(_ dictionary: [String: Any]?, _ key: String) -> String? {
    dictionary?[key] as? String
}

func strings(_ dictionary: [String: Any]?, _ key: String) -> [String] {
    if let values = dictionary?[key] as? [String] { return values }
    if let single = dictionary?[key] as? String { return [single] }
    return []
}

print("\n  services:")
for id in serviceIDs {
    let base = prefix + id
    let ipv4 = snapshot[base + "/IPv4"]
    let ipv6 = snapshot[base + "/IPv6"]
    let subkeys = snapshot.keys.filter { $0.hasPrefix(base + "/") }
        .map { String($0.dropFirst(base.count + 1)) }.sorted()
    print("\n    \(id.prefix(8))...  subkeys=\(subkeys.joined(separator: ","))")
    print("        /Interface.DeviceName   = \(string(snapshot[base + "/Interface"], "DeviceName") ?? "**absent**")")
    print("        /IPv4.InterfaceName     = \(string(ipv4, "InterfaceName") ?? "-")   Confirmed=\(string(ipv4, "ConfirmedInterfaceName") ?? "-")")
    print("        /IPv6.InterfaceName     = \(string(ipv6, "InterfaceName") ?? "-")")
    let addresses = strings(ipv4, "Addresses")
    let dns = strings(snapshot[base + "/DNS"], "ServerAddresses")
    print("        /IPv4.Addresses         = \(addresses.isEmpty ? "(none)" : addresses.joined(separator: ", "))")
    print("        /IPv4.Router            = \(string(ipv4, "Router") ?? "-")")
    print("        /DNS.ServerAddresses    = \(dns.isEmpty ? "(none)" : dns.joined(separator: ", "))")
}

// Where the interface mapping lives, because the State: domain does not carry it.
let setup = SCDynamicStoreCopyKeyList(store, "Setup:/Network/Service/.*" as CFString) as? [String] ?? []
print("\n  keys ending in /Interface: State: \(allKeys.filter { $0.hasSuffix("/Interface") }.count), Setup: \(setup.filter { $0.hasSuffix("/Interface") }.count)")

// MARK: - 4. The resolver, walked end to end

section("4. Resolver result — what the row and panel will show")

func configuration(serviceID: String) -> (name: String?, legacy: String?, ipv4: [String], ipv6: [String], router: String?, dns: [String]) {
    let base = prefix + serviceID
    let ipv4 = snapshot[base + "/IPv4"]
    let ipv6 = snapshot[base + "/IPv6"]
    let legacy = string(snapshot[base + "/Interface"], "DeviceName")
    // Same order as NetworkServiceResolver.deviceName.
    let name = string(ipv4, "InterfaceName") ?? string(ipv6, "InterfaceName") ?? legacy
    return (
        name,
        legacy,
        strings(ipv4, "Addresses"),
        strings(ipv6, "Addresses"),
        string(ipv4, "Router"),
        strings(snapshot[base + "/DNS"], "ServerAddresses")
    )
}

func selectService(interface: String) -> String? {
    let candidates = serviceIDs.filter { id in
        let base = prefix + id
        return string(snapshot[base + "/Interface"], "DeviceName") == interface
            || string(snapshot[base + "/IPv4"], "InterfaceName") == interface
            || string(snapshot[base + "/IPv6"], "InterfaceName") == interface
    }
    if candidates.count == 1 { return candidates.first }
    if let primary = string(snapshot["State:/Network/Global/IPv4"], "PrimaryService"),
       candidates.contains(primary) { return primary }
    return nil
}

var resolved: (name: String?, legacy: String?, ipv4: [String], ipv6: [String], router: String?, dns: [String])?

if let primaryID = string(snapshot["State:/Network/Global/IPv4"], "PrimaryService") {
    let primary = configuration(serviceID: primaryID)
    print("  primary service interface name: current = \(primary.name ?? "**unreadable**")   legacy(/Interface.DeviceName) = \(primary.legacy ?? "unreadable")")
    if let name = primary.name, wiredNames.contains(name) {
        resolved = primary
        print("  -> branch A: the primary service is a wired interface")
    }
}
if resolved == nil {
    print("  branch A did not match (the primary service is not a wired interface)")
    for interface in wiredNames {
        guard let id = selectService(interface: interface) else { continue }
        resolved = configuration(serviceID: id)
        print("  -> branch B: fell back to \(interface)")
        break
    }
}

print("")
if let details = resolved {
    print("  PrimaryLinkDetails")
    print("      interface = \(details.name ?? "**unavailable**")")
    print("      IPv4      = \(details.ipv4.isEmpty ? "unavailable" : details.ipv4.joined(separator: ", "))")
    print("      IPv6      = \(details.ipv6.isEmpty ? "unavailable" : details.ipv6.joined(separator: ", "))")
    print("      router    = \(details.router ?? "unavailable")")
    print("      DNS       = \(details.dns.isEmpty ? "unavailable" : details.dns.joined(separator: ", "))")
    print("\n  -> row title = Ethernet, row subtitle = \(details.ipv4.first ?? details.ipv6.first ?? "\"Connected\" (no address)")")
} else {
    print("  PrimaryLinkDetails = nil")
    print("     -> no wired service in the snapshot; the panel would show Unavailable per row.")
    print("     -> if section 1 said wiredEthernet = true, that is a bug.")
}
print("")
