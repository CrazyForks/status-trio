import Foundation

public enum RingStrokeStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case light
    case regular
    case bold

    public var id: String { rawValue }

    public var scale: Double {
        switch self {
        case .light: return 1.0
        case .regular: return 1.25
        case .bold: return 1.5
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "light", "standard": self = .light
        case "regular", "normal": self = .regular
        case "bold", "heavy": self = .bold
        default: return nil
        }
    }
}
