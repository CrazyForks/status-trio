import Foundation
import Testing
@testable import StatusTrioCore

struct BluetoothLEBatteryScannerStateTests {
    @Test func usesBoundedWindowIntervalQueueConcurrencyAndTimeoutValues() {
        #expect(BluetoothLEBatteryScanPolicy.scanWindow == .seconds(5))
        #expect(BluetoothLEBatteryScanPolicy.automaticScanInterval == 60)
        #expect(BluetoothLEBatteryScanPolicy.successfulConnectionCooldown == 60)
        #expect(BluetoothLEBatteryScanPolicy.failedConnectionCooldown == 30)
        #expect(BluetoothLEBatteryScanPolicy.resultLifetime == 1800)
        #expect(BluetoothLEBatteryScanPolicy.maxQueuedCandidates == 8)
        #expect(BluetoothLEBatteryScanPolicy.maxConcurrentConnections == 2)
        #expect(BluetoothLEBatteryScanPolicy.connectionTimeout == .seconds(4))
    }

    @Test func automaticScansAreThrottledButManualScansCanStartImmediately() {
        let start = Date(timeIntervalSince1970: 1_000)
        var policy = BluetoothLEBatteryScanPolicy()

        let initialScanStarted = policy.beginScan(at: start, manual: false)
        let earlyAutomaticScanStarted = policy.beginScan(at: start.addingTimeInterval(59), manual: false)
        let manualScanStarted = policy.beginScan(at: start.addingTimeInterval(59), manual: true)
        let earlyAfterManualScanStarted = policy.beginScan(at: start.addingTimeInterval(118), manual: false)
        let intervalElapsedScanStarted = policy.beginScan(at: start.addingTimeInterval(119), manual: false)
        #expect(initialScanStarted)
        #expect(!earlyAutomaticScanStarted)
        #expect(manualScanStarted)
        #expect(!earlyAfterManualScanStarted)
        #expect(intervalElapsedScanStarted)
    }

    @Test func deduplicatesCandidatesAndCapsTheQueueAtEight() {
        let start = Date(timeIntervalSince1970: 2_000)
        var policy = BluetoothLEBatteryScanPolicy()
        let scanStarted = policy.beginScan(at: start, manual: true)
        #expect(scanStarted)

        let candidates = (0..<9).map { _ in UUID() }
        for candidate in candidates.prefix(8) {
            let enqueued = policy.enqueueCandidate(candidate, at: start)
            #expect(enqueued)
        }
        let duplicateEnqueued = policy.enqueueCandidate(candidates[0], at: start)
        let ninthEnqueued = policy.enqueueCandidate(candidates[8], at: start)
        #expect(!duplicateEnqueued)
        #expect(!ninthEnqueued)
        #expect(policy.queuedCandidateCount == 8)
    }

    @Test func connectionQueueStartsAndRefillsWhileScanWindowIsActive() {
        let start = Date(timeIntervalSince1970: 3_000)
        var policy = BluetoothLEBatteryScanPolicy()
        let scanStarted = policy.beginScan(at: start, manual: true)
        #expect(scanStarted)
        let candidates = (0..<4).map { _ in UUID() }
        for candidate in candidates {
            let enqueued = policy.enqueueCandidate(candidate, at: start)
            #expect(enqueued)
        }

        let initialConnections = policy.startQueuedConnections()
        #expect(initialConnections == Array(candidates.prefix(2)))
        #expect(policy.inFlightConnectionCount == 2)
        policy.completeConnection(candidates[0], succeeded: true, at: start)
        let nextConnections = policy.startQueuedConnections()
        #expect(nextConnections == [candidates[2]])
        #expect(policy.inFlightConnectionCount == 2)
    }

