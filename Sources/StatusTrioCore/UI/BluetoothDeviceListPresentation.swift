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
        isExpanded: Bool
    ) -> BluetoothDeviceListModel {
        let orderedDevices = BluetoothDeviceListPresentation.orderedDevices(devices, using: order)
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
        return !devices.isEmpty
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
        return !BluetoothDevicePresentation.grouped(devices).connected.isEmpty
    }
}
