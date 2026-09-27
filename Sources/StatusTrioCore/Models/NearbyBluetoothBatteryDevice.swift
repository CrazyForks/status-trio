import Foundation

struct NearbyBluetoothBatteryDevice: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var batteryLevel: Int
    var model: String?
    var manufacturer: String?
    var lastUpdated: Date

    func displayName(fallback: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? fallback : trimmedName
    }
}
