import Foundation

public enum VolumeDisplayStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case dots
    case arc

    public var id: String { rawValue }
}

public struct VolumeIconOptions: Equatable, Hashable, Sendable {
    public let displayStyle: VolumeDisplayStyle

    public static let standard = VolumeIconOptions(displayStyle: .dots)

    public init(displayStyle: VolumeDisplayStyle = .dots) {
        self.displayStyle = displayStyle
    }
}
