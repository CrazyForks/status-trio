import Foundation

/// The paired-device list with the iOS devices the BLE scan found folded into it.
///
/// A nearby battery reading is not a separate kind of device: an iPhone that the
/// paired-device report lists without a class, and the same iPhone seen over the
/// air, are one device on two frequencies. Listing them twice — once as an
/// unclassified row and once under "nearby" — describes the same phone as if it
/// were two, so the reading is folded onto the row it belongs to instead.
///
/// The fold is by name, because that is the only identity the two sources share.
/// The report keys a device by its classic address and the scan by the
/// peripheral's CoreBluetooth identifier, and the two are not the same value and
/// cannot be converted into one another. A name is what both sides carry, and the
/// comparison is exact once whitespace and case are dropped, for the reason the
/// accessory fallback gives: a substring match would fold a reading onto any
/// device whose name happens to contain it.
///
/// Only devices the model string identifies as Apple's mobile family are folded.
/// Anything else the scan found — a BLE thermometer, a fitness tracker — is
/// handed back as a nearby device and keeps the section it arrived in.
enum BluetoothNearbyDeviceMerge {
    struct Result: Equatable {
        /// The paired-device list, with a row added for a mobile device the
        /// report does not carry at all.
        ///
        /// The order is the report's own, with an added row appended. Where the
        /// panel draws a row a reading created is the panel's rule, not this
        /// one's: see `BluetoothDeviceListPresentation.orderedDevices`.
        let devices: [BluetoothDevice]
        /// The paired-device levels, with a level added for every device the
        /// report carried none for.
        let batteryLevels: [String: BluetoothBatteryLevel]
        /// The scan results that were not folded in.
        let remainingNearby: [NearbyBluetoothBatteryDevice]
    }

    static func merged(
        devices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel],
        nearbyDevices: [NearbyBluetoothBatteryDevice]
    ) -> Result {
        var mergedDevices = devices
        var mergedLevels = batteryLevels
        var remaining: [NearbyBluetoothBatteryDevice] = []

        for nearby in nearbyDevices {
            guard let kind = BluetoothMobileDeviceModel.kind(forModel: nearby.model),
                  !nearby.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                remaining.append(nearby)
                continue
            }

            if let index = mergedDevices.firstIndex(where: { $0.name.matchesDeviceName(nearby.name) }) {
                let device = mergedDevices[index]
                // The report's own class wins when it declared one. Only a row it
                // could not classify is corrected, so a device macOS described
                // keeps the class macOS gave it.
                mergedDevices[index] = device.kind == .unknown
                    ? device.identifiedByModel(kind)
                    : device
                let key = BluetoothBatteryReader.normalizedAddress(device.id)
                addIfAbsent(&mergedLevels, key: key, level: nearby.batteryLevel, address: device.id)
            } else {
                let device = BluetoothDevice(
                    id: nearby.id.uuidString,
                    name: nearby.name,
                    kind: kind,
                    isConnected: false,
                    isReadOverTheAir: true
                )
                mergedDevices.append(device)
                let key = BluetoothBatteryReader.normalizedAddress(device.id)
                addIfAbsent(&mergedLevels, key: key, level: nearby.batteryLevel, address: device.id)
            }
        }

        return Result(
            devices: mergedDevices,
            batteryLevels: mergedLevels,
            remainingNearby: remaining
        )
    }

    /// A level is only ever added. The paired-device report is the primary
    /// source, and it also carries the per-channel parts a scan reading has no
    /// way to describe, so a device it already answered for keeps its answer.
    private static func addIfAbsent(
        _ levels: inout [String: BluetoothBatteryLevel],
        key: String,
        level: Int,
        address: String
    ) {
        guard !key.isEmpty, levels[key] == nil else { return }
        levels[key] = BluetoothBatteryLevel(
            deviceAddress: address,
            main: level,
            left: nil,
            right: nil,
            caseLevel: nil
        )
    }
}

private extension String {
    /// Whether this report name and an advertised name describe one device.
    func matchesDeviceName(_ other: String) -> Bool {
        let mine = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let theirs = other.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !mine.isEmpty && mine == theirs
    }
}
