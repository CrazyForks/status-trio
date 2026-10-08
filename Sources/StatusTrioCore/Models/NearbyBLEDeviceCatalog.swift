import Foundation

struct NearbyBLEPanelRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let device: BluetoothDevice
    let batteryLevel: Int?
    let wasSeenRecently: Bool
    let readFailed: Bool
    var batteryLevelsEnabled = true
    var observedAt: Date? = nil

    var status: NearbyBLEPanelRowStatus {
        if let batteryLevel { return .battery(batteryLevel) }
        if readFailed { return .unavailable }
        return wasSeenRecently ? .pending : .notNearby
    }

    var presentationStatus: NearbyBLEPanelRowStatus? {
        batteryLevelsEnabled ? status : nil
    }
}

enum NearbyBLEPanelRowStatus: Equatable, Sendable {
    case battery(Int)
    case unavailable
    case notNearby
    case pending
}

enum NearbyBLEDeviceCatalog {
    static let recentCandidateLifetime = BluetoothLEBatteryScanPolicy.resultLifetime

    /// Rows shown in Settings, in the user's saved order. BLE UUID identity
    /// remains separate from any same-named system Bluetooth row.
    static func settingsDevices(
        _ devices: [BluetoothDevice],
        selections: [NearbyBLEDeviceSelection],
        now: Date = Date()
    ) -> [BluetoothDevice] {
        devices.filter { !$0.isUnpairedGhost } + selections.filter {
            $0.vendor == .apple && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && isVerifiedAndFresh($0, now: now)
        }.map { selection in
            device(
                id: selection.id,
                name: selection.name,
                model: selection.model
            )
        }
    }

    static func discoveredAppleMetadata(
        from candidates: [NearbyBLEDeviceCandidate],
        existing: [NearbyBLEDeviceSelection]
    ) -> [NearbyBLEDeviceSelection] {
        var byID: [UUID: NearbyBLEDeviceSelection] = [:]
        var orderedIDs: [UUID] = []
        for selection in existing {
            if var saved = byID[selection.id] {
                if saved.model == nil { saved.model = selection.model }
                byID[selection.id] = saved
            } else {
                byID[selection.id] = selection
                orderedIDs.append(selection.id)
            }
        }
        for candidate in candidates where candidate.vendor == .apple &&
            !candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if var saved = byID[candidate.id] {
                saved.name = candidate.name
                saved.vendor = candidate.vendor
                byID[candidate.id] = saved
            } else {
                byID[candidate.id] = NearbyBLEDeviceSelection(
                    id: candidate.id,
                    name: candidate.name,
                    vendor: candidate.vendor,
                    model: nil
                )
                orderedIDs.append(candidate.id)
            }
        }
        return orderedIDs.compactMap { byID[$0] }
    }

    /// Rows created by successful battery reads remain available across scans;
    /// candidate-only advertisements do not enter persisted selections.
    static func settingsCandidates(
        selections: [NearbyBLEDeviceSelection],
        now: Date = Date()
    ) -> [NearbyBLEDeviceCandidate] {
        return selections.filter { $0.vendor == .apple && isVerifiedAndFresh($0, now: now) }
            .map { selection in
                NearbyBLEDeviceCandidate(
                    id: selection.id,
                    name: selection.name,
                    vendor: .apple,
                    lastSeen: selection.batteryLastUpdated ?? .distantPast
                )
            }
    }

    static func nextVerifiedRowExpiration(
        selections: [NearbyBLEDeviceSelection],
        now: Date = Date()
    ) -> Date? {
        selections.compactMap { selection -> Date? in
            guard selection.vendor == .apple,
                  let level = selection.batteryLevel,
                  (0...100).contains(level),
                  let timestamp = selection.batteryLastUpdated else { return nil }
            return timestamp.addingTimeInterval(BluetoothLEBatteryScanPolicy.resultLifetime)
        }.filter { $0 > now }.min()
    }

    /// Projects battery-verified Apple UUID metadata into panel rows.
    static func panelRows(
        selections: [NearbyBLEDeviceSelection],
        readings: [NearbyBluetoothBatteryDevice],
        failures: Set<UUID>,
        options: BluetoothDeviceListOptions,
        now: Date,
        batteryLevelsEnabled: Bool = true
    ) -> [NearbyBLEPanelRow] {
        let readingsByID = Dictionary(readings.map { ($0.id, $0) }, uniquingKeysWith: { older, newer in
            older.lastUpdated >= newer.lastUpdated ? older : newer
        })
        let orderRanks = ranks(from: options.order)

        let indexedRows: [(Int, NearbyBLEPanelRow)] = selections.enumerated().compactMap { element in
            let (index, selection) = element
            guard selection.vendor == .apple,
                  isVerifiedAndFresh(selection, now: now) else { return nil }
            let row = device(
                id: selection.id,
                name: selection.name,
                model: selection.model ?? readingsByID[selection.id]?.model
            )
            guard !BluetoothDeviceListPresentation.isDeviceHidden(row, options: options) else { return nil }
            return (index, NearbyBLEPanelRow(
                id: selection.id,
                device: row,
                batteryLevel: validLevel(selection, reading: readingsByID[selection.id], now: now),
                wasSeenRecently: false,
                readFailed: failures.contains(selection.id),
                batteryLevelsEnabled: batteryLevelsEnabled,
                observedAt: readingsByID[selection.id]?.lastUpdated ?? selection.batteryLastUpdated
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

    private static func validLevel(
        _ selection: NearbyBLEDeviceSelection,
        reading: NearbyBluetoothBatteryDevice?,
        now: Date
    ) -> Int? {
        if let reading,
           (0...100).contains(reading.batteryLevel),
           now.timeIntervalSince(reading.lastUpdated) <= BluetoothLEBatteryScanPolicy.resultLifetime {
            return reading.batteryLevel
        }
        guard let batteryLevel = selection.batteryLevel,
              (0...100).contains(batteryLevel) else { return nil }
        return batteryLevel
    }

    private static func isVerifiedAndFresh(_ selection: NearbyBLEDeviceSelection, now: Date) -> Bool {
        guard let batteryLastUpdated = selection.batteryLastUpdated else { return false }
        return now.timeIntervalSince(batteryLastUpdated) <= BluetoothLEBatteryScanPolicy.resultLifetime
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
