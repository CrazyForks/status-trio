import Foundation

struct NearbyBLEPanelRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let device: BluetoothDevice
    let batteryLevel: Int?
    let wasSeenRecently: Bool
    let readFailed: Bool

    var status: NearbyBLEPanelRowStatus {
        if let batteryLevel { return .battery(batteryLevel) }
        if readFailed { return .unavailable }
        return wasSeenRecently ? .pending : .notNearby
    }
}

enum NearbyBLEPanelRowStatus: Equatable, Sendable {
    case battery(Int)
    case unavailable
    case notNearby
    case pending
}

enum NearbyBLEDeviceCatalog {
    static let recentCandidateLifetime: TimeInterval = 60

    /// Rows shown in Settings, in the user's saved order. The explicit BLE
    /// identity keeps controls for a nearby peripheral separate from any
    /// same-named row in the system Bluetooth report.
    static func settingsDevices(selections: [NearbyBLEDeviceSelection]) -> [BluetoothDevice] {
        selections.map { selection in
            device(
                id: selection.id,
                name: selection.name,
                model: selection.model
            )
        }
    }

    /// A selection first discovery picker that retains saved UUIDs which are
    /// no longer broadcasting, so users can still remove them.
    static func settingsCandidates(
        selections: [NearbyBLEDeviceSelection],
        candidates: [NearbyBLEDeviceCandidate]
    ) -> [NearbyBLEDeviceCandidate] {
        var byID: [UUID: NearbyBLEDeviceCandidate] = [:]
        for candidate in NearbyBLEDiscoveryPresentation.ordered(candidates) {
            byID[candidate.id] = candidate
        }
        var result = selections.map { selection in
            let live = byID.removeValue(forKey: selection.id)
            let liveName = live?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return NearbyBLEDeviceCandidate(
                id: selection.id,
                name: liveName.isEmpty ? selection.name : liveName,
                vendor: live?.vendor ?? selection.vendor,
                lastSeen: live?.lastSeen ?? .distantPast
            )
        }
        result.append(contentsOf: NearbyBLEDiscoveryPresentation.ordered(Array(byID.values)))
        return NearbyBLEDiscoveryPresentation.ordered(result)
    }

    /// Projects the selected UUID allowlist into panel rows. Broadcast names
    /// and vendor data describe discovery only; neither can create a row or
    /// classify it as an iPhone. Only selected metadata and a trusted GATT model
    /// may contribute identity details.
    static func panelRows(
        selections: [NearbyBLEDeviceSelection],
        candidates: [NearbyBLEDeviceCandidate],
        readings: [NearbyBluetoothBatteryDevice],
        failures: Set<UUID>,
        options: BluetoothDeviceListOptions,
        now: Date
    ) -> [NearbyBLEPanelRow] {
        let candidatesByID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let readingsByID = Dictionary(readings.map { ($0.id, $0) }, uniquingKeysWith: { older, newer in
            older.lastUpdated >= newer.lastUpdated ? older : newer
        })
        let orderRanks = ranks(from: options.order)

        let indexedRows: [(Int, NearbyBLEPanelRow)] = selections.enumerated().compactMap { element in
            let (index, selection) = element
            let row = device(
                id: selection.id,
                name: selection.name,
                model: selection.model ?? readingsByID[selection.id]?.model
            )
            guard !BluetoothDeviceListPresentation.isDeviceHidden(row, options: options) else { return nil }
            return (index, NearbyBLEPanelRow(
                id: selection.id,
                device: row,
                batteryLevel: validLevel(readingsByID[selection.id], now: now),
                wasSeenRecently: candidatesByID[selection.id].map { isRecent($0, now: now) } ?? false,
                readFailed: failures.contains(selection.id)
            ))
        }
        return indexedRows.sorted { lhs, rhs in
            let leftRank = orderRanks[BluetoothDeviceIdentity.preferenceKey(lhs.1.device.id)] ?? Int.max
            let rightRank = orderRanks[BluetoothDeviceIdentity.preferenceKey(rhs.1.device.id)] ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.0 < rhs.0
        }
        .map(\.1)
    }

    private static func device(id: UUID, name: String, model: String?) -> BluetoothDevice {
        BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(id),
            name: name,
            kind: BluetoothMobileDeviceModel.kind(forModel: model) ?? .unknown,
            isConnected: false,
            appleMobileModel: model,
            isUnpairedGhost: false,
            isReadOverTheAir: true
        )
    }

    private static func validLevel(_ reading: NearbyBluetoothBatteryDevice?, now: Date) -> Int? {
        guard let reading,
              (0...100).contains(reading.batteryLevel),
              now.timeIntervalSince(reading.lastUpdated) <= BluetoothLEBatteryScanPolicy.resultLifetime else {
            return nil
        }
        return reading.batteryLevel
    }

    private static func isRecent(_ candidate: NearbyBLEDeviceCandidate, now: Date) -> Bool {
        now.timeIntervalSince(candidate.lastSeen) <= recentCandidateLifetime
    }

    private static func ranks(from order: [String]) -> [String: Int] {
        var ranks: [String: Int] = [:]
        for (index, item) in order.enumerated() {
            let key = BluetoothDeviceIdentity.preferenceKey(item)
            guard !key.isEmpty, ranks[key] == nil else { continue }
            ranks[key] = index
        }
        return ranks
    }
}
