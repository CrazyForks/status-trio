import Foundation

enum BluetoothNearbyBatteryListPresentation {
    static func visibleDevices(
        from devices: [NearbyBluetoothBatteryDevice],
        enabled: Bool
    ) -> [NearbyBluetoothBatteryDevice] {
        guard enabled else { return [] }
        return devices.filter { (0...100).contains($0.batteryLevel) }
    }
}
