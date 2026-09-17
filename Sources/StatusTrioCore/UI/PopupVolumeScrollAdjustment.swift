import Foundation

struct PopupVolumeScrollAdjustment {
    private static let preciseVolumePerPoint = 0.002
    private static let discreteVolumePerLine = 0.02

    func volumeDelta(
        deltaY: Double,
        isPrecise: Bool,
        isDirectionInverted: Bool,
        usesNaturalScrolling: Bool
    ) -> Double? {
        guard deltaY.isFinite, deltaY != 0 else { return nil }

        let volumePerUnit = isPrecise
            ? Self.preciseVolumePerPoint
            : Self.discreteVolumePerLine
        let scrollUpDelta = usesNaturalScrolling
            ? (isDirectionInverted ? -deltaY : deltaY)
            : deltaY
        return scrollUpDelta * volumePerUnit
    }
}

struct PopupVolumeScrollSession {
    static let timeout: TimeInterval = 0.75

    private var targetScalar: Double?
    private var lastTimestamp: TimeInterval?
    private var requestedUnmute = false

    mutating func scalar(
        at timestamp: TimeInterval,
        fallback: Double?
    ) -> Double? {
        if let lastTimestamp,
           timestamp < lastTimestamp
            || timestamp - lastTimestamp > Self.timeout {
            reset()
        }
        self.lastTimestamp = timestamp

        if let targetScalar {
            return targetScalar
        }
        guard let fallback, fallback.isFinite else { return nil }

        let clampedScalar = Self.clamp(fallback)
        targetScalar = clampedScalar
        return clampedScalar
    }

    mutating func applying(delta: Double, to scalar: Double) -> Double {
        let adjustedScalar = Self.clamp(scalar + delta)
        targetScalar = adjustedScalar
        return adjustedScalar
    }

    mutating func shouldUnmute(isMuted: Bool, isIncreasing: Bool) -> Bool {
        guard isMuted, isIncreasing, !requestedUnmute else { return false }
        requestedUnmute = true
        return true
    }

    mutating func reset() {
        targetScalar = nil
        lastTimestamp = nil
        requestedUnmute = false
    }

    private static func clamp(_ scalar: Double) -> Double {
        min(1, max(0, scalar))
    }
}
