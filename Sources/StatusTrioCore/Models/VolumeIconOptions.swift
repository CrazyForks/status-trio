import Foundation

public enum VolumeDisplayStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case dots
    case arc

    public var id: String { rawValue }
}

public struct VolumeIconOptions: Equatable, Hashable, Sendable {
    public let displayStyle: VolumeDisplayStyle
    public let ringStrokeScale: Double

    public static let defaultRingStrokeScale: Double = 1.25

    public static let standard = VolumeIconOptions(displayStyle: .dots, ringStrokeScale: defaultRingStrokeScale)

    public init(
        displayStyle: VolumeDisplayStyle = .dots,
        ringStrokeScale: Double = defaultRingStrokeScale
    ) {
        self.displayStyle = displayStyle
        self.ringStrokeScale = ringStrokeScale.isFinite ? min(2.5, max(0.5, ringStrokeScale)) : Self.defaultRingStrokeScale
    }
}