    @Test func candidatesNotStartedAtWindowEndAreDropped() {
        let start = Date(timeIntervalSince1970: 3_250)
        var policy = BluetoothLEBatteryScanPolicy()
        let scanStarted = policy.beginScan(at: start, manual: true)
        let candidates = (0..<4).map { _ in UUID() }
        for candidate in candidates {
            let enqueued = policy.enqueueCandidate(candidate, at: start)
            #expect(enqueued)
        }

        let initialConnections = policy.startQueuedConnections()
        policy.discardQueuedCandidates()

        #expect(scanStarted)
        #expect(initialConnections == Array(candidates.prefix(2)))
        #expect(policy.inFlightConnectionCount == 2)
        #expect(policy.queuedCandidateCount == 0)
        policy.completeConnection(candidates[0], succeeded: false, at: start)
        #expect(policy.startQueuedConnections().isEmpty)
    }

    @Test func doesNotQueueTheSamePeripheralWhileItsGattQueryIsInFlight() {
        let start = Date(timeIntervalSince1970: 3_500)
        let candidate = UUID()
        var policy = BluetoothLEBatteryScanPolicy()
        let scanStarted = policy.beginScan(at: start, manual: true)
        let candidateEnqueued = policy.enqueueCandidate(candidate, at: start)
        let startedConnections = policy.startQueuedConnections()
        let refreshStarted = policy.beginScan(at: start.addingTimeInterval(1), manual: true)
        let duplicateEnqueued = policy.enqueueCandidate(candidate, at: start.addingTimeInterval(1))

        #expect(scanStarted)
        #expect(candidateEnqueued)
        #expect(startedConnections == [candidate])
        #expect(refreshStarted)
        #expect(!duplicateEnqueued)
        #expect(policy.queuedCandidateCount == 0)
        #expect(policy.inFlightConnectionCount == 1)
    }

    @Test func appliesSuccessAndFailureCooldownsToLaterScanWindows() {
        let start = Date(timeIntervalSince1970: 4_000)
        let successfulID = UUID()
        let failedID = UUID()
        var policy = BluetoothLEBatteryScanPolicy()

        let initialScanStarted = policy.beginScan(at: start, manual: true)
        let successfulCandidateEnqueued = policy.enqueueCandidate(successfulID, at: start)
        let failedCandidateEnqueued = policy.enqueueCandidate(failedID, at: start)
        let connections = policy.startQueuedConnections()
        #expect(initialScanStarted)
        #expect(successfulCandidateEnqueued)
        #expect(failedCandidateEnqueued)
        #expect(connections == [successfulID, failedID])
        policy.completeConnection(successfulID, succeeded: true, at: start)
        policy.completeConnection(failedID, succeeded: false, at: start)

        let afterTwentyNineSeconds = start.addingTimeInterval(29)
        let twentyNineSecondScanStarted = policy.beginScan(at: afterTwentyNineSeconds, manual: true)
        let successfulCandidateAtTwentyNineSeconds = policy.enqueueCandidate(successfulID, at: afterTwentyNineSeconds)
        let failedCandidateAtTwentyNineSeconds = policy.enqueueCandidate(failedID, at: afterTwentyNineSeconds)
        #expect(twentyNineSecondScanStarted)
        #expect(!successfulCandidateAtTwentyNineSeconds)
        #expect(!failedCandidateAtTwentyNineSeconds)

        let afterThirtySeconds = start.addingTimeInterval(30)
        let thirtySecondScanStarted = policy.beginScan(at: afterThirtySeconds, manual: true)
        let successfulCandidateAtThirtySeconds = policy.enqueueCandidate(successfulID, at: afterThirtySeconds)
        let failedCandidateAtThirtySeconds = policy.enqueueCandidate(failedID, at: afterThirtySeconds)
        #expect(thirtySecondScanStarted)
        #expect(!successfulCandidateAtThirtySeconds)
        #expect(failedCandidateAtThirtySeconds)

        let afterSixtySeconds = start.addingTimeInterval(60)
        let sixtySecondScanStarted = policy.beginScan(at: afterSixtySeconds, manual: true)
        let successfulCandidateAtSixtySeconds = policy.enqueueCandidate(successfulID, at: afterSixtySeconds)
        let failedCandidateAtSixtySeconds = policy.enqueueCandidate(failedID, at: afterSixtySeconds)
        #expect(sixtySecondScanStarted)
        #expect(successfulCandidateAtSixtySeconds)
        #expect(failedCandidateAtSixtySeconds)
    }

