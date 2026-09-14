import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let iconSizeRange: ClosedRange<Double> = 16...36
    static let defaultIconSize: Double = 28
    static let iconSizeDefaultsKey = "menuBarIconSize"

    static let batteryCriticalThresholdRange: ClosedRange<Double> = 0...100
    static let defaultBatteryCriticalThreshold: Double = 20
    static let batterySymbolScaleRange: ClosedRange<Double> = 0.9...1.1
    static let defaultBatterySymbolScale: Double = 1
    static let showsBatteryPercentageDefaultsKey = "showsBatteryPercentage"
    static let showsChargingIndicatorDefaultsKey = "showsChargingIndicator"
    static let usesBatteryStatusColorsDefaultsKey = "usesBatteryStatusColors"
    static let batteryCriticalThresholdDefaultsKey = "batteryCriticalThreshold"
    static let batterySymbolScaleDefaultsKey = "batterySymbolScale"

    static let outputDeviceLimitRange: ClosedRange<Int> = 1...20
    static let defaultMaxVisibleOutputDevices = 5
    static let maxVisibleOutputDevicesDefaultsKey = "maxVisibleOutputDevices"
    static let alwaysShowsAllOutputDevicesDefaultsKey = "alwaysShowsAllOutputDevices"
    static let outputDeviceOrderDefaultsKey = "outputDeviceOrder"

    @Published var iconSize: Double {
        didSet {
            let clamped = Self.clampedIconSize(iconSize)
            // 写入越界值时先夹取再落盘，夹取会再次触发 didSet，一次后收敛。
            guard clamped == iconSize else {
                iconSize = clamped
                return
            }
            defaults.set(clamped, forKey: Self.iconSizeDefaultsKey)
        }
    }

    @Published var showsBatteryPercentage: Bool {
        didSet {
            defaults.set(showsBatteryPercentage, forKey: Self.showsBatteryPercentageDefaultsKey)
        }
    }

    @Published var showsChargingIndicator: Bool {
        didSet {
            defaults.set(showsChargingIndicator, forKey: Self.showsChargingIndicatorDefaultsKey)
        }
    }

    @Published var usesBatteryStatusColors: Bool {
        didSet {
            defaults.set(usesBatteryStatusColors, forKey: Self.usesBatteryStatusColorsDefaultsKey)
        }
    }

    @Published var batterySymbolScale: Double {
        didSet {
            let clamped = Self.clampedBatterySymbolScale(batterySymbolScale)
            guard clamped == batterySymbolScale else {
                batterySymbolScale = clamped
                return
            }
            defaults.set(clamped, forKey: Self.batterySymbolScaleDefaultsKey)
        }
    }

    @Published var batteryCriticalThreshold: Double {
        didSet {
            let clamped = Self.clampedBatteryCriticalThreshold(batteryCriticalThreshold)
            guard clamped == batteryCriticalThreshold else {
                batteryCriticalThreshold = clamped
                return
            }
            defaults.set(clamped, forKey: Self.batteryCriticalThresholdDefaultsKey)
        }
    }

    @Published var maxVisibleOutputDevices: Int {
        didSet {
            let clamped = Self.clampedOutputDeviceLimit(maxVisibleOutputDevices)
            guard clamped == maxVisibleOutputDevices else {
                maxVisibleOutputDevices = clamped
                return
            }
            defaults.set(clamped, forKey: Self.maxVisibleOutputDevicesDefaultsKey)
        }
    }

    @Published var alwaysShowsAllOutputDevices: Bool {
        didSet {
            defaults.set(
                alwaysShowsAllOutputDevices,
                forKey: Self.alwaysShowsAllOutputDevicesDefaultsKey
            )
        }
    }

    @Published private(set) var outputDeviceOrder: [String] {
        didSet {
            defaults.set(outputDeviceOrder, forKey: Self.outputDeviceOrderDefaultsKey)
        }
    }

    var visibleOutputDeviceLimit: Int? {
        alwaysShowsAllOutputDevices ? nil : maxVisibleOutputDevices
    }

    func orderedOutputDevices(_ devices: [AudioOutputDevice]) -> [AudioOutputDevice] {
        guard !outputDeviceOrder.isEmpty else { return devices }

        var ranks: [String: Int] = [:]
        for (index, uid) in outputDeviceOrder.enumerated() where ranks[uid] == nil {
            ranks[uid] = index
        }

        return devices.enumerated()
            .sorted { lhs, rhs in
                let leftRank = lhs.element.uid.flatMap { ranks[$0] } ?? Int.max
                let rightRank = rhs.element.uid.flatMap { ranks[$0] } ?? Int.max
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func moveOutputDevices(
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        in devices: [AudioOutputDevice]
    ) {
        guard !source.isEmpty,
              source.allSatisfy({ devices.indices.contains($0) }),
              (0...devices.count).contains(destination) else {
            return
        }

        let movedDevices = source.map { devices[$0] }
        let remainingDevices = devices.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        let insertionOffset = destination - source.filter { $0 < destination }.count

        var reorderedDevices = remainingDevices
        reorderedDevices.insert(
            contentsOf: movedDevices,
            at: min(insertionOffset, reorderedDevices.count)
        )
        outputDeviceOrder = reorderedDevices.compactMap(\.uid)
    }

    var isBatterySymbolSizeEnabled: Bool {
        showsBatteryPercentage || showsChargingIndicator
    }

    var batteryIconOptions: BatteryIconOptions {
        BatteryIconOptions(
            showsPercentage: showsBatteryPercentage,
            showsChargingIndicator: showsChargingIndicator,
            usesStatusColors: usesBatteryStatusColors,
            criticalThreshold: Int(batteryCriticalThreshold.rounded()),
            textScale: batterySymbolScale * BatteryIconOptions.defaultTextScale
        )
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedIconSize = (defaults.object(forKey: Self.iconSizeDefaultsKey) as? NSNumber)?.doubleValue
        let storedCriticalThreshold = (defaults.object(forKey: Self.batteryCriticalThresholdDefaultsKey) as? NSNumber)?.doubleValue
        let storedBatterySymbolScale = (defaults.object(forKey: Self.batterySymbolScaleDefaultsKey) as? NSNumber)?.doubleValue
        let storedOutputDeviceLimit = (defaults.object(forKey: Self.maxVisibleOutputDevicesDefaultsKey) as? NSNumber)?.intValue
        let storedOutputDeviceOrder = defaults.stringArray(forKey: Self.outputDeviceOrderDefaultsKey) ?? []

        self.iconSize = Self.clampedIconSize(storedIconSize ?? Self.defaultIconSize)
        self.showsBatteryPercentage = defaults.object(forKey: Self.showsBatteryPercentageDefaultsKey) as? Bool ?? true
        self.showsChargingIndicator = defaults.object(forKey: Self.showsChargingIndicatorDefaultsKey) as? Bool ?? true
        self.usesBatteryStatusColors = defaults.object(forKey: Self.usesBatteryStatusColorsDefaultsKey) as? Bool ?? true
        self.batterySymbolScale = Self.clampedBatterySymbolScale(
            storedBatterySymbolScale ?? Self.defaultBatterySymbolScale
        )
        self.batteryCriticalThreshold = Self.clampedBatteryCriticalThreshold(
            storedCriticalThreshold ?? Self.defaultBatteryCriticalThreshold
        )
        self.maxVisibleOutputDevices = Self.clampedOutputDeviceLimit(
            storedOutputDeviceLimit ?? Self.defaultMaxVisibleOutputDevices
        )
        self.alwaysShowsAllOutputDevices = defaults.object(
            forKey: Self.alwaysShowsAllOutputDevicesDefaultsKey
        ) as? Bool ?? false
        self.outputDeviceOrder = storedOutputDeviceOrder
    }

    static func clampedIconSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultIconSize }
        return min(iconSizeRange.upperBound, max(iconSizeRange.lowerBound, value))
    }

    static func clampedBatterySymbolScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBatterySymbolScale }
        return min(
            batterySymbolScaleRange.upperBound,
            max(batterySymbolScaleRange.lowerBound, value)
        )
    }

    static func clampedBatteryCriticalThreshold(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBatteryCriticalThreshold }
        return min(
            batteryCriticalThresholdRange.upperBound,
            max(batteryCriticalThresholdRange.lowerBound, value)
        ).rounded()
    }

    static func clampedOutputDeviceLimit(_ value: Int) -> Int {
        min(outputDeviceLimitRange.upperBound, max(outputDeviceLimitRange.lowerBound, value))
    }
}
