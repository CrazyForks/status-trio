/// Identifies what the Dock icon actually draws, so signal noise that cannot
/// change a pixel (a different RSSI inside the same bar count, a different volume
/// inside the same dot count) does not trigger another render.
struct DockIconRenderKey: Equatable, Hashable {
    let batteryPercentage: Int
    let gapContent: BatteryGapContent
    let batteryColorRole: BatteryColorRole
    let connection: NetworkConnection
    let wifiState: WiFiState
    let wifiBars: Int
    let volumeSteps: Int
    let options: BatteryIconOptions
    let connectionOptions: ConnectionIconOptions
    let volumeOptions: VolumeIconOptions
    let volumeArcProgress: Double?
    let bluetoothAudioOptions: BluetoothAudioIconOptions
    let bluetoothAudioDeviceIcon: AudioOutputDeviceIconSource?
    let backgroundStyle: DockIconBackgroundStyle

    init(
        status: MenuBarStatus,
        options: BatteryIconOptions,
        connectionOptions: ConnectionIconOptions,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        backgroundStyle: DockIconBackgroundStyle
    ) {
        self.batteryPercentage = status.battery.percentage
        self.gapContent = StatusMappings.batteryGapContent(
            status.battery,
            options: options
        )
        self.batteryColorRole = options.usesStatusColors
            ? StatusMappings.batteryColorRole(
                status.battery,
                criticalThreshold: options.criticalThreshold
            )
            : .foreground
        self.connection = status.connection
        self.wifiState = status.wifi.state
        self.wifiBars = StatusMappings.wifiBars(rssi: status.wifi.rssi)
        self.volumeSteps = StatusMappings.volumeSteps(
            scalar: status.volume.scalar,
            isMuted: status.volume.isMuted
        ) ?? 0
        self.options = options
        self.connectionOptions = connectionOptions
        self.volumeOptions = volumeOptions
        self.volumeArcProgress = volumeOptions.displayStyle == .arc
            ? status.volume.scalar.flatMap(Self.clampedVolume)
            : nil
        self.bluetoothAudioOptions = bluetoothAudioOptions
        self.bluetoothAudioDeviceIcon = status.volume.currentDevice?.isBluetoothAudio == true
            ? status.volume.currentDevice.map { AudioOutputDeviceIcon.source(for: $0) }
            : nil
        self.backgroundStyle = backgroundStyle
    }

    private static func clampedVolume(_ scalar: Double) -> Double? {
        guard scalar.isFinite else { return nil }
        return min(1, max(0, scalar))
    }
}

struct DockIconRenderCache {
    private(set) var lastKey: DockIconRenderKey?

    mutating func shouldRender(_ key: DockIconRenderKey) -> Bool {
        guard key != lastKey else { return false }
        lastKey = key
        return true
    }

    mutating func reset() {
        lastKey = nil
    }
}

/// Keeps the images that were rendered for recent states, so recurring states
/// (the same volume steps, battery percentage, or Wi-Fi bars) reuse an image
/// instead of allocating another one.
@MainActor
final class DockIconImageCache {
    private let limit: Int
    private var images: [DockIconRenderKey: NSImage] = [:]
    private var order: [DockIconRenderKey] = []

    init(limit: Int = 12) {
        self.limit = max(1, limit)
    }

    func image(for key: DockIconRenderKey) -> NSImage? {
        guard let image = images[key] else { return nil }
        touch(key)
        return image
    }

    func store(_ image: NSImage, for key: DockIconRenderKey) {
        images[key] = image
        touch(key)

        while order.count > limit {
            let oldest = order.removeFirst()
            images[oldest] = nil
        }
    }

    func reset() {
        images.removeAll()
        order.removeAll()
    }

    private func touch(_ key: DockIconRenderKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
import AppKit
