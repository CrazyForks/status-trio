import Foundation
import IOKit
import IOKit.ps

struct BatteryPowerSample: Equatable, Sendable {
    let volts: Double
    let amps: Double
    let updatedAt: Date
    var watts: Double { volts * amps }
}

struct BatteryDetails: Equatable, Sendable {
    var adapterWatts: Int?
    var remainingMinutes: Int?
    var cycleCount: Int?
    var power: BatteryPowerSample?
}

/// A small immutable context, so a percentage update does not restart detail collection.
struct BatteryPowerState: Hashable, Sendable {
    let isPresent: Bool
    let isConnected: Bool
    let isCharging: Bool

    init(_ battery: BatteryStatus) {
        isPresent = battery.isPresent
        isConnected = battery.isConnectedToPower
        isCharging = battery.isCharging
    }
}

struct BatteryDetailsReader: Sendable {
    func read(state: BatteryPowerState, notBefore: Date?) -> BatteryDetails {
        let now = Date()
        let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        var registry: [String: Any] = [:]
        if service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS {
                registry = properties?.takeRetainedValue() as? [String: Any] ?? [:]
            }
        }
        return Self.parse(
            registry: registry,
            adapterWatts: adapter?[kIOPSPowerAdapterWattsKey] as? Int,
            remainingSeconds: IOPSGetTimeRemainingEstimate(),
            state: state,
            now: now,
            notBefore: notBefore
        )
    }

    /// IORegistry is public, but these AppleSmartBattery properties are best-effort,
    /// not a stable cross-model API. Never combine values from nested telemetry sources.
    static func parse(
        registry: [String: Any], adapterWatts: Int?, remainingSeconds: Double,
        state: BatteryPowerState, now: Date, notBefore: Date? = nil
    ) -> BatteryDetails {
        guard state.isPresent else { return BatteryDetails() }
        var result = BatteryDetails(
            adapterWatts: state.isConnected ? adapterWatts.flatMap { $0 > 0 ? $0 : nil } : nil,
            remainingMinutes: !state.isConnected && remainingSeconds.isFinite && remainingSeconds >= 60
                && remainingSeconds < Double(Int.max) ? Int(remainingSeconds / 60) : nil,
            cycleCount: (registry["CycleCount"] as? Int).flatMap { $0 >= 0 ? $0 : nil }
        )
        guard let millivolts = (registry["Voltage"] as? NSNumber)?.doubleValue,
              let current = registry["Amperage"] as? NSNumber,
              CFGetTypeID(current) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: current.objCType)),
              let timestamp = (registry["UpdateTime"] as? NSNumber)?.doubleValue,
              let connected = registry["ExternalConnected"] as? Bool,
              let charging = registry["IsCharging"] as? Bool,
              connected == state.isConnected, charging == state.isCharging,
              millivolts.isFinite, timestamp.isFinite,
              (1_000...30_000).contains(millivolts)
        else { return result }
        // Some IORegistry producers wrap negative current in an unsigned 64-bit
        // NSNumber. Interpret the integer bit pattern, then bound the result.
        let milliamps = Double(current.int64Value)
        guard abs(milliamps) <= 30_000,
              // Zero after a power transition is ambiguous, not evidence of zero consumption.
              milliamps != 0,
              milliamps > 0 ? (connected && charging) : !charging
        else { return result }
        let updatedAt = Date(timeIntervalSince1970: timestamp)
        let age = now.timeIntervalSince(updatedAt)
        guard (-5...90).contains(age), notBefore.map({ updatedAt >= $0 }) ?? true else { return result }
        result.power = BatteryPowerSample(volts: millivolts / 1_000, amps: milliamps / 1_000, updatedAt: updatedAt)
        return result
    }
}
