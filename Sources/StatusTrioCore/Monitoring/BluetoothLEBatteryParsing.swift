import Foundation

enum BluetoothLEBatteryParsing {
    static func percentage(_ data: Data) -> Int? {
        guard data.count == 1, let value = data.first, value <= 100 else {
            return nil
        }
        return Int(value)
    }

    static func deviceInfo(_ data: Data) -> String? {
        guard let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }

        let withoutNulls = decoded.replacingOccurrences(of: "\0", with: "")
        let trimmed = withoutNulls.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
