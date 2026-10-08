import Foundation

enum BluetoothDeviceIdentity {
    private static let blePrefix = "ble:"

    static func bleRowID(_ id: UUID) -> String {
        "\(blePrefix)\(id.uuidString.lowercased())"
    }

    static func bleUUID(from rowID: String) -> UUID? {
        guard rowID.hasPrefix(blePrefix) else { return nil }
        return UUID(uuidString: String(rowID.dropFirst(blePrefix.count)))
    }

    static func preferenceKey(_ rowID: String) -> String {
        if let id = bleUUID(from: rowID) { return bleRowID(id) }
        if rowID.hasPrefix("mobile-") { return BluetoothBatteryReader.normalizedAddress(rowID) }
        return BluetoothBatteryReader.normalizedAddress(rowID)
    }
}
