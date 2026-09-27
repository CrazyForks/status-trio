import Foundation

/// What the icon-source menu offers: the featured audio-device entry, or one
/// picked device by its normalized address.
///
/// The picker binds through this value rather than the raw `String?` so the
/// menu can tag every row distinctly — `nil` cannot be a tag on its own —
/// while the store keeps the flat address form.
enum BluetoothNetworkIconSource: Hashable, Identifiable {
    case audioDevices
    case device(address: String)

    var id: String {
        switch self {
        case .audioDevices:
            ""
        case let .device(address):
            address
        }
    }
}
