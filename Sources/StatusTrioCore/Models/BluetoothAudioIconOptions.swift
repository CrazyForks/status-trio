import Foundation

struct BluetoothAudioIconOptions: Equatable, Hashable, Sendable {
    static let defaultSymbolScale: Double = 1.6

    let replacesNetworkIcon: Bool
    let usesVolumeColor: Bool
    let prioritizesNetworkErrors: Bool
    let symbolScale: Double

    static let standard = BluetoothAudioIconOptions(
        replacesNetworkIcon: false,
        usesVolumeColor: false,
        prioritizesNetworkErrors: true,
        symbolScale: defaultSymbolScale
    )

    init(
        replacesNetworkIcon: Bool = false,
        usesVolumeColor: Bool = false,
        prioritizesNetworkErrors: Bool = true,
        symbolScale: Double = Self.defaultSymbolScale
    ) {
        self.replacesNetworkIcon = replacesNetworkIcon
        self.usesVolumeColor = usesVolumeColor
        self.prioritizesNetworkErrors = prioritizesNetworkErrors
        self.symbolScale = symbolScale
    }
}
