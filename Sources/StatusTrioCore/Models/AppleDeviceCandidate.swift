import Foundation

/// Identity stays namespaced by the provider; display names are never identity.
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
    case unverifiedTrustedRoute
}

struct LegacyAppleDeviceSelection: Codable, Equatable, Identifiable, Sendable {
    let id: AppleDeviceID
    var name: String
    var model: String?
}

struct AppleDeviceCandidate: Codable, Equatable, Identifiable, Sendable {
    let id: AppleDeviceID
    var name: String
    var model: String?
    var transports: [MobileBatteryTransport]
    var trustRequired: Bool
    var evidence: AppleDeviceEvidence

    var isVerifiedTrustedAppleDevice: Bool {
        guard !trustRequired else { return false }
        let hasTrustedTransport = transports.contains(.usb) || transports.contains(.network)
        guard hasTrustedTransport else { return false }
        return switch (id, evidence) {
        case (.trustedDevice, .verifiedAppleModel): Self.isPhoneOrIPadModel(model)
        case (.trustedWatch, .verifiedAppleModel): Self.isWatchModel(model)
        case (.trustedWatch, .trustedWatchCompanion): true
        default: false
        }
    }

    private static func normalizedModel(_ model: String?) -> String {
        (model ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isPhoneOrIPadModel(_ model: String?) -> Bool {
        let value = normalizedModel(model)
        return value.hasPrefix("iphone") || value.hasPrefix("ipad")
    }

    private static func isWatchModel(_ model: String?) -> Bool {
        let value = normalizedModel(model)
        return value.hasPrefix("watch")
    }

}
