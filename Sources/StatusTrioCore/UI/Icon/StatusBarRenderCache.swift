struct StatusBarRenderKey: Equatable {
    let status: MenuBarStatus
    let iconSize: Double
    let options: BatteryIconOptions
    let connectionOptions: ConnectionIconOptions
    let volumeOptions: VolumeIconOptions
    let bluetoothAudioOptions: BluetoothAudioIconOptions
    let appearanceName: String
    let phase: ChargingEffectPhase?

    init(
        status: MenuBarStatus,
        iconSize: Double,
        options: BatteryIconOptions,
        connectionOptions: ConnectionIconOptions,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        appearanceName: String,
        phase: ChargingEffectPhase? = nil
    ) {
        self.status = status
        self.iconSize = iconSize
        self.options = options
        self.connectionOptions = connectionOptions
        self.volumeOptions = volumeOptions
        self.bluetoothAudioOptions = bluetoothAudioOptions
        self.appearanceName = appearanceName
        self.phase = phase
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
