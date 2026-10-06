import Foundation

struct AppleDevicePanelRow: Identifiable, Equatable, Sendable {
    let id: AppleDeviceID
    let device: BluetoothDevice
    let batteryLevel: Int?
    let status: NearbyBLEPanelRowStatus
}

enum AppleDeviceCatalog {
    struct Projection: Equatable, Sendable {
        let rows: [AppleDevicePanelRow]
        let batteryLevels: [String: BluetoothBatteryLevel]
    }

    static func projection(
        selections: [AppleDeviceSelection],
        candidates: [AppleDeviceCandidate],
        nearbyReadings: [NearbyBluetoothBatteryDevice],
        trustedSnapshots: [MobileBatterySnapshot],
        failures: Set<AppleDeviceID>,
        options: BluetoothDeviceListOptions,
        now: Date
    ) -> Projection {
        let rows = panelRows(
            selections: selections,
            candidates: candidates,
            nearbyReadings: nearbyReadings,
            trustedSnapshots: trustedSnapshots,
            failures: failures,
            options: options,
            now: now
        )
        let levels = Dictionary(rows.compactMap { row -> (String, BluetoothBatteryLevel)? in
            guard let level = row.batteryLevel else { return nil }
            return (row.device.id, BluetoothBatteryLevel(
                deviceAddress: row.device.id,
                main: level,
                left: nil,
                right: nil,
                caseLevel: nil
            ))
        }, uniquingKeysWith: { _, latest in latest })
        return Projection(rows: rows, batteryLevels: levels)
    }

    static func candidates(
        ble: [NearbyBLEDeviceCandidate],
        trusted: [AppleDeviceCandidate],
        selections: [AppleDeviceSelection]
    ) -> [AppleDeviceCandidate] {
        var values: [AppleDeviceID: AppleDeviceCandidate] = [:]
        for candidate in ble where candidate.vendor == .apple {
            let id = AppleDeviceID.ble(candidate.id)
            values[id] = AppleDeviceCandidate(
                id: id, name: candidate.name, model: nil, transports: [.bluetooth],
                trustRequired: false, evidence: .appleBluetoothCompanyID
            )
        }
        for candidate in trusted where candidate.isSelectableAppleDevice { values[candidate.id] = candidate }
        for selection in selections where values[selection.id] == nil {
            let evidence: AppleDeviceEvidence
            let transports: [MobileBatteryTransport]
            switch selection.id {
            case .ble:
                evidence = .appleBluetoothCompanyID
                transports = [.bluetooth]
            case .trustedDevice:
                evidence = .verifiedAppleModel
                transports = [.usb, .network]
            case .trustedWatch:
                evidence = .trustedWatchCompanion
                transports = [.usb, .network]
            }
            values[selection.id] = AppleDeviceCandidate(
                id: selection.id, name: selection.name, model: selection.model,
                transports: transports, trustRequired: false, evidence: evidence
            )
        }
        return values.values.sorted { $0.id.rowID < $1.id.rowID }
    }

    static func panelRows(
        selections: [AppleDeviceSelection],
        candidates: [AppleDeviceCandidate],
        nearbyReadings: [NearbyBluetoothBatteryDevice],
        trustedSnapshots: [MobileBatterySnapshot],
        failures: Set<AppleDeviceID>,
        options: BluetoothDeviceListOptions,
        now: Date
    ) -> [AppleDevicePanelRow] {
        let candidateMap = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let nearbyMap = Dictionary(nearbyReadings.map { (AppleDeviceID.ble($0.id), $0) }, uniquingKeysWith: { _, latest in latest })
        let trustedMap = Dictionary(trustedSnapshots.map { (Self.id(for: $0), $0) }, uniquingKeysWith: { _, latest in latest })
        var order: [String: Int] = [:]
        for (index, value) in options.order.enumerated() {
            let key = BluetoothDeviceIdentity.preferenceKey(value)
            if order[key] == nil { order[key] = index }
        }

        var indexedRows: [(rank: Int, index: Int, row: AppleDevicePanelRow)] = []
        for (index, selection) in selections.enumerated() {
            guard let candidate = candidateMap[selection.id], candidate.isSelectableAppleDevice else { continue }
            let device = BluetoothDevice(
                id: selection.id.rowID,
                name: selection.name,
                kind: BluetoothMobileDeviceModel.kind(forModel: selection.model ?? candidate.model) ?? .unknown,
                isConnected: false,
                appleMobileModel: selection.model ?? candidate.model,
                isReadOverTheAir: true
            )
            guard !BluetoothDeviceListPresentation.isDeviceHidden(device, options: options) else { continue }

            let level: Int?
            let status: NearbyBLEPanelRowStatus
            switch selection.id {
            case let .ble(id):
                let reading = nearbyMap[.ble(id)]
                let valid = reading.flatMap { (0...100).contains($0.batteryLevel) && now.timeIntervalSince($0.lastUpdated) <= BluetoothLEBatteryScanPolicy.resultLifetime ? $0.batteryLevel : nil }
                level = valid
                status = valid.map { NearbyBLEPanelRowStatus.battery($0) } ?? (failures.contains(selection.id) ? .unavailable : .notNearby)
            case .trustedDevice, .trustedWatch:
                level = trustedMap[selection.id]?.batteryLevel
                status = level.map { NearbyBLEPanelRowStatus.battery($0) } ?? (failures.contains(selection.id) ? .unavailable : .notNearby)
            }
            let rank = order[BluetoothDeviceIdentity.preferenceKey(device.id)] ?? Int.max
            let row = AppleDevicePanelRow(id: selection.id, device: device, batteryLevel: level, status: status)
            indexedRows.append((rank: rank, index: index, row: row))
        }
        indexedRows.sort { lhs, rhs in
            lhs.rank == rhs.rank ? lhs.index < rhs.index : lhs.rank < rhs.rank
        }
        return indexedRows.map(\.row)
    }

    static func rowIdentityMap(_ rows: [AppleDevicePanelRow]) -> [String: AppleDeviceID] {
        Dictionary(rows.map { ($0.device.id, $0.id) }, uniquingKeysWith: { first, _ in first })
    }

    private static func id(for snapshot: MobileBatterySnapshot) -> AppleDeviceID {
        if let parentID = snapshot.parentID { .trustedWatch(parentID: parentID, id: snapshot.id) }
        else { .trustedDevice(snapshot.id) }
    }
}
