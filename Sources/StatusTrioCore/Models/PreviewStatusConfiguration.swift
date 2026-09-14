import CoreAudio
import Foundation

struct PreviewVirtualOutputDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    var name: String
}

struct PreviewStatusConfiguration: Equatable, Sendable {
    var batteryPercentage: Int
    var isBatteryPresent: Bool
    var isCharging: Bool
    var isCharged: Bool
    var isLowPowerMode: Bool
    var isConnectedToPower: Bool
    var wifiState: WiFiState
    var wifiRSSI: Int
    var wifiSSID: String
    var volumeScalar: Double
    var isMuted: Bool
    var virtualOutputDevices: [PreviewVirtualOutputDevice]
    var selectedVirtualOutputDeviceID: AudioDeviceID?

    static let standard = PreviewStatusConfiguration(
        batteryPercentage: 72,
        isBatteryPresent: true,
        isCharging: false,
        isCharged: false,
        isLowPowerMode: false,
        isConnectedToPower: false,
        wifiState: .connected,
        wifiRSSI: -55,
        wifiSSID: "Preview Wi-Fi",
        volumeScalar: 0.65,
        isMuted: false,
        virtualOutputDevices: [
            PreviewVirtualOutputDevice(id: 1000, name: "Preview Output")
        ],
        selectedVirtualOutputDeviceID: 1000
    )

    var snapshot: StatusSnapshot {
        let battery = BatteryStatus(
            rawPercentage: batteryPercentage,
            isPresent: isBatteryPresent,
            isCharging: isCharging,
            isCharged: isCharged,
            isLowPowerMode: isLowPowerMode,
            isConnectedToPower: isConnectedToPower
        )
        let wifi = WiFiStatus(
            state: wifiState,
            rssi: wifiRSSI,
            ssid: wifiSSID.isEmpty ? nil : wifiSSID,
            nameAccess: .authorized
        )
        let outputDevices = virtualOutputDevices.map { device in
            AudioOutputDevice(
                id: device.id,
                name: device.name,
                isCurrent: device.id == selectedVirtualOutputDeviceID,
                volume: volumeScalar
            )
        }
        let currentOutputDevice = outputDevices.first(where: \.isCurrent)
        let volume = VolumeStatus(
            scalar: volumeScalar,
            isMuted: isMuted,
            deviceName: currentOutputDevice?.name,
            outputDevices: outputDevices
        )
        return StatusSnapshot(battery: battery, wifi: wifi, volume: volume)
    }
}
