import Foundation

/// A security classification deliberately derived from CoreWLAN's stable raw
/// values. Keeping it independent from `CWSecurity` makes scan results safe to
/// cross the serial CoreWLAN worker boundary.
enum WiFiSecurityKind: Int, CaseIterable, Equatable, Hashable, Sendable {
    case unknown = -1
    case open = 0
    case wep = 1
    case wpaPersonal = 2
    case wpaPersonalMixed = 3
    case wpa2Personal = 4
    case personal = 5
    case dynamicWEP = 6
    case wpaEnterprise = 7
    case wpaEnterpriseMixed = 8
    case wpa2Enterprise = 9
    case enterprise = 10
    case wpa3Personal = 11
    case wpa3Enterprise = 12
    case wpa3Transition = 13
    case owe = 14
    case oweTransition = 15

    init(coreWLANRawValue: Int) {
        self = Self(rawValue: coreWLANRawValue) ?? .unknown
    }

    var requiresPassword: Bool {
        self != .open && self != .owe && self != .oweTransition && self != .unknown
    }

    var isEnterprise: Bool {
        switch self {
        case .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise, .wpa3Enterprise:
            true
        default:
            false
        }
    }
}

struct WiFiNetworkIdentity: Equatable, Hashable, Sendable {
    /// This is intentionally the unmodified SSID returned by CoreWLAN. In
    /// particular, leading/trailing whitespace is a part of an SSID identity.
    let ssid: String
    let security: WiFiSecurityKind
}

struct WiFiNetworkCandidate: Equatable, Hashable, Sendable {
    let identity: WiFiNetworkIdentity
    let bssid: String?
    let rssi: Int?
    let channel: Int?
    let security: WiFiSecurityKind

    init(
        ssid: String,
        bssid: String?,
        rssi: Int?,
        channel: Int?,
        security: WiFiSecurityKind
    ) {
        identity = WiFiNetworkIdentity(ssid: ssid, security: security)
        self.bssid = bssid
        self.rssi = rssi
        self.channel = channel
        self.security = security
    }
}

struct WiFiNetwork: Identifiable, Equatable, Sendable {
    let identity: WiFiNetworkIdentity
    let candidates: [WiFiNetworkCandidate]
    let connectedBSSID: String?
    let isKnown: Bool

    init(
        identity: WiFiNetworkIdentity,
        candidates: [WiFiNetworkCandidate],
        connectedBSSID: String?,
        isKnown: Bool = false
    ) {
        self.identity = identity
        self.candidates = candidates
        self.connectedBSSID = connectedBSSID
        self.isKnown = isKnown
    }

    var id: WiFiNetworkIdentity { identity }
    var ssid: String { identity.ssid }
    var security: WiFiSecurityKind { identity.security }

    /// The selected candidate is presentation-only. The associated AP always
    /// comes from `WiFiConnectionDetails`, never from this strongest candidate.
    var preferredCandidate: WiFiNetworkCandidate? {
        candidates.sorted(by: Self.candidateComesFirst).first
    }

    var isConnected: Bool {
        guard let connectedBSSID else { return false }
        return candidates.contains { candidate in
            guard let candidateBSSID = candidate.bssid else { return false }
            return candidateBSSID.caseInsensitiveCompare(connectedBSSID) == .orderedSame
        }
    }

    var rssi: Int? { preferredCandidate?.rssi }

    static func merge(
        _ candidates: [WiFiNetworkCandidate],
        connectedBSSID: String?,
        knownSSIDs: Set<String> = []
    ) -> [WiFiNetwork] {
        let groups = Dictionary(grouping: candidates, by: \.identity)
        return groups.map { identity, values in
            WiFiNetwork(
                identity: identity,
                candidates: values.sorted(by: candidateComesFirst),
                connectedBSSID: connectedBSSID,
                isKnown: knownSSIDs.contains(identity.ssid)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
            let leftRSSI = lhs.rssi ?? Int.min
            let rightRSSI = rhs.rssi ?? Int.min
            if leftRSSI != rightRSSI { return leftRSSI > rightRSSI }
            if lhs.ssid != rhs.ssid { return lhs.ssid.localizedCaseInsensitiveCompare(rhs.ssid) == .orderedAscending }
            return lhs.security.rawValue < rhs.security.rawValue
        }
    }

    private static func candidateComesFirst(
        _ lhs: WiFiNetworkCandidate,
        _ rhs: WiFiNetworkCandidate
    ) -> Bool {
        let leftRSSI = lhs.rssi ?? Int.min
        let rightRSSI = rhs.rssi ?? Int.min
        if leftRSSI != rightRSSI { return leftRSSI > rightRSSI }
        return (lhs.bssid ?? "") < (rhs.bssid ?? "")
    }
}

enum WiFiNetworkRowAction: Equatable, Sendable {
    case none
    case connect
    case openSettings
}

enum WiFiNetworkPresentation {
    static func grouped(
        _ networks: [WiFiNetwork]
    ) -> (known: [WiFiNetwork], other: [WiFiNetwork]) {
        (
            known: networks.filter { $0.isKnown || $0.isConnected },
            other: networks.filter { !$0.isKnown && !$0.isConnected }
        )
    }

