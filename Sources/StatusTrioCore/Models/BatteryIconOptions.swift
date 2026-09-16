import Foundation

struct BatteryIconOptions: Equatable, Hashable, Sendable {
    let showsPercentage: Bool
    let showsChargingIndicator: Bool
    let usesStatusColors: Bool
    let showsPlugForConnectedPower: Bool
    let criticalThreshold: Int
    let textScale: Double

    static let defaultTextScale = 1.8

    static let standard = BatteryIconOptions(
        showsPercentage: true,
        showsChargingIndicator: true,
        usesStatusColors: true,
        criticalThreshold: 20,
        showsPlugForConnectedPower: true,
        textScale: defaultTextScale
    )

    init(
        showsPercentage: Bool,
        showsChargingIndicator: Bool,
        usesStatusColors: Bool,
        criticalThreshold: Int,
        showsPlugForConnectedPower: Bool = true,
        textScale: Double = defaultTextScale
    ) {
        self.showsPercentage = showsPercentage
        self.showsChargingIndicator = showsChargingIndicator
        self.usesStatusColors = usesStatusColors
        self.showsPlugForConnectedPower = showsPlugForConnectedPower
        self.criticalThreshold = min(100, max(0, criticalThreshold))
        self.textScale = textScale.isFinite ? min(3, max(1, textScale)) : Self.defaultTextScale
    }
}
