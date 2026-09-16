import Foundation

struct BatteryStatus: Equatable, Sendable {
    let rawPercentage: Int?
    let isPresent: Bool
    let isCharging: Bool
    let isCharged: Bool
    let timeToFullChargeMinutes: Int?
    let isLowPowerMode: Bool
    let isConnectedToPower: Bool

    init(
        rawPercentage: Int?,
        isPresent: Bool,
        isCharging: Bool,
        isCharged: Bool = false,
        timeToFullChargeMinutes: Int? = nil,
        isLowPowerMode: Bool,
        isConnectedToPower: Bool
    ) {
        self.rawPercentage = rawPercentage
        self.isPresent = isPresent
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.timeToFullChargeMinutes = timeToFullChargeMinutes
        self.isLowPowerMode = isLowPowerMode
        self.isConnectedToPower = isConnectedToPower
    }

    var percentage: Int {
        guard isPresent else { return 100 }
        let value = rawPercentage ?? 100
        return min(100, max(0, value))
    }

    static let placeholder = BatteryStatus(
        rawPercentage: 100,
        isPresent: true,
        isCharging: false,
        isLowPowerMode: false,
        isConnectedToPower: false
    )
}

enum WiFiState: Equatable, Sendable {
    case connected
    case notAssociated
    case off
    case noInternet
    case hotspot
    case temporary
    case shared
    case unavailable

    var isNetworkAssociated: Bool {
        switch self {
        case .connected, .noInternet, .hotspot, .temporary, .shared:
            true
        case .notAssociated, .off, .unavailable:
            false
        }
    }
}

enum WiFiNameAccess: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

struct WiFiStatus: Equatable, Sendable {
    let state: WiFiState
    let rssi: Int?
    let ssid: String?
    let nameAccess: WiFiNameAccess

    init(
        state: WiFiState,
        rssi: Int?,
        ssid: String? = nil,
        nameAccess: WiFiNameAccess = .notDetermined
    ) {
        self.state = state
        self.rssi = rssi
        self.ssid = ssid
        self.nameAccess = nameAccess
    }

    static let placeholder = WiFiStatus(state: .unavailable, rssi: nil)
}

extension WiFiStatus {
    /// True while a network name is expected but not known yet: the popover shows
    /// no subtitle until the fresh read delivers the name, instead of flashing the
    /// generic state text first.
    var isAwaitingName: Bool {
        state.isNetworkAssociated
            && nameAccess == .authorized
            && (ssid ?? "").isEmpty
    }
}

struct VolumeStatus: Equatable, Sendable {
    let scalar: Double?
    let isMuted: Bool
    let deviceName: String?
    let outputDevices: [AudioOutputDevice]

    init(
        scalar: Double?,
        isMuted: Bool,
        deviceName: String?,
        outputDevices: [AudioOutputDevice] = []
    ) {
        self.scalar = scalar
        self.isMuted = isMuted
        self.deviceName = deviceName
        self.outputDevices = outputDevices
    }

    static let placeholder = VolumeStatus(
        scalar: nil,
        isMuted: false,
        deviceName: nil
    )
}

struct StatusSnapshot: Equatable, Sendable {
    let battery: BatteryStatus
    let wifi: WiFiStatus
    let connection: NetworkConnection
    let volume: VolumeStatus

    init(
        battery: BatteryStatus,
        wifi: WiFiStatus,
        connection: NetworkConnection = .unknown,
        volume: VolumeStatus
    ) {
        self.battery = battery
        self.wifi = wifi
        self.connection = connection
        self.volume = volume
    }

    static let placeholder = StatusSnapshot(
        battery: .placeholder,
        wifi: .placeholder,
        volume: .placeholder
    )
}
