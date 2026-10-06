import Foundation

/// The list the status panel renders, derived once per body evaluation so the
/// view never re-derives the order or the limit itself.
struct BluetoothDeviceListModel: Equatable {
    let orderedDevices: [BluetoothDevice]
    let visibleDevices: [BluetoothDevice]
    let canToggleExpansion: Bool

    static func make(
        devices: [BluetoothDevice],
        nearbyRows: [NearbyBLEPanelRow] = [],
        appleRows: [AppleDevicePanelRow] = [],
        order: [String],
        limit: Int,
        isExpanded: Bool,
        options: BluetoothDeviceListOptions
    ) -> BluetoothDeviceListModel {
        let unifiedDevices = devices + nearbyRows.map(\.device) + appleRows.map(\.device)
        let filteredDevices = BluetoothDeviceListPresentation.filteredDevices(
            unifiedDevices,
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
    /// Applies the shared system-row shadow rule while the nearby battery list
    /// is enabled. Saved selections are deliberately independent of row-level
    /// hiding: hiding the BLE row must not make its duplicate system ghost reappear.
    static func panelSystemRows(
        from systemRows: [BluetoothDevice],
        selectedNearbyBLEDevices: [BluetoothDevice],
        showsNearbyBatteryLevels: Bool,
        listOptions: BluetoothDeviceListOptions
    ) -> [BluetoothDevice] {
        guard showsNearbyBatteryLevels,
              listOptions.showsList,
              listOptions.maxVisibleDevices > 0 else { return systemRows }
        return removingSelectedNearbyBLEGhostShadows(
            from: systemRows,
            selectedNearbyBLERows: selectedNearbyBLEDevices
        )
    }

    /// Removes only a uniquely name-matched unpaired ghost that shadows one
    /// selected Nearby BLE row. This is presentation-only: neither row identity,
    /// readings, nor the UUID-based read permit is merged or changed by a name.
    static func removingSelectedNearbyBLEGhostShadows(
        from devices: [BluetoothDevice],
        selectedNearbyBLERows: [BluetoothDevice]
    ) -> [BluetoothDevice] {
        var selectedIDsByName: [String: Set<UUID>] = [:]
        for device in selectedNearbyBLERows {
            guard device.isReadOverTheAir,
                  let id = BluetoothDeviceIdentity.bleUUID(from: device.id),
                  let name = normalizedPresentationName(device.name) else { continue }
            selectedIDsByName[name, default: []].insert(id)
        }

        var ghostCountsByName: [String: Int] = [:]
        for device in devices where device.isUnpairedGhost && !device.isConnected {
            guard let name = normalizedPresentationName(device.name) else { continue }
            ghostCountsByName[name, default: 0] += 1
        }

        let shadowNames = Set(selectedIDsByName.compactMap { name, ids in
            ids.count == 1 && ghostCountsByName[name] == 1 ? name : nil
        })
        guard !shadowNames.isEmpty else { return devices }

        return devices.filter { device in
            guard device.isUnpairedGhost, !device.isConnected,
                  let name = normalizedPresentationName(device.name) else { return true }
            return !shadowNames.contains(name)
        }
    }

    private static func normalizedPresentationName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Connected devices always lead; the saved order only reorders devices
    /// **within** their own group, so a drag can never lift a disconnected
    /// device above a connected one. Devices with no saved rank keep the
    /// group's own order and land after the ranked ones.
    ///
    /// Trusted-mobile reading rows lead their group; selected BLE UUID rows
    /// remain in the saved order. See `leading`.
    static func orderedDevices(
        _ devices: [BluetoothDevice],
        using order: [String]
    ) -> [BluetoothDevice] {
        let groups = BluetoothDevicePresentation.grouped(devices)
        return leading(groups.connected, using: order) + leading(groups.disconnected, using: order)
    }

    /// One group, with trusted-mobile reading rows in front.
    ///
    /// Those rows are the only ones the panel has live information about: a
    /// level read over the air seconds ago, where every other row carries what
    /// macOS wrote down at some earlier point. The report knows nothing about
    /// where they belong, so it lists them wherever its own scan found them —
    /// the middle of the group, sorted among the rest by name — which is where
    /// the user was looking past them. The saved order arranges the rest and
    /// cannot push a reading row back among them.
    private static func leading(
        _ group: [BluetoothDevice],
        using order: [String]
    ) -> [BluetoothDevice] {
        let readings = group.filter {
            $0.isReadOverTheAir && BluetoothDeviceIdentity.bleUUID(from: $0.id) == nil
        }
        guard !readings.isEmpty else { return ranked(group, using: order) }
        return readings + ranked(group.filter { !readings.contains($0) }, using: order)
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
        let key = BluetoothDeviceIdentity.preferenceKey(device.id)
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
            let key = BluetoothDeviceIdentity.preferenceKey(address)
            guard !key.isEmpty, ranks[key] == nil else { continue }
            ranks[key] = index
        }

        return devices.enumerated()
            .sorted { lhs, rhs in
                let leftRank = ranks[BluetoothDeviceIdentity.preferenceKey(lhs.element.id)] ?? Int.max
                let rightRank = ranks[BluetoothDeviceIdentity.preferenceKey(rhs.element.id)] ?? Int.max
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

struct BluetoothDeviceSettingsOrderLabel: Equatable {
    let title: String
    let source: String?
}

enum BluetoothDeviceSettingsPresentation {
    static func orderLabel(
        device: BluetoothDevice,
        nearbyBLENames: [UUID: String],
        fallback: String,
        nearbySource: String
    ) -> BluetoothDeviceSettingsOrderLabel {
        guard let id = BluetoothDeviceIdentity.bleUUID(from: device.id) else {
            return BluetoothDeviceSettingsOrderLabel(title: device.name, source: nil)
        }
        let candidate = NearbyBLEDeviceCandidate(
            id: id,
            name: nearbyBLENames[id] ?? device.name,
            vendor: .unknown,
            lastSeen: .distantPast
        )
        return BluetoothDeviceSettingsOrderLabel(
            title: candidate.displayName(fallback: fallback),
            source: nearbySource
        )
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

/// Mobile helper readings are independently available while Bluetooth is off
/// or denied, but they still obey the user's device-list setting and filters.
enum BluetoothMobileBatteryPanelVisibility {
    static func shouldClaim(
        showsBatteryLevels: Bool,
        showsMobileBatteryLevels: Bool,
        options: BluetoothDeviceListOptions
    ) -> Bool {
        showsBatteryLevels && showsMobileBatteryLevels && options.showsList
    }

    static func showsList(
        availability: BluetoothAvailability,
        devices: [BluetoothDevice],
        pairedDevices: [BluetoothDevice],
        mobileDeviceIDs: Set<String>,
        showsMobileBatteryLevels: Bool,
        options: BluetoothDeviceListOptions
    ) -> Bool {
        guard options.showsList else { return false }
        if BluetoothPanelListVisibility.showsList(
            availability: availability,
            devices: pairedDevices,
            options: options
        ) {
            return true
        }
        guard showsMobileBatteryLevels else { return false }
        return BluetoothDeviceListPresentation.filteredDevices(devices, options: options)
            .contains { mobileDeviceIDs.contains($0.id) }
    }
}

enum BluetoothDeviceListHeading {
    static func title(
        hasNearbyDevices: Bool,
        hasExternalMobileDevices: Bool
    ) -> LocalizationKey? {
        guard hasNearbyDevices else { return nil }
        return hasExternalMobileDevices ? .bluetoothDevicesTitle : .bluetoothPairedDevicesTitle
    }
}

/// USB/Wi-Fi helper failures are independent of nearby BLE readings: a BLE
/// success must never hide a real helper failure, and an empty helper result
/// without failures is not itself an error.
enum MobileBatteryFailurePresentation {
    static func message(
        isEnabled: Bool,
        snapshots: [MobileBatterySnapshot],
        failures: [MobileBatteryReadFailure],
        isRefreshing: Bool
    ) -> LocalizationKey? {
        guard isEnabled, !isRefreshing, snapshots.isEmpty, !failures.isEmpty else { return nil }
        return failures.contains { $0.category == "trust-required" }
            ? .mobileBatteryTrustRequired
            : .mobileBatteryUnavailable
    }
}
