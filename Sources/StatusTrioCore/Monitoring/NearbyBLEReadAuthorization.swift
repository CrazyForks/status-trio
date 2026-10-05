import Foundation

/// A read token becomes stale whenever its UUID is removed from the allowlist.
/// Re-adding the UUID does not revive a pending read from the previous grant.
struct NearbyBLEReadAuthorization {
    private(set) var allowedIDs: Set<UUID> = []
    private var revisions: [UUID: UInt64] = [:]

    mutating func update(_ ids: Set<UUID>) -> Set<UUID> {
        let removedIDs = allowedIDs.subtracting(ids)
        for id in removedIDs {
            revisions[id, default: 0] &+= 1
        }
        allowedIDs = ids
        return removedIDs
    }

    func revision(for id: UUID) -> UInt64 {
        revisions[id, default: 0]
    }

    func accepts(_ id: UUID, revision: UInt64) -> Bool {
        allowedIDs.contains(id) && revisions[id, default: 0] == revision
    }
}
