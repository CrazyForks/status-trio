import Foundation

/// Keeps one CoreBluetooth session per UUID and blocks reuse until asynchronous
/// cancellation reaches its terminal callback.
struct NearbyBLESessionCancellationGate {
    private var active: [UUID: UUID] = [:]
    private var cancelling: [UUID: UUID] = [:]

    mutating func begin(_ id: UUID, session: UUID) -> Bool {
        guard active[id] == nil, cancelling[id] == nil else { return false }
        active[id] = session
        return true
    }

    func isCurrent(_ id: UUID, session: UUID) -> Bool {
        active[id] == session
    }

    mutating func retire(_ id: UUID, session: UUID) -> Bool {
        guard active[id] == session else { return false }
        active.removeValue(forKey: id)
        cancelling[id] = session
        return true
    }

    mutating func finishActive(_ id: UUID, session: UUID) -> Bool {
        guard active[id] == session else { return false }
        active.removeValue(forKey: id)
        return true
    }

    mutating func finishCancellation(_ id: UUID, session: UUID) -> Bool {
        guard cancelling[id] == session else { return false }
        cancelling.removeValue(forKey: id)
        return true
    }

    func isCancelling(_ id: UUID, session: UUID) -> Bool {
        cancelling[id] == session
    }
}
