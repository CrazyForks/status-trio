import Foundation

/// Identity remains namespaced by the transport/provider that can authorize it.
enum AppleDeviceID: Codable, Hashable, Sendable {
    case ble(UUID)
    case trustedDevice(String)
    case trustedWatch(parentID: String, id: String)

    var rowID: String {
        switch self {
        case let .ble(id): BluetoothDeviceIdentity.bleRowID(id)
        case let .trustedDevice(id):
            MobileBatteryDeviceMerge.externalDeviceID(for: "phone:\(id)")
        case let .trustedWatch(parentID, id):
            MobileBatteryDeviceMerge.externalDeviceID(for: "watch:\(parentID):\(id)")
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, id, parentID }
    private enum Kind: String, Codable { case ble, trustedDevice, trustedWatch }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .ble: self = .ble(try values.decode(UUID.self, forKey: .id))
        case .trustedDevice: self = .trustedDevice(try values.decode(String.self, forKey: .id))
        case .trustedWatch:
            self = .trustedWatch(
                parentID: try values.decode(String.self, forKey: .parentID),
                id: try values.decode(String.self, forKey: .id)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .ble(id):
            try values.encode(Kind.ble, forKey: .kind)
            try values.encode(id, forKey: .id)
        case let .trustedDevice(id):
            try values.encode(Kind.trustedDevice, forKey: .kind)
            try values.encode(id, forKey: .id)
        case let .trustedWatch(parentID, id):
            try values.encode(Kind.trustedWatch, forKey: .kind)
            try values.encode(parentID, forKey: .parentID)
            try values.encode(id, forKey: .id)
        }
    }
}

/// Evidence is machine-derived. Names are intentionally absent from this decision.
enum AppleDeviceEvidence: String, Codable, Sendable {
    case appleBluetoothCompanyID
    case verifiedAppleModel
    case trustedWatchCompanion
}

struct AppleDeviceSelection: Codable, Equatable, Identifiable, Sendable {
    let id: AppleDeviceID
    var name: String
    var model: String?
}

struct AppleDeviceCandidate: Equatable, Identifiable, Sendable {
    let id: AppleDeviceID
    var name: String
    var model: String?
    var transports: [MobileBatteryTransport]
    var trustRequired: Bool
    var evidence: AppleDeviceEvidence

    var selection: AppleDeviceSelection {
        AppleDeviceSelection(id: id, name: name, model: model)
    }

    var isSelectableAppleDevice: Bool {
        guard !transports.isEmpty else { return false }
        return switch (id, evidence) {
        case (.ble, .appleBluetoothCompanyID): true
        case (.trustedDevice, .verifiedAppleModel), (.trustedWatch, .verifiedAppleModel),
             (.trustedWatch, .trustedWatchCompanion): true
        default: false
        }
    }
}
