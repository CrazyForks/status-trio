import Foundation
import Testing
@testable import StatusTrioCore

struct NearbyBLESessionLifecycleTests {
    @Test func revokedUUIDCannotStartANewSessionUntilCancellationDrains() {
        var lifecycle = NearbyBLESessionCancellationGate()
        let id = UUID()
        let oldSession = UUID()
        let newSession = UUID()

        let beganOld = lifecycle.begin(id, session: oldSession)
        #expect(beganOld)
        let retiredOld = lifecycle.retire(id, session: oldSession)
        #expect(retiredOld)
        #expect(!lifecycle.isCurrent(id, session: oldSession))
        let beganDuringCancellation = lifecycle.begin(id, session: newSession)
        #expect(!beganDuringCancellation)

        let drainedOld = lifecycle.finishCancellation(id, session: oldSession)
        #expect(drainedOld)
        let beganNew = lifecycle.begin(id, session: newSession)
        #expect(beganNew)
        #expect(!lifecycle.isCurrent(id, session: oldSession))
        #expect(lifecycle.isCurrent(id, session: newSession))
        let duplicateOldDisconnect = lifecycle.finishCancellation(id, session: oldSession)
        #expect(!duplicateOldDisconnect)
        #expect(lifecycle.isCurrent(id, session: newSession), "a late old disconnect cannot retire the new session")
    }
}
