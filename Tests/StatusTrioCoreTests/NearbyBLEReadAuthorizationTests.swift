import Foundation
import Testing
@testable import StatusTrioCore

struct NearbyBLEReadAuthorizationTests {
    @Test func reselectingDoesNotAcceptAnOldRead() {
        let id = UUID()
        var gate = NearbyBLEReadAuthorization()
        _ = gate.update([id])
        let revision = gate.revision(for: id)
        #expect(gate.accepts(id, revision: revision))
        let revoked = gate.update([])
        #expect(revoked == [id])
        _ = gate.update([id])
        #expect(!gate.accepts(id, revision: revision))
    }

    @Test func revokingOneIDLeavesAnotherReadAuthorized() {
        let first = UUID()
        let second = UUID()
        var gate = NearbyBLEReadAuthorization()
        _ = gate.update([first, second])
        let secondRevision = gate.revision(for: second)

        let revoked = gate.update([second])
        #expect(revoked == [first])
        #expect(gate.accepts(second, revision: secondRevision))
    }

    @Test func unchangedPermissionsKeepActiveReadRevisions() {
        let id = UUID()
        var gate = NearbyBLEReadAuthorization()
        _ = gate.update([id])
        let revision = gate.revision(for: id)

        let revoked = gate.update([id])
        #expect(revoked.isEmpty)
        #expect(gate.accepts(id, revision: revision))
    }
}
