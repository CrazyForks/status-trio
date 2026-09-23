/// The list the status panel renders, derived once per body evaluation so the
/// view never re-derives the order or the limit itself.
struct BluetoothDeviceListModel: Equatable {
    let orderedDevices: [BluetoothDevice]
    let visibleDevices: [BluetoothDevice]
    let canToggleExpansion: Bool

    static func make(
        devices: [BluetoothDevice],
        order: [String],
        limit: Int,
        isExpanded: Bool,
        options: BluetoothDeviceListOptions
    ) -> BluetoothDeviceListModel {
        let filteredDevices = BluetoothDeviceListPresentation.filteredDevices(
            devices,
            options: options
        )
        let orderedDevices = BluetoothDeviceListPresentation.orderedDevices(filteredDevices, using: order)
        return BluetoothDeviceListModel(
            orderedDevices: orderedDevices,
            visibleDevices: BluetoothDeviceListPresentation.visibleDevices(
                from: orderedDevices,
                limit: limit,
                isExpanded: isExpanded
            ),
            canToggleExpansion: BluetoothDeviceListPresentation.canToggleExpansion(
                for: orderedDevices,
                limit: limit
            )
        )
    }
}

enum BluetoothDeviceListPresentation {
    /// Connected devices always lead; the saved order only reorders devices
    /// **within** their own group, so a drag can never lift a disconnected
    /// device above a connected one. Devices with no saved rank keep the
    /// group's own order and land after the ranked ones.
    static func orderedDevices(
        _ devices: [BluetoothDevice],
        using order: [String]
    ) -> [BluetoothDevice] {
        let groups = BluetoothDevicePresentation.grouped(devices)
        return ranked(groups.connected, using: order) + ranked(groups.disconnected, using: order)
    }

    /// Drops devices the user cannot act on or has chosen to hide: unpaired
    /// "ghost" devices the profiler reports but System Settings does not (when
    /// `options.hidesGhostDevices` is on, unless the device is in
    /// `options.revealedGhostDeviceAddresses`), and any device whose normalized
    /// address the user has hidden. The status panel renders the result; the
    /// Settings order list renders the raw devices so the user can still reveal
    /// or rearrange a hidden one.
    static func filteredDevices(
        _ devices: [BluetoothDevice],
        options: BluetoothDeviceListOptions
    ) -> [BluetoothDevice] {
        devices.filter { !isDeviceHidden($0, options: options) }
    }

    /// Whether the panel drops `device` under `options`. Ghost devices are hidden
    /// when `hidesGhostDevices` is on and the device is not in the reveal set;
    /// any device whose normalized address is in `hiddenDeviceAddresses` is
    /// hidden regardless of type. Centralized so the Settings row and the panel
    /// agree on what "hidden" means.
    static func isDeviceHidden(
        _ device: BluetoothDevice,
        options: BluetoothDeviceListOptions
    ) -> Bool {
        let key = BluetoothBatteryReader.normalizedAddress(device.id)
        if !key.isEmpty, options.hiddenDeviceAddresses.contains(key) {
            return true
        }
        if options.hidesGhostDevices,
           device.isUnpairedGhost,
           !options.revealedGhostDeviceAddresses.contains(key) {
            return true
        }
        return false
    }

    static func visibleDevices(
        from devices: [BluetoothDevice],
        limit: Int,
        isExpanded: Bool
    ) -> [BluetoothDevice] {
        guard !isExpanded else { return devices }
        return Array(devices.prefix(max(0, limit)))
    }

    static func canToggleExpansion(for devices: [BluetoothDevice], limit: Int) -> Bool {
        devices.count > max(0, limit)
    }

    private static func ranked(
        _ devices: [BluetoothDevice],
        using order: [String]
    ) -> [BluetoothDevice] {
        guard !order.isEmpty else { return devices }

        // Both sides are normalized: a saved entry written with separators or in
        // lowercase has to rank the device it names, or the order silently
        // applies to nothing while the list looks shuffled.
        var ranks: [String: Int] = [:]
        for (index, address) in order.enumerated() {
            let key = BluetoothBatteryReader.normalizedAddress(address)
            guard !key.isEmpty, ranks[key] == nil else { continue }
            ranks[key] = index
        }

        return devices.enumerated()
            .sorted { lhs, rhs in
                let leftRank = ranks[BluetoothBatteryReader.normalizedAddress(lhs.element.id)] ?? Int.max
                let rightRank = ranks[BluetoothBatteryReader.normalizedAddress(rhs.element.id)] ?? Int.max
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

/// Whether the panel's Bluetooth section shows the list at all, and whether the
/// row's own subtitle gives way to it. Both rules live here so the view body
/// stays a straight rendering of decisions that are unit-tested.
enum BluetoothPanelListVisibility {
    static func showsList(
        availability: BluetoothAvailability,
        devices: [BluetoothDevice],
        options: BluetoothDeviceListOptions
    ) -> Bool {
        guard options.showsList, availability == .available else { return false }
        return !BluetoothDeviceListPresentation.filteredDevices(devices, options: options).isEmpty
    }

    /// The list carries the connected names, so the subtitle that would repeat
    /// them is dropped. States only the row can explain — nothing connected, no
    /// permission, powered off, read failure — keep it.
    static func hidesRowSubtitle(
        availability: BluetoothAvailability,
        devices: [BluetoothDevice],
        options: BluetoothDeviceListOptions
    ) -> Bool {
        guard showsList(availability: availability, devices: devices, options: options) else {
            return false
        }
        let visible = BluetoothDeviceListPresentation.filteredDevices(devices, options: options)
        return !BluetoothDevicePresentation.grouped(visible).connected.isEmpty
    }
}
