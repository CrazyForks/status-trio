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
}

struct NearbyBLEDeviceSelection: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var vendor: NearbyBLEVendor
    var model: String?
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

    private static func vendorOrder(_ vendor: NearbyBLEVendor) -> Int {
        switch vendor {
        case .apple: 0
        case .other, .unknown: 1
        }
    }
}
