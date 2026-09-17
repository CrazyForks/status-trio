import CoreWLAN

/// Known bands only; unknown or unavailable channels remain nil.
enum WiFiFrequencyBand: Equatable, Sendable {
    case twoPointFourGHz, fiveGHz, sixGHz

    init?(coreWLANBand: CWChannelBand) {
        switch coreWLANBand {
        case .band2GHz: self = .twoPointFourGHz
        case .band5GHz: self = .fiveGHz
        case .band6GHz: self = .sixGHz
        default: return nil
        }
    }

    var gigahertz: Double {
        switch self {
        case .twoPointFourGHz: 2.4
        case .fiveGHz: 5
        case .sixGHz: 6
        }
    }
}
