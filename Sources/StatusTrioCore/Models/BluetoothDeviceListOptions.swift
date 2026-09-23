import Foundation

/// The status panel's Bluetooth list preferences, derived once in
/// `SettingsStore` so the popover receives a single value instead of reading
/// three separate settings.
struct BluetoothDeviceListOptions: Equatable, Sendable {
    let showsList: Bool
    let maxVisibleDevices: Int
    let order: [String]
    /// When true, devices the profiler reported with no device class — scanned
    /// but never paired, and not listed in System Settings — are dropped from
    /// the panel. Off shows everything the profiler knows, so the user can
    /// reveal any device. Defaults on, because the panel should match what
    /// System Settings shows rather than the wider DeviceCache the profiler sees.
    let hidesGhostDevices: Bool
    /// Normalized addresses the user has chosen to hide from the panel, on top
    /// of the automatic ghost filter. Manual hides survive a rename because the
    /// address is the device's stable identity.
    let hiddenDeviceAddresses: Set<String>
    /// Normalized addresses the user has explicitly revealed from the ghost
    /// filter, overriding `hidesGhostDevices` for those specific devices. Ghost
    /// devices are hidden by default, but this set lets the user open individual
    /// ones without flipping the global filter to "show all".
    let revealedGhostDeviceAddresses: Set<String>

    /// The filter fields default so existing call sites that only care about
    /// list visibility, cap, and order keep compiling: a 3-field
    /// `BluetoothDeviceListOptions(showsList:maxVisibleDevices:order:)` still
    /// builds, and its effective behavior matches the panel's standard filter
    /// (ghosts hidden, nothing manually hidden or revealed).
    init(
        showsList: Bool,
        maxVisibleDevices: Int,
        order: [String],
        hidesGhostDevices: Bool = true,
        hiddenDeviceAddresses: Set<String> = [],
        revealedGhostDeviceAddresses: Set<String> = []
    ) {
        self.showsList = showsList
        self.maxVisibleDevices = maxVisibleDevices
        self.order = order
        self.hidesGhostDevices = hidesGhostDevices
        self.hiddenDeviceAddresses = hiddenDeviceAddresses
        self.revealedGhostDeviceAddresses = revealedGhostDeviceAddresses
    }

    static let standard = BluetoothDeviceListOptions(
        showsList: true,
        maxVisibleDevices: 5,
        order: [],
        hidesGhostDevices: true,
        hiddenDeviceAddresses: [],
        revealedGhostDeviceAddresses: []
    )
}
