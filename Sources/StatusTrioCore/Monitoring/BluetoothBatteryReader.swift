import Foundation

struct BluetoothBatteryLevel: Equatable, Sendable {
    let deviceAddress: String
    let main: Int?
    let left: Int?
    let right: Int?
    let caseLevel: Int?

    var summary: String? {
        var components: [String] = []
        if let main {
            components.append("\(main)%")
        }
        if let left {
            components.append("L \(left)%")
        }
        if let right {
            components.append("R \(right)%")
        }
        if let caseLevel {
            components.append("Case \(caseLevel)%")
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }
}

protocol BluetoothBatteryReading: AnyObject {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]) -> Void)
}

enum BluetoothBatteryReader {
    static func normalizedAddress(_ address: String) -> String {
        address
            .filter(\.isHexDigit)
            .uppercased()
    }

    static func parse(json: Data) -> [String: BluetoothBatteryLevel] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else {
            return [:]
        }

        var levels: [String: BluetoothBatteryLevel] = [:]
        for section in sections {
            for collectionKey in ["device_connected", "device_not_connected"] {
                guard let devices = section[collectionKey] as? [[String: Any]] else { continue }
                for entry in devices {
                    for value in entry.values {
                        guard let properties = value as? [String: Any],
                              let address = properties["device_address"] as? String,
                              !address.isEmpty else {
                            continue
                        }
                        let main = percentage(properties["device_batteryLevelMain"])
                            ?? percentage(properties["device_batteryLevel"])
                        let level = BluetoothBatteryLevel(
                            deviceAddress: address,
                            main: main,
                            left: percentage(properties["device_batteryLevelLeft"]),
                            right: percentage(properties["device_batteryLevelRight"]),
                            caseLevel: percentage(properties["device_batteryLevelCase"])
                        )
                        guard level.summary != nil else { continue }
                        levels[normalizedAddress(address)] = level
                    }
                }
            }
        }
        return levels
    }

    private static func percentage(_ value: Any?) -> Int? {
        let number: Double
        switch value {
        case let value as NSNumber:
            number = value.doubleValue
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let withoutPercent = trimmed.hasSuffix("%")
                ? String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                : trimmed
            guard let parsed = Double(withoutPercent) else { return nil }
            number = parsed
        default:
            return nil
        }

        guard number.isFinite,
              number.rounded() == number,
              (0...100).contains(number) else {
            return nil
        }
        return Int(number)
    }
}

final class SystemProfilerBluetoothBatteryWorker: @unchecked Sendable, BluetoothBatteryReading {
    typealias OutputProvider = @Sendable () -> Data?
    private let queue = DispatchQueue(label: "StatusTrio.SystemProfilerBluetoothBatteryWorker")
    private let outputProvider: OutputProvider
    private let reportCache: BluetoothProfilerReportCache

    init(
        outputProvider: @escaping OutputProvider = SystemProfilerBluetoothBatteryWorker.readSystemProfilerOutput,
        reportCache: BluetoothProfilerReportCache = .shared
    ) {
        self.outputProvider = outputProvider
        self.reportCache = reportCache
    }

    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]) -> Void) {
        queue.async {
            guard let data = self.reportCache.freshData() ?? self.outputProvider() else {
                completion([:])
                return
            }
            self.reportCache.store(data)
            completion(BluetoothBatteryReader.parse(json: data))
        }
    }

    static func readSystemProfilerOutput() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPBluetoothDataType"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }
}
