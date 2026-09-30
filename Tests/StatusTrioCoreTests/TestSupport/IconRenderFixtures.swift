import AppKit
import CoreGraphics
@testable import StatusTrioCore

/// Domain fixtures for raster tests that assert independent geometry or color
/// conventions. Product mapping is still exercised through the canonical mapper;
/// these helpers contain no selection or drawing rules.
func renderMenuBarFixture(
    snapshot: StatusSnapshot,
    size: CGFloat,
    scale: CGFloat,
    foreground: CGColor,
    criticalColor: CGColor? = nil,
    options: BatteryIconOptions = .standard,
    connectionOptions: ConnectionIconOptions = .standard,
    volumeOptions: VolumeIconOptions = .standard,
    bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
    audioIcon: IconSymbolSource? = nil,
    phase: ChargingEffectPhase? = nil
) -> CGImage? {
    let scene = IconPresentationMapper.scene(
        inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: audioIcon),
        configuration: IconPresentationConfiguration(
            battery: options,
            connection: connectionOptions,
            volume: volumeOptions,
            bluetooth: bluetoothAudioOptions
        )
    )
    return StatusIconRenderer.render(
        scene: scene,
        environment: StatusIconRenderEnvironment(
            size: size,
            scale: scale,
            foreground: foreground,
            criticalColor: criticalColor ?? StatusIconRenderer.defaultCriticalColor
        ),
        phase: phase
    )
}

func renderMenuBarFixture(
    menuBarStatus: MenuBarStatus,
    size: CGFloat,
    scale: CGFloat,
    foreground: CGColor,
    criticalColor: CGColor? = nil,
    options: BatteryIconOptions = .standard,
    connectionOptions: ConnectionIconOptions = .standard,
    volumeOptions: VolumeIconOptions = .standard,
    bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
    audioIcon: IconSymbolSource? = nil,
    phase: ChargingEffectPhase? = nil
) -> CGImage? {
    renderMenuBarFixture(
        snapshot: snapshotFromMenuBarStatus(menuBarStatus),
        size: size,
        scale: scale,
        foreground: foreground,
        criticalColor: criticalColor,
        options: options,
        connectionOptions: connectionOptions,
        volumeOptions: volumeOptions,
        bluetoothAudioOptions: bluetoothAudioOptions,
        audioIcon: audioIcon,
        phase: phase
    )
}

func menuBarFixtureImage(
    menuBarStatus: MenuBarStatus,
    size: CGFloat,
    scale: CGFloat = 2,
    appearance: NSAppearance? = nil,
    options: BatteryIconOptions = .standard,
    connectionOptions: ConnectionIconOptions = .standard,
    volumeOptions: VolumeIconOptions = .standard,
    bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
    phase: ChargingEffectPhase? = nil
) -> NSImage {
    guard let image = StatusIconRenderer.image(
        scene: IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshotFromMenuBarStatus(menuBarStatus), audioIcon: nil),
            configuration: IconPresentationConfiguration(
                battery: options,
                connection: connectionOptions,
                volume: volumeOptions,
                bluetooth: bluetoothAudioOptions
            )
        ),
        size: size,
        scale: scale,
        appearance: appearance,
        phase: phase
    ) else {
        fatalError("The icon fixture must produce a supported scene.")
    }
    return image
}

func menuBarFixtureImage(
    snapshot: StatusSnapshot,
    size: CGFloat,
    scale: CGFloat = 2,
    appearance: NSAppearance? = nil,
    options: BatteryIconOptions = .standard,
    connectionOptions: ConnectionIconOptions = .standard,
    volumeOptions: VolumeIconOptions = .standard,
    bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
    phase: ChargingEffectPhase? = nil
) -> NSImage {
    guard let image = StatusIconRenderer.image(
        scene: IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: IconPresentationConfiguration(
                battery: options,
                connection: connectionOptions,
                volume: volumeOptions,
                bluetooth: bluetoothAudioOptions
            )
        ),
        size: size,
        scale: scale,
        appearance: appearance,
        phase: phase
    ) else {
        fatalError("The icon fixture must produce a supported scene.")
    }
    return image
}

private func snapshotFromMenuBarStatus(_ status: MenuBarStatus) -> StatusSnapshot {
    StatusSnapshot(
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
}

@MainActor
func renderDockFixture(
    status: MenuBarStatus,
    options: BatteryIconOptions = .standard,
    connectionOptions: ConnectionIconOptions = .standard,
    volumeOptions: VolumeIconOptions = .standard,
    bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
    backgroundStyle: DockIconBackgroundStyle = .dark,
    pixelLength: Int = DockIconRenderer.pixelSize
) -> NSImage? {
        DockIconRenderer.image(
            scene: IconPresentationMapper.scene(
                inputs: IconPresentationResourceResolver.inputs(snapshot: snapshotFromMenuBarStatus(status)),
            configuration: IconPresentationConfiguration(
                battery: options,
                connection: connectionOptions,
                volume: volumeOptions,
                bluetooth: bluetoothAudioOptions
            )
        ),
        backgroundStyle: backgroundStyle,
        pixelLength: pixelLength
    )
}
