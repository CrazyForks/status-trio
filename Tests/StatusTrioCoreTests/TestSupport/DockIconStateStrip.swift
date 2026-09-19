import AppKit
import CoreGraphics
import Foundation
@testable import StatusTrioCore

/// Renders eight representative Dock states as one text-free horizontal strip.
/// The background style intentionally alternates dark/light so the same live
/// glyph can be compared across both appearances at a glance.
@MainActor
enum DockIconStateStrip {
    struct State {
        let backgroundStyle: DockIconBackgroundStyle
        let status: MenuBarStatus
        let batteryOptions: BatteryIconOptions
        let connectionOptions: ConnectionIconOptions
        let volumeOptions: VolumeIconOptions
        let bluetoothAudioOptions: BluetoothAudioIconOptions

        var volumeStyle: VolumeDisplayStyle { volumeOptions.displayStyle }

        var usesBluetoothAudio: Bool {
            status.volume.currentDevice?.isBluetoothAudio == true
        }

        var usesBluetoothVolumeColor: Bool {
            usesBluetoothAudio && bluetoothAudioOptions.usesVolumeColor
        }
    }

    private static let iconSize: CGFloat = 220
    private static let gap: CGFloat = 14
    private static let horizontalMargin: CGFloat = 24
    private static let verticalMargin: CGFloat = 24
    private static let canvasHeight = iconSize + verticalMargin * 2

    static let states: [State] = [
        State(
            backgroundStyle: .dark,
            status: status(battery: battery(76, charging: true, connected: true), wifi: connectedWiFi, volume: volume(0.6)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: .standard,
            bluetoothAudioOptions: .standard
        ),
        State(
            backgroundStyle: .light,
            status: status(battery: battery(76, connected: true), wifi: connectedWiFi, volume: volume(0.75)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: VolumeIconOptions(displayStyle: .arc),
            bluetoothAudioOptions: .standard
        ),
        State(
            backgroundStyle: .dark,
            status: status(battery: battery(15), wifi: WiFiStatus(state: .connected, rssi: -85), volume: volume(0.6, muted: true)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: .standard,
            bluetoothAudioOptions: .standard
        ),
        State(
            backgroundStyle: .light,
            status: status(battery: battery(55, lowPower: true), wifi: WiFiStatus(state: .noInternet, rssi: -58), volume: volume(0.25)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: .standard,
            bluetoothAudioOptions: .standard
        ),
        State(
            backgroundStyle: .dark,
            status: bluetoothStatus(battery: battery(76, charging: true, connected: true), volume: volume(0.75)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: .standard,
            bluetoothAudioOptions: bluetoothOptions
        ),
        State(
            backgroundStyle: .light,
            status: bluetoothStatus(battery: battery(76), volume: volume(0.45)),
            batteryOptions: BatteryIconOptions(showsPercentage: true),
            connectionOptions: .standard,
            volumeOptions: VolumeIconOptions(displayStyle: .arc),
            bluetoothAudioOptions: bluetoothOptions
        ),
        State(
            backgroundStyle: .dark,
            status: bluetoothStatus(battery: battery(100, charged: true, connected: true), volume: volume(1)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: .standard,
            bluetoothAudioOptions: bluetoothOptions
        ),
        State(
            backgroundStyle: .light,
            status: status(battery: battery(76), wifi: WiFiStatus(state: .hotspot, rssi: -58), volume: volume(0.65)),
            batteryOptions: .standard,
            connectionOptions: .standard,
            volumeOptions: VolumeIconOptions(displayStyle: .arc),
            bluetoothAudioOptions: .standard
        )
    ]

    static func pngData(scale: CGFloat = 2) throws -> Data {
        let canvasWidth = horizontalMargin * 2
            + iconSize * CGFloat(states.count)
            + gap * CGFloat(states.count - 1)
        let context = try SheetCanvas.makeContext(width: canvasWidth, height: canvasHeight, scale: scale)

        context.setFillColor(SheetCanvas.color(0.93, 0.93, 0.95))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

        let y = verticalMargin
        for (index, state) in states.enumerated() {
            guard let image = DockIconRenderer.image(
                status: state.status,
                options: state.batteryOptions,
                connectionOptions: state.connectionOptions,
                volumeOptions: state.volumeOptions,
                bluetoothAudioOptions: state.bluetoothAudioOptions,
                backgroundStyle: state.backgroundStyle
            ) else {
                throw StripError.iconUnavailable
            }

            var proposed = CGRect(origin: .zero, size: image.size)
            guard let tile = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
                throw StripError.iconUnavailable
            }

            let x = horizontalMargin + CGFloat(index) * (iconSize + gap)
            context.draw(tile, in: CGRect(x: x, y: y, width: iconSize, height: iconSize))
        }

        return try SheetCanvas.pngData(context)
    }

    enum StripError: Error {
        case iconUnavailable
    }

    private static let connectedWiFi = WiFiStatus(state: .connected, rssi: -52)
    private static let bluetoothOptions = BluetoothAudioIconOptions(
        replacesNetworkIcon: true,
        usesVolumeColor: true
    )

    private static func battery(
        _ percentage: Int,
        charging: Bool = false,
        charged: Bool = false,
        connected: Bool = false,
        lowPower: Bool = false
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: charging,
            isCharged: charged,
            isLowPowerMode: lowPower,
            isConnectedToPower: connected
        )
    }

    private static func volume(
        _ scalar: Double,
        muted: Bool = false,
        bluetooth: Bool = false
    ) -> MenuBarVolumeStatus {
        let device = bluetooth ? SheetFixtures.bluetoothDevice : nil
        return MenuBarVolumeStatus(
            scalar: scalar,
            isMuted: muted,
            deviceName: device?.name,
            currentDevice: device
        )
    }

    private static func status(
        battery: BatteryStatus,
        wifi: WiFiStatus,
        volume: MenuBarVolumeStatus
    ) -> MenuBarStatus {
        MenuBarStatus(battery: battery, wifi: wifi, connection: .wifi, volume: volume)
    }

    private static func bluetoothStatus(
        battery: BatteryStatus,
        volume: MenuBarVolumeStatus
    ) -> MenuBarStatus {
        status(battery: battery, wifi: connectedWiFi, volume: MenuBarVolumeStatus(
            scalar: volume.scalar,
            isMuted: volume.isMuted,
            deviceName: SheetFixtures.bluetoothDevice.name,
            currentDevice: SheetFixtures.bluetoothDevice
        ))
    }
}
