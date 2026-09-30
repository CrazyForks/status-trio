@testable import StatusTrioCore

@MainActor
func makeTestIconPresentation(
    store: SystemStatusStore,
    settings: SettingsStore
) -> IconPresentationViewModel {
    let appearance = StatusIconAppearance(settings: settings)
    return IconPresentationViewModel(
        snapshot: store.snapshot,
        settings: IconPresentationSettings(
            configuration: IconPresentationConfiguration(
                battery: appearance.batteryOptions,
                connection: appearance.connectionOptions,
                volume: appearance.volumeOptions,
                bluetooth: appearance.bluetoothAudioOptions
            ),
            menuBarSize: appearance.iconSize,
            testsChargingEffect: settings.testsChargingEffect
        ),
        snapshots: store.$snapshot.eraseToAnyPublisher(),
        preferences: settings.iconPresentationPublisher,
        resolveInputs: { IconPresentationResourceResolver.inputs(snapshot: $0) }
    )
}

@MainActor
func makeIconPresentationScene(
    status: MenuBarStatus,
    battery: BatteryIconOptions = .standard,
    connection: ConnectionIconOptions = .standard,
    volume: VolumeIconOptions = .standard,
    bluetooth: BluetoothAudioIconOptions = .standard
) -> IconSceneState {
    let snapshot = StatusSnapshot(
        battery: status.battery,
        wifi: status.wifi,
        connection: status.connection,
        volume: VolumeStatus(
            scalar: status.volume.scalar,
            isMuted: status.volume.isMuted,
            deviceName: status.volume.deviceName,
            currentDevice: status.volume.currentDevice
        )
    )
    return IconPresentationMapper.scene(
        inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
        configuration: IconPresentationConfiguration(
            battery: battery,
            connection: connection,
            volume: volume,
            bluetooth: bluetooth
        )
    )
}
