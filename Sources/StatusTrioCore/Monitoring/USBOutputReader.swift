import Foundation

/// A USB / Thunderbolt port that is currently sourcing power to an accessory.
/// `AppleSmartBattery.PowerOutDetails` reports milliwatts per port; the key is
/// absent when nothing is attached.
struct USBOutputSample: Equatable, Sendable {
    let watts: Double
    let readAt: Date
    let portCount: Int

    func isFresh(at now: Date, notBefore: Date? = nil) -> Bool {
        let age = now.timeIntervalSince(readAt)
        return (-5...30).contains(age) && (notBefore.map { readAt >= $0 } ?? true)
    }
}

enum USBOutputReader {
    /// Ports that are powering an accessory, summed into one output reading.
    /// Values outside a plausible single-port envelope are treated as "this key
    /// is not a live output reading" rather than as power.
    static func parse(registry: [String: Any], now: Date = Date()) -> USBOutputSample? {
        guard let ports = registry["PowerOutDetails"] as? [[String: Any]], !ports.isEmpty else { return nil }
        var total = 0.0
        var counted = 0
        for port in ports {
            guard let milliwatts = number(port["Watts"]) ?? number(port["PDPowermW"]) else { continue }
            let watts = milliwatts / 1_000
            guard watts.isFinite, (0...150).contains(watts) else { continue }
            total += watts
            counted += 1
        }
        guard counted > 0, total <= 300 else { return nil }
        return USBOutputSample(watts: total, readAt: now, portCount: counted)
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        default: return nil
        }
    }
}
