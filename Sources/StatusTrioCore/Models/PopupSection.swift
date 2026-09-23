import Foundation

enum PopupSection: String, CaseIterable, Identifiable, Sendable {
    case battery
    case network
    case vpn
    case bluetooth
    case volume

    var id: Self { self }

    var titleKey: LocalizationKey {
        switch self {
        case .battery: .settingsPopupOrderBattery
        case .network: .wifiTitle
        case .vpn: .vpnTitle
        case .bluetooth: .bluetoothTitle
        case .volume: .settingsPopupOrderVolume
        }
    }

    var systemImage: String {
        switch self {
        case .battery: "battery.100percent"
        case .network: "wifi"
        case .vpn: "lock.shield"
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .volume: "speaker.wave.2"
        }
    }
}
