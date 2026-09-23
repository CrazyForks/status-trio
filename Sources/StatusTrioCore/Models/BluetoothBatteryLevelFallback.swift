/// Whether a device's level has to come from the accessory power sources, and
/// how the two sources are combined when it does.
///
/// The paired-device report is the primary source: it carries the device list
/// and the per-channel levels the list is rendered from. The accessory power
/// sources are the same underlying data seen through the power manager, and they
/// are consulted only for the devices the report carries no level for. A device
/// macOS can already read is therefore never described by the other source, so
/// the app can gain a level and can never change or lose one.
enum BluetoothBatteryLevelFallback {
    /// Whether the accessory sources are worth reading at all.
    ///
    /// Only a connected device counts. A disconnected one has no live session to
    /// read a level from — neither source reports one — so counting it here would
    /// make the answer "yes" on every single refresh, and cost a `/usr/bin/pmset`
    /// process each time. The filter lives here rather than at the call site so a
    /// caller cannot pass the whole list and get that for free.
    ///
    /// A report that could not be read is the other case this covers: with no
    /// levels to compare against, the only way to show anything is to ask the
    /// second source.
    static func isNeeded(
        levels: [String: BluetoothBatteryLevel]?,
        devices: [BluetoothDevice]
    ) -> Bool {
        let connected = devices.filter(\.isConnected)
        guard !connected.isEmpty else { return false }
        guard let levels else { return true }
        return connected.contains {
            levels[BluetoothBatteryReader.normalizedAddress($0.id)] == nil
        }
    }

    /// The primary levels, with a level added for every device they carry none
    /// for. Entries the report already has are copied through untouched, so this
    /// can only ever add.
    static func merged(
        levels: [String: BluetoothBatteryLevel],
        accessories: [BluetoothAccessoryBatteryLevel],
        devices: [BluetoothDevice]
    ) -> [String: BluetoothBatteryLevel] {
        var merged = levels
        for device in devices {
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            guard !address.isEmpty, merged[address] == nil else { continue }
            guard let level = level(for: device, accessories: accessories) else { continue }
            merged[address] = level
        }
        return merged
    }

    /// One device's level, built from every accessory reading that belongs to it.
    ///
    /// Each reading lands in the channel its part names, and a reading with no
    /// part — or with a part the app does not know — lands in the device-wide
    /// level. A part is never allowed to write the device-wide level, which is
    /// what stops one bud's charge from being reported as the whole device's.
    /// The first reading for a channel wins, so a second accessory source for the
    /// same channel cannot overwrite the first with a staler number.
    static func level(
        for device: BluetoothDevice,
        accessories: [BluetoothAccessoryBatteryLevel]
    ) -> BluetoothBatteryLevel? {
        var main: Int?
        var left: Int?
        var right: Int?
        var caseLevel: Int?
        for accessory in accessories where matches(accessory, device) {
            switch accessory.part {
            case .none: main = main ?? accessory.percentage
            case .left: left = left ?? accessory.percentage
            case .right: right = right ?? accessory.percentage
            case .caseLevel: caseLevel = caseLevel ?? accessory.percentage
            }
        }
        guard main != nil || left != nil || right != nil || caseLevel != nil else { return nil }
        return BluetoothBatteryLevel(
            deviceAddress: device.id,
            main: main,
            left: left,
            right: right,
            caseLevel: caseLevel
        )
    }

    /// Whether an accessory reading describes a device.
    ///
    /// The vendor and product ID pair is the identity: it survives a rename and
    /// names one model. When both sides carry the pair, they decide on their own —
    /// a name is not consulted, because a rename would otherwise re-join a
    /// reading to whichever device now happens to share its wording. A name is
    /// what is left when either side has no pair, and that comparison is exact
    /// once whitespace and case are ignored: a substring match would join an
    /// accessory to any device whose name happens to contain it.
    static func matches(_ accessory: BluetoothAccessoryBatteryLevel, _ device: BluetoothDevice) -> Bool {
        if let vendor = device.vendorID,
           let product = device.productID,
           let accessoryVendor = accessory.vendorID,
           let accessoryProduct = accessory.productID {
            return accessoryVendor == vendor && accessoryProduct == product
        }
        let name = device.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return false }
        return accessory.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name
    }
}
