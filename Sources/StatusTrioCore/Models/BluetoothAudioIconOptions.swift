import Foundation

struct BluetoothAudioIconOptions: Equatable, Hashable, Sendable {
    let replacesNetworkIcon: Bool
    let usesVolumeColor: Bool
    let prioritizesNetworkErrors: Bool

    static let standard = BluetoothAudioIconOptions(
        replacesNetworkIcon: false,
        usesVolumeColor: false,
        prioritizesNetworkErrors: true
    )

    init(
        replacesNetworkIcon: Bool = false,
        usesVolumeColor: Bool = false,
        prioritizesNetworkErrors: Bool = true
    ) {
        self.replacesNetworkIcon = replacesNetworkIcon
        self.usesVolumeColor = usesVolumeColor
        self.prioritizesNetworkErrors = prioritizesNetworkErrors
    }
}
