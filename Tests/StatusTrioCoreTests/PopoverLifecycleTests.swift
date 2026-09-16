import Foundation
import Testing
@testable import StatusTrioCore

struct PopoverToggleGateTests {
    @Test func acceptsTheFirstToggleImmediately() {
        var gate = PopoverToggleGate(lockout: 0.25)
        let start = Date()

        let accepted = gate.shouldAccept(at: start)
        #expect(accepted)
    }

    @Test func ignoresRepeatsInsideTheLockout() {
        var gate = PopoverToggleGate(lockout: 0.25)
        let start = Date()
        _ = gate.shouldAccept(at: start)

        let shortlyAfter = gate.shouldAccept(at: start.addingTimeInterval(0.1))
        let justInsideLockout = gate.shouldAccept(at: start.addingTimeInterval(0.24))
        #expect(shortlyAfter == false)
        #expect(justInsideLockout == false)
    }

    @Test func acceptsAgainAfterTheLockout() {
        var gate = PopoverToggleGate(lockout: 0.25)
        let start = Date()
        _ = gate.shouldAccept(at: start)

        let afterLockout = gate.shouldAccept(at: start.addingTimeInterval(0.25))
        #expect(afterLockout)
    }
}

struct PopoverContentRetentionTests {
    @Test func keepsContentWhileThePopoverIsOpen() {
        var retention = PopoverContentRetention(releaseDelay: 60)
        retention.markOpened()

        #expect(retention.shouldRelease(at: Date().addingTimeInterval(3600)) == false)
    }

    @Test func releasesOnlyAfterTheDelay() {
        var retention = PopoverContentRetention(releaseDelay: 60)
        let closed = Date()
        retention.markClosed(at: closed)

        #expect(retention.shouldRelease(at: closed.addingTimeInterval(59)) == false)
        #expect(retention.shouldRelease(at: closed.addingTimeInterval(60)))
    }

    @Test func reopeningCancelsThePendingRelease() {
        var retention = PopoverContentRetention(releaseDelay: 60)
        let closed = Date()
        retention.markClosed(at: closed)
        retention.markOpened()

        #expect(retention.shouldRelease(at: closed.addingTimeInterval(120)) == false)
    }
}
