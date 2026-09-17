import Foundation

struct BatteryIconOptions: Equatable, Hashable, Sendable {
    let showsPercentage: Bool
    let showsChargingIndicator: Bool
    let usesStatusColors: Bool
    let showsPercentageWhenConnected: Bool
    let criticalThreshold: Int
    let textScale: Double
    let ringStrokeScale: Double

    static let defaultTextScale = 1.8
    static let defaultRingStrokeScale = 1.25

    static let standard = BatteryIconOptions(
        showsPercentage: true,
        showsChargingIndicator: true,
        usesStatusColors: true,
        criticalThreshold: 20,
        showsPercentageWhenConnected: false,
        textScale: defaultTextScale,
        ringStrokeScale: defaultRingStrokeScale
    )

    init(
        showsPercentage: Bool = true,
        showsChargingIndicator: Bool = true,
        usesStatusColors: Bool = true,
        criticalThreshold: Int = 20,
        showsPercentageWhenConnected: Bool = false,
        textScale: Double = defaultTextScale,
        ringStrokeScale: Double = defaultRingStrokeScale
    ) {
        self.showsPercentage = showsPercentage
        self.showsChargingIndicator = showsChargingIndicator
        self.usesStatusColors = usesStatusColors
        self.showsPercentageWhenConnected = showsPercentageWhenConnected
        self.criticalThreshold = min(100, max(0, criticalThreshold))
        self.textScale = textScale.isFinite ? min(3, max(1, textScale)) : Self.defaultTextScale
        self.ringStrokeScale = ringStrokeScale.isFinite ? min(2.5, max(0.5, ringStrokeScale)) : Self.defaultRingStrokeScale
    }
}
