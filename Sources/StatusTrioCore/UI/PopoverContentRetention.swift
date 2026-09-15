import Foundation

/// Decides when a closed popover may release its content: only once it has stayed
/// closed for `releaseDelay`, so a quick reopen reuses what is already built.
struct PopoverContentRetention {
    let releaseDelay: TimeInterval
    private var closedAt: Date?

    init(releaseDelay: TimeInterval) {
        self.releaseDelay = releaseDelay
    }

    mutating func markOpened() {
        closedAt = nil
    }

    mutating func markClosed(at now: Date) {
        closedAt = now
    }

    func shouldRelease(at now: Date) -> Bool {
        guard let closedAt else { return false }
        return now.timeIntervalSince(closedAt) >= releaseDelay
    }
}
