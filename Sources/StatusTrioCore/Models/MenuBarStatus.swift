import Foundation

struct MenuBarVolumeStatus: Equatable, Sendable {
    let scalar: Double?
    let isMuted: Bool
    let deviceName: String?

    init(scalar: Double?, isMuted: Bool, deviceName: String?) {
        self.scalar = scalar
        self.isMuted = isMuted
        self.deviceName = deviceName
    }

    init(volume: VolumeStatus) {
        self.init(
            scalar: volume.scalar,
            isMuted: volume.isMuted,
            deviceName: volume.deviceName
        )
    }
}

struct MenuBarStatus: Equatable, Sendable {
    let battery: BatteryStatus
    let wifi: WiFiStatus
    let connection: NetworkConnection
    let volume: MenuBarVolumeStatus

    init(
        battery: BatteryStatus,
        wifi: WiFiStatus,
        connection: NetworkConnection,
        volume: MenuBarVolumeStatus
    ) {
        self.battery = battery
        self.wifi = wifi
        self.connection = connection
        self.volume = volume
    }

    init(snapshot: StatusSnapshot) {
        self.init(
            battery: snapshot.battery,
            wifi: snapshot.wifi,
            connection: snapshot.connection,
            volume: MenuBarVolumeStatus(volume: snapshot.volume)
        )
    }

    static let placeholder = MenuBarStatus(snapshot: .placeholder)
}
