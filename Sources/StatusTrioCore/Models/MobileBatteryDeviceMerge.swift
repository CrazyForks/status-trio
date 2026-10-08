import Foundation
import CryptoKit

/// Combines macOS's paired-device report with trusted mobile snapshots.
/// Provider identities are joined only when their stable identifiers match.
enum MobileBatteryDeviceMerge {
    struct Result: Equatable {
        let devices: [BluetoothDevice]
        let batteryLevels: [String: BluetoothBatteryLevel]
        let remainingNearby: [NearbyBluetoothBatteryDevice]
        /// Rows identified by a mobile read even when an existing paired
        /// battery value remains authoritative and mobile metadata is hidden.
        let mobileDeviceIDs: Set<String>
        let mobileMetadataByDeviceID: [String: MobileBatterySnapshot]
    }

    static func merged(
        devices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel],
        nearbyDevices: [NearbyBluetoothBatteryDevice],
        mobileSnapshots: [MobileBatterySnapshot],
        fallbackWatchName: String
    ) -> Result {
        var mergedDevices = devices
        var mergedLevels = batteryLevels
        var remainingNearby: [NearbyBluetoothBatteryDevice] = []
        var metadata: [String: MobileBatterySnapshot] = [:]
        var mobileDeviceIDs = Set<String>()
        let snapshots = deduplicatedSnapshots(mobileSnapshots)

        // Reserve every exact identity match before considering any names. A
        // different snapshot with a matching name must never take a row that a
        // stable identity identifies later in the same merge.
        let identityMatches = Dictionary(uniqueKeysWithValues: snapshots.compactMap { snapshot -> (String, Int)? in
            let matches = devices.indices.filter { devices[$0].id == snapshot.identity }
            guard matches.count == 1, let index = matches.first else { return nil }
            return (snapshot.identity, index)
        })
        var consumedMobileIdentities = Set<String>()

        for snapshot in snapshots {
            guard let index = identityMatches[snapshot.identity],
                  let mobileKind = BluetoothMobileDeviceModel.kind(forModel: snapshot.model) else { continue }
            let device = mergedDevices[index]
            if device.kind == .unknown {
                mergedDevices[index] = device.replacingKind(with: mobileKind)
                    .recordingAppleMobileModel(snapshot.model)
            } else if mobileKind == .mobile(.watch) {
                mergedDevices[index] = device.recordingAppleMobileModel(snapshot.model)
            }
            mobileDeviceIDs.insert(device.id)
            if addMobileLevel(snapshot, to: device.id, levels: &mergedLevels) {
                metadata[device.id] = snapshot
            }
            consumedMobileIdentities.insert(snapshot.identity)
        }

        for snapshot in snapshots {
            guard !consumedMobileIdentities.contains(snapshot.identity) else { continue }
            guard let mobileKind = BluetoothMobileDeviceModel.kind(forModel: snapshot.model) else { continue }
            let stableID = externalDeviceID(for: snapshot.identity)

            let observedName = snapshot.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = observedName.isEmpty
                ? (mobileKind == .mobile(.watch) ? fallbackWatchName : fallbackPhoneName)
                : observedName
            let device = BluetoothDevice(
                id: stableID,
                name: name,
                kind: mobileKind,
                isConnected: false,
                appleMobileModel: snapshot.model,
                isReadOverTheAir: true
            )
            mergedDevices.append(device)
            mobileDeviceIDs.insert(device.id)
            if addMobileLevel(snapshot, to: device.id, levels: &mergedLevels) {
                metadata[device.id] = snapshot
            }
        }

        remainingNearby = nearbyDevices

        return Result(
            devices: mergedDevices,
            batteryLevels: mergedLevels,
            remainingNearby: remainingNearby,
            mobileDeviceIDs: mobileDeviceIDs,
            mobileMetadataByDeviceID: metadata
        )
    }

    /// The namespace is visibly prefixed and the identity is hashed to fixed
    /// hex. The global Bluetooth key normalizer keeps the hex namespace and
    /// digest, avoiding collisions between provider IDs that filter to the same
    /// text without embedding a reversible device identifier in the row ID.
    static func externalDeviceID(for identity: String) -> String {
        let digest = SHA256.hash(data: Data(identity.utf8))
        let hexDigest = digest.map { String(format: "%02X", $0) }.joined()
        return "mobile-\(hexDigest)"
    }

    private static let fallbackPhoneName = "iPhone"

    static func deduplicatedSnapshots(_ snapshots: [MobileBatterySnapshot]) -> [MobileBatterySnapshot] {
        var latestByIdentity: [String: MobileBatterySnapshot] = [:]
        for snapshot in snapshots {
            guard let existing = latestByIdentity[snapshot.identity] else {
                latestByIdentity[snapshot.identity] = snapshot
                continue
            }
            if snapshot.observedAt > existing.observedAt
                || (snapshot.observedAt == existing.observedAt && snapshot.transport == .usb && existing.transport == .network) {
                latestByIdentity[snapshot.identity] = snapshot
            }
        }
        return latestByIdentity.values.sorted { $0.identity < $1.identity }
    }

    private static func addMobileLevel(
        _ snapshot: MobileBatterySnapshot,
        to deviceID: String,
        levels: inout [String: BluetoothBatteryLevel]
    ) -> Bool {
        let key = BluetoothBatteryReader.normalizedAddress(deviceID)
        guard !key.isEmpty, levels[key] == nil else { return false }
        levels[key] = BluetoothBatteryLevel(
            deviceAddress: deviceID,
            main: snapshot.batteryLevel,
            left: nil,
            right: nil,
            caseLevel: nil
        )
        return true
    }

}
