import Foundation

/// The status panel's Bluetooth list preferences, derived once in
/// `SettingsStore` so the popover receives a single value instead of reading
/// three separate settings.
struct BluetoothDeviceListOptions: Equatable, Sendable {
    let showsList: Bool
    let maxVisibleDevices: Int
    let order: [String]

    static let standard = BluetoothDeviceListOptions(
        showsList: true,
        maxVisibleDevices: 5,
        order: []
    )
}
