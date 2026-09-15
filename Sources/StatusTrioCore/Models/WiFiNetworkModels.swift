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
        connectedBSSID: String?
    ) -> [WiFiNetwork] {
        let groups = Dictionary(grouping: candidates, by: \.identity)
        return groups.map { identity, values in
            WiFiNetwork(
                identity: identity,
                candidates: values.sorted(by: candidateComesFirst),
                connectedBSSID: connectedBSSID
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
