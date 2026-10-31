struct OutputDeviceListModel: Equatable {
    let orderedDevices: [AudioOutputDevice]
    let visibleDevices: [AudioOutputDevice]
    let canToggleExpansion: Bool

    static func make(
        devices: [AudioOutputDevice],
        order: [String],
        limit: Int?,
        isExpanded: Bool
    ) -> OutputDeviceListModel {
        let orderedDevices = OutputDeviceListPresentation.orderedDevices(
            devices,
            using: order
        )
        return OutputDeviceListModel(
            orderedDevices: orderedDevices,
            visibleDevices: OutputDeviceListPresentation.visibleDevices(
                from: orderedDevices,
                limit: limit,
                isExpanded: isExpanded
            ),
            canToggleExpansion: OutputDeviceListPresentation.canToggleExpansion(
                for: orderedDevices,
                limit: limit
            )
        )
    }
}

enum OutputDeviceListPresentation {
    static func orderedDevices(
        _ devices: [AudioOutputDevice],
        using order: [String]
    ) -> [AudioOutputDevice] {
        guard !order.isEmpty else { return devices }

        var ranks: [String: Int] = [:]
        for (index, uid) in order.enumerated() where ranks[uid] == nil {
            ranks[uid] = index
        }

        return devices.enumerated()
            .sorted { lhs, rhs in
                let leftRank = lhs.element.uid.flatMap { ranks[$0] } ?? Int.max
                let rightRank = rhs.element.uid.flatMap { ranks[$0] } ?? Int.max
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// The Settings order list: the shown devices in the saved order, then the
    /// hidden ones, so unchecking a device moves it below every shown device.
    static func settingsDevices(
        _ devices: [AudioOutputDevice],
        order: [String],
        hiddenUIDs: Set<String>
    ) -> [AudioOutputDevice] {
        let ordered = orderedDevices(devices, using: order)
        return ordered.filter { !isHidden($0, in: hiddenUIDs) }
            + ordered.filter { isHidden($0, in: hiddenUIDs) }
    }

    /// The status-panel list. A hidden device still appears while it is the
    /// active output, so the list never loses its selected row.
    static func panelDevices(
        _ devices: [AudioOutputDevice],
        order: [String],
        hiddenUIDs: Set<String>
    ) -> [AudioOutputDevice] {
        orderedDevices(devices, using: order)
            .filter { $0.isCurrent || !isHidden($0, in: hiddenUIDs) }
    }

    /// A device without a UID has no stable key to remember, so it can't be hidden.
    static func isHidden(_ device: AudioOutputDevice, in hiddenUIDs: Set<String>) -> Bool {
        guard let uid = device.uid else { return false }
        return hiddenUIDs.contains(uid)
    }

    static func visibleDevices<Device>(
        from devices: [Device],
        limit: Int?,
        isExpanded: Bool
    ) -> [Device] {
        guard !isExpanded, let limit else { return devices }
        return Array(devices.prefix(max(0, limit)))
    }

    static func canToggleExpansion<Device>(
        for devices: [Device],
        limit: Int?
    ) -> Bool {
        guard let limit else { return false }
        return devices.count > max(0, limit)
    }
}
