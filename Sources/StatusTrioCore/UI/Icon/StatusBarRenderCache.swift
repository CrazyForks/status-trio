struct StatusBarRenderKey: Equatable {
    let status: MenuBarStatus
    let iconSize: Double
    let options: BatteryIconOptions
    let connectionOptions: ConnectionIconOptions
    let volumeOptions: VolumeIconOptions
    let appearanceName: String

    init(
        status: MenuBarStatus,
        iconSize: Double,
        options: BatteryIconOptions,
        connectionOptions: ConnectionIconOptions,
        volumeOptions: VolumeIconOptions = .standard,
        appearanceName: String
    ) {
        self.status = status
        self.iconSize = iconSize
        self.options = options
        self.connectionOptions = connectionOptions
        self.volumeOptions = volumeOptions
        self.appearanceName = appearanceName
    }
}

struct StatusBarRenderCache {
    private(set) var lastKey: StatusBarRenderKey?

    mutating func shouldRender(_ key: StatusBarRenderKey) -> Bool {
        guard key != lastKey else { return false }
        lastKey = key
        return true
    }
}
