import Foundation

enum NearbyBLEVendor: String, Codable, Sendable {
    case apple
    case other
    case unknown

    static func fromManufacturerData(_ data: Data?) -> NearbyBLEVendor {
        guard let data, data.count >= 2 else { return .unknown }
        let companyID = UInt16(data[data.startIndex]) | UInt16(data[data.startIndex + 1]) << 8
        return companyID == 0x004C ? .apple : .other
    }
}

struct NearbyBLEDeviceCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var vendor: NearbyBLEVendor
    var lastSeen: Date

    func displayName(fallback: String) -> String {
        NearbyBLEDiscoveryPresentation.displayNames([self], fallback: fallback)[id] ?? fallback
    }

    func wasSeenRecently(now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastSeen) <= NearbyBLEDeviceCatalog.recentCandidateLifetime
    }
}

struct NearbyBLEDeviceSelection: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var vendor: NearbyBLEVendor
    var model: String?
    var batteryLevel: Int? = nil
    var batteryLastUpdated: Date? = nil
}

enum NearbyBLEDiscoveryPresentation {
    static func ordered(_ candidates: [NearbyBLEDeviceCandidate]) -> [NearbyBLEDeviceCandidate] {
        candidates.sorted { lhs, rhs in
            let leftGroup = vendorOrder(lhs.vendor)
            let rightGroup = vendorOrder(rhs.vendor)
            guard leftGroup == rightGroup else { return leftGroup < rightGroup }
            let leftName = lhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let rightName = rhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let comparison = leftName.localizedCaseInsensitiveCompare(rightName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func displayNames(
        _ candidates: [NearbyBLEDeviceCandidate],
        fallback: String
    ) -> [UUID: String] {
        let baseNames = candidates.map { candidate in
            let trimmed = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return (candidate.id, trimmed.isEmpty ? fallback : trimmed, trimmed.isEmpty)
        }
        var counts: [String: Int] = [:]
        for (_, name, _) in baseNames {
            let key = name.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            counts[key, default: 0] += 1
        }
        return Dictionary(uniqueKeysWithValues: baseNames.map { id, name, wasBlank in
            let key = name.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            let shouldAddSuffix = wasBlank || counts[key, default: 0] > 1
            let suffix = String(id.uuidString.suffix(4))
            return (id, shouldAddSuffix ? "\(name) · \(suffix)" : name)
        })
    }

    private static func vendorOrder(_ vendor: NearbyBLEVendor) -> Int {
        switch vendor {
        case .apple: 0
        case .other, .unknown: 1
        }
    }
}

struct NearbyBLECandidateCache {
    private var values: [UUID: NearbyBLEDeviceCandidate] = [:]
    private var observedInCurrentScan = Set<UUID>()

    var candidates: [NearbyBLEDeviceCandidate] {
        NearbyBLEDiscoveryPresentation.ordered(Array(values.values))
    }

    var nextExpiration: Date? {
        values.values.map { $0.lastSeen.addingTimeInterval(NearbyBLEDeviceCatalog.recentCandidateLifetime) }.min()
    }

    mutating func beginScan() {
        observedInCurrentScan.removeAll(keepingCapacity: true)
    }

    mutating func record(_ candidate: NearbyBLEDeviceCandidate) {
        values[candidate.id] = candidate
        observedInCurrentScan.insert(candidate.id)
    }

    mutating func finishScan(at now: Date) -> [NearbyBLEDeviceCandidate] {
        values = values.filter { id, candidate in
            observedInCurrentScan.contains(id)
                && now.timeIntervalSince(candidate.lastSeen) <= NearbyBLEDeviceCatalog.recentCandidateLifetime
        }
        observedInCurrentScan.removeAll(keepingCapacity: true)
        return candidates
    }

    mutating func expire(at now: Date) -> [NearbyBLEDeviceCandidate] {
        values = values.filter {
            now.timeIntervalSince($0.value.lastSeen) <= NearbyBLEDeviceCatalog.recentCandidateLifetime
        }
        return candidates
    }

    mutating func clear() -> [NearbyBLEDeviceCandidate] {
        values.removeAll(keepingCapacity: false)
        observedInCurrentScan.removeAll(keepingCapacity: false)
        return []
    }
}
