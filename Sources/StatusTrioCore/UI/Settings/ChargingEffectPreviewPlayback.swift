import Foundation

struct ChargingEffectPreviewPlayback: Equatable, Sendable {
    static let duration: TimeInterval = 2 * ChargingEffectTimeline.steadyCycleDuration

    private(set) var startedAt: Date?

    var isPlaying: Bool {
        startedAt != nil
    }

    mutating func start(at date: Date) {
        startedAt = date
    }

    mutating func stop() {
        startedAt = nil
    }

    func phase(at date: Date) -> ChargingEffectPhase? {
        guard let startedAt else { return nil }
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed.isFinite, elapsed >= 0, elapsed < Self.duration else { return nil }
        return ChargingEffectTimeline.phase(elapsed: elapsed, kind: .steady)
    }
}