    @Test func stopInvalidatesOldCallbacksAndDropsPendingWork() {
        let start = Date(timeIntervalSince1970: 5_000)
        let candidate = UUID()
        var policy = BluetoothLEBatteryScanPolicy()
        let scanStarted = policy.beginScan(at: start, manual: true)
        let candidateEnqueued = policy.enqueueCandidate(candidate, at: start)
        #expect(scanStarted)
        #expect(candidateEnqueued)
        let oldGeneration = policy.generation

        policy.stop()

        #expect(!policy.acceptsCallback(from: oldGeneration))
        #expect(policy.queuedCandidateCount == 0)
        #expect(policy.inFlightConnectionCount == 0)
        #expect(policy.startQueuedConnections().isEmpty)
    }

    /// A cooldown belongs to the session that earned it, so the next session
    /// must not inherit it. The panel closing and reopening is exactly that
    /// case: the devices read a moment ago have to be readable again rather
    /// than skipped until their cooldown runs out.
    @Test func connectionCooldownsDoNotSurviveStop() {
        let start = Date(timeIntervalSince1970: 5_500)
        let successfulID = UUID()
        let failedID = UUID()
        var policy = BluetoothLEBatteryScanPolicy()

        _ = policy.beginScan(at: start, manual: true)
        _ = policy.enqueueCandidate(successfulID, at: start)
        _ = policy.enqueueCandidate(failedID, at: start)
        _ = policy.startQueuedConnections()
        policy.completeConnection(successfulID, succeeded: true, at: start)
        policy.completeConnection(failedID, succeeded: false, at: start)

        // Still inside both cooldowns, and still skipped while the session runs.
        let duringSession = start.addingTimeInterval(1)
        _ = policy.beginScan(at: duringSession, manual: true)
        let successfulDuringSession = policy.enqueueCandidate(successfulID, at: duringSession)
        let failedDuringSession = policy.enqueueCandidate(failedID, at: duringSession)
        #expect(!successfulDuringSession)
        #expect(!failedDuringSession)

        policy.stop()

        let nextSession = start.addingTimeInterval(2)
        _ = policy.beginScan(at: nextSession, manual: true)
        let successfulInNextSession = policy.enqueueCandidate(successfulID, at: nextSession)
        let failedInNextSession = policy.enqueueCandidate(failedID, at: nextSession)
        #expect(successfulInNextSession)
        #expect(failedInNextSession)
    }

    /// A level is the whole reading for a device that only advertises `180F`, and
    /// it goes out as soon as it arrives.
    @Test func aLevelWithNoModelReadBehindItPublishesAtOnce() {
        #expect(BluetoothLEBatteryPublishGate.shouldPublish(
            batteryLevel: 31,
            modelReadPending: false,
            sessionIsEnding: false
        ))
    }

    /// A device that also answers the model characteristic is not settled yet:
    /// the string it returns is what decides whether the row is folded onto a
    /// paired device or left in the nearby list, so the row must not be drawn in
    /// one and moved to the other a tenth of a second later — which is what put
    /// the panel's "paired devices" header on screen and took it off again.
    @Test func aLevelHeldBackWhileTheModelReadIsInFlight() {
        #expect(!BluetoothLEBatteryPublishGate.shouldPublish(
            batteryLevel: 31,
            modelReadPending: true,
            sessionIsEnding: false
        ))
    }

    /// The wait is bounded by the session: a device that never answers the model
    /// read still publishes the level it did answer.
    @Test func aSessionEndingStillPublishesTheLevelItHas() {
        #expect(BluetoothLEBatteryPublishGate.shouldPublish(
            batteryLevel: 31,
            modelReadPending: true,
            sessionIsEnding: true
        ))
    }

    /// No level is no reading, whatever else the session answered.
    @Test func nothingPublishesWithoutALevel() {
        for modelReadPending in [true, false] {
            for sessionIsEnding in [true, false] {
                #expect(!BluetoothLEBatteryPublishGate.shouldPublish(
                    batteryLevel: nil,
                    modelReadPending: modelReadPending,
                    sessionIsEnding: sessionIsEnding
                ))
            }
        }
    }
}