    static func action(for network: WiFiNetwork) -> WiFiNetworkRowAction {
        if network.isConnected { return .none }
        return network.isKnown ? .openSettings : .connect
    }

    /// The details row names the action it performs, so its caption and its
    /// accessibility label both flip once the details are open.
    static func detailsToggleTitleKey(isExpanded: Bool) -> LocalizationKey {
        isExpanded ? .wifiDetailsHide : .wifiDetailsShow
    }

    static func detailsToggleSymbol(isExpanded: Bool) -> String {
        isExpanded ? "chevron.up" : "info.circle"
    }
}

struct WiFiConnectionDetails: Equatable, Sendable {
    let ssid: String?
    let bssid: String?
    let band: String?
    let channel: Int?
    let channelWidth: String?
    let rssi: Int?
    let noise: Int?
    let phyMode: String?
    let transmitRateMbps: Double?
    let security: WiFiSecurityKind
    let countryCode: String?
    let interfaceName: String?
    let ipv4Addresses: [String]
    let ipv6Addresses: [String]
    let router: String?
    let dnsServers: [String]

    var signalToNoiseRatio: Int? {
        guard let rssi, let noise, rssi < 0, noise < 0, rssi >= noise else { return nil }
        return rssi - noise
    }

    static let unavailable = WiFiConnectionDetails(
        ssid: nil,
        bssid: nil,
        band: nil,
        channel: nil,
        channelWidth: nil,
        rssi: nil,
        noise: nil,
        phyMode: nil,
        transmitRateMbps: nil,
        security: .unknown,
        countryCode: nil,
        interfaceName: nil,
        ipv4Addresses: [],
        ipv6Addresses: [],
        router: nil,
        dnsServers: []
    )
}

enum WiFiCredentialSource: Equatable, Sendable {
    case appKeychain
    case systemKeychain
}

enum WiFiCredentialIssue: Equatable, Sendable {
    case cancelled
    case accessDenied
    case keychainLocked
    case readFailed
    case saveFailed
}

enum WiFiCredentialResult: Equatable, Sendable {
    case credential(String, WiFiCredentialSource)
    case noCredential
    case issue(WiFiCredentialIssue)
}

enum WiFiListState: Equatable, Sendable {
    case idle
    case scanning
    case ready
    case poweredOff
    case noInterface
    case permissionDenied
    case failed
    case resolvingCredentials
    case needsPassword
    case credentialAccessCancelled
    case credentialAccessDenied
    case credentialStoreLocked
    case credentialReadFailed
    case connecting(WiFiNetworkIdentity)
    case connectionFailed
    case connectionTimedOut
    case networkUnavailable
    case enterpriseNetwork

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }

    var isConnectionFlow: Bool {
        switch self {
        case .resolvingCredentials, .needsPassword, .connecting:
            true
        default:
            false
        }
    }
}

struct AsyncRequestGate: Sendable {
    private(set) var current: UInt64 = 0

    mutating func advance() -> UInt64 {
        current &+= 1
        return current
    }

    func accepts(_ request: UInt64) -> Bool {
        request == current
    }
}

enum BluetoothAvailability: Equatable, Sendable {
    case idle
    case initializing
    case authorizationNotDetermined
    case authorizationDenied
    case authorizationRestricted
    case available
    case poweredOff
    case unavailable
    case failed
}

enum BluetoothAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case allowed
    case denied
    case restricted
}

