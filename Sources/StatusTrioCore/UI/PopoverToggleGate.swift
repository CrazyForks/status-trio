import Foundation

/// Allows the first toggle through immediately and ignores repeats that arrive
/// within `lockout`, so rapid clicking cannot thrash the popover.
struct PopoverToggleGate {
    let lockout: TimeInterval
    private var lastAccepted: Date?

    init(lockout: TimeInterval) {
        self.lockout = lockout
    }

    mutating func shouldAccept(at now: Date) -> Bool {
        if let lastAccepted, now.timeIntervalSince(lastAccepted) < lockout {
            return false
        }
        lastAccepted = now
        return true
    }
}