enum BluetoothManagerState: Equatable, Sendable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

enum BluetoothAvailabilityMapper {
    static func preliminary(
        authorization: BluetoothAuthorizationStatus,
        managerState: BluetoothManagerState
    ) -> BluetoothAvailability {
        switch authorization {
        case .denied:
            return .authorizationDenied
        case .restricted:
            return .authorizationRestricted
        case .notDetermined:
            return .authorizationNotDetermined
        case .allowed:
            switch managerState {
            case .unknown, .resetting:
                return .initializing
            case .unsupported:
                return .unavailable
            case .unauthorized:
                return .authorizationDenied
            case .poweredOff:
                return .poweredOff
            case .poweredOn:
                return .available
            }
        }
    }
}

enum BluetoothDeviceKind: Equatable, Sendable {
    case computer
    case phone
    case audio
    case peripheral
    case unknown
}

struct BluetoothDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let kind: BluetoothDeviceKind
    let isConnected: Bool

    /// AirPods are identified by name. The audio class alone would also match
    /// speakers and other headphones, and macOS exposes no reliable model
    /// table for registry product IDs; every AirPods name contains "AirPods".
    var isAirPods: Bool {
        kind == .audio && name.lowercased().contains("airpods")
    }

    /// Whether the popover summary may report this device's battery level.
    var isAirPodsSummaryCandidate: Bool {
        isConnected && isAirPods
    }
}

/// What the popover's Bluetooth row reports. Deriving the text from state
/// keeps the summary testable without rendering SwiftUI.
enum BluetoothSummary: Equatable, Sendable {
    case requestAuthorization
    case initializing
    case authorizationDenied
    case authorizationRestricted
    case poweredOff
    case unavailable
    case readFailed
    case noConnectedDevices
    /// The joined device names, and whether any of them is an AirPods whose
    /// level the summary reports. Reading levels launches a `system_profiler`
    /// subprocess, so callers gate it on that flag.
    case devices(String, hasAirPods: Bool)

    var deviceNames: String? {
        guard case .devices(let names, _) = self else { return nil }
        return names
    }

    var hasConnectedAirPods: Bool {
        guard case .devices(_, let hasAirPods) = self else { return false }
        return hasAirPods
    }

    static func presentation(
        availability: BluetoothAvailability,
        devices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel]
    ) -> BluetoothSummary {
        switch availability {
        case .authorizationNotDetermined:
            return .requestAuthorization
        case .authorizationDenied:
            return .authorizationDenied
        case .authorizationRestricted:
            return .authorizationRestricted
        case .poweredOff:
            return .poweredOff
        case .unavailable:
            return .unavailable
        case .failed:
            return .readFailed
        // An idle controller has not read anything yet; saying so would only
        // repeat the initializing state it is about to enter.
        case .idle, .initializing:
            return .initializing
        case .available:
            let connected = BluetoothDevicePresentation.grouped(devices).connected
            guard !connected.isEmpty else { return .noConnectedDevices }
            let names = connected.map { entry(for: $0, batteryLevels: batteryLevels) }
                .joined(separator: "、")
            return .devices(names, hasAirPods: connected.contains { $0.isAirPodsSummaryCandidate })
        }
    }

    private static func entry(
        for device: BluetoothDevice,
        batteryLevels: [String: BluetoothBatteryLevel]
    ) -> String {
        guard device.isAirPodsSummaryCandidate else { return device.name }
        let address = BluetoothBatteryReader.normalizedAddress(device.id)
        guard let summary = batteryLevels[address]?.summary else { return device.name }
        // The middle dot marks the level as a property of this device, while
        // the ideographic comma above separates devices from each other.
        return "\(device.name) · \(summary)"
    }
}

/// Starting the Bluetooth state monitor is what raises the system permission
/// prompt, so the popover may only activate an app that already has the grant.
enum BluetoothPanelActivation {
    static func shouldActivate(authorization: BluetoothAuthorizationStatus) -> Bool {
        authorization == .allowed
    }
}

enum BluetoothDevicePresentation {
    static func grouped(_ devices: [BluetoothDevice]) -> (connected: [BluetoothDevice], disconnected: [BluetoothDevice]) {
        let sorted = devices.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return (
            sorted.filter(\.isConnected),
            sorted.filter { !$0.isConnected }
        )
    }
}
