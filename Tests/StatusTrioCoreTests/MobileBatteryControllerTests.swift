import XCTest
@testable import StatusTrioCore

@MainActor
final class MobileBatteryControllerTests: XCTestCase {
    func testSleeperWaitsThrowWhenTheRequestedStateNeverArrives() async {
        let sleeper = ControlledMobileBatterySleeper()
        for operation in 0..<3 {
            do {
                switch operation {
                case 0:
                    try await sleeper.waitForDuration(.seconds(600), timeout: .zero)
                case 1:
                    try await sleeper.waitForRequestCount(1, duration: .seconds(600), timeout: .zero)
                default:
                    try await sleeper.waitForActiveRequestCount(1, duration: .seconds(600), timeout: .zero)
                }
                XCTFail("Sleeper wait \(operation) returned without observing its requested state.")
            } catch is ControlledMobileBatterySleeper.WaitTimeout {
                // A missing scheduler event must fail rather than silently continue.
            } catch {
                XCTFail("Unexpected sleeper wait error: \(error)")
            }
        }
    }

    func testClaimsAndSurfaceMustBothBeActiveToRead() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)

        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.setSurfaceVisible(true)
        await settle()
        let countWithoutClaims = await reader.readCount
        XCTAssertEqual(countWithoutClaims, 0)

        controller.setSurfaceVisible(false)
        controller.request("summary")
        await settle()
        let countWithClaimsButClosed = await reader.readCount
        XCTAssertEqual(countWithClaimsButClosed, 0)

        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        controller.stop()
        await reader.finishAll()
    }

    func testReleasingTemporaryViewportRetainsFreshCachedSnapshot() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.setSurfaceVisible(true)
        controller.request("popover")
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 74))
        await waitUntil { controller.snapshots.count == 1 }

        controller.setAuthorizedDeviceIDs([])

        XCTAssertEqual(controller.snapshots.map(\.batteryLevel), [74])
        controller.setSurfaceVisible(false)
        XCTAssertEqual(controller.snapshots.map(\.batteryLevel), [74])
        controller.stop()
        await reader.finishAll()
    }

    func testBackgroundRefreshCanReadWithClosedSurfaceAndStopsWhenDisabled() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.setBackgroundRefresh(enabled: true, interval: .seconds(60))
        controller.setSurfaceVisible(false)

        await waitUntil { await reader.readCount == 1 }
        controller.setBackgroundRefresh(enabled: false, interval: .seconds(60))
        await waitUntil { await reader.cancellationCount == 1 }
        controller.stop()
        await reader.finishAll()
    }

    func testBackgroundRefreshUsesConfiguredIntervalWithoutOverlappingRead() async throws {
        let reader = ControlledMobileBatteryReader()
        let sleeper = ControlledMobileBatterySleeper()
        let controller = MobileBatteryController(
            reader: reader,
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.setBackgroundRefresh(enabled: true, interval: .seconds(120))
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 42))
        await waitUntil { !controller.isRefreshing }
        try await sleeper.waitForDuration(.seconds(120))

        let countBeforeTick = await reader.readCount
        XCTAssertEqual(countBeforeTick, 1)
        await sleeper.fire(duration: .seconds(120))
        await waitUntil { await reader.readCount == 2 }
        controller.setBackgroundRefresh(enabled: false, interval: .seconds(120))
        await waitUntil { await reader.cancellationCount == 1 }
        let readCountAfterDisable = await reader.readCount
        await sleeper.fire(duration: .seconds(120))
        await settle()
        let readCountAfterCancelledCadence = await reader.readCount
        XCTAssertEqual(readCountAfterCancelledCadence, readCountAfterDisable)
        controller.stop()
        await reader.finishAll()
    }

    func testSuccessfulWatchKeepsConfiguredBackgroundInterval() async throws {
        let reader = ControlledMobileBatteryReader()
        let sleeper = ControlledMobileBatterySleeper()
        let controller = MobileBatteryController(
            reader: reader,
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        let selected: Set<AppleDeviceID> = [.trustedDevice("phone-a"), .trustedWatch(parentID: "phone-a", id: "watch-a")]
        controller.setAuthorizedDeviceIDs(selected)
        controller.setBackgroundAuthorizedDeviceIDs(selected)
        controller.setBackgroundRefresh(enabled: true, interval: .seconds(600))
        await waitUntil { await reader.readCount == 1 }

        await reader.complete(0, with: MobileBatteryReadResult(snapshots: [
            snapshot(level: 42, at: Date()), watchSnapshot(id: "watch-a", parentID: "phone-a", level: 68)
        ]))
        await waitUntil { controller.snapshots.count == 2 }
        try await sleeper.waitForDuration(.seconds(600))

        let earlyRetryRequests = await sleeper.requestCount(for: .seconds(60))
        let normalRefreshRequests = await sleeper.requestCount(for: .seconds(600))
        XCTAssertEqual(earlyRetryRequests, 0)
        XCTAssertEqual(normalRefreshRequests, 1)
        controller.stop()
        await reader.finishAll()
    }

    func testMissingWatchWithValidCachedSnapshotKeepsConfiguredInterval() async throws {
        let reader = ControlledMobileBatteryReader()
        let sleeper = ControlledMobileBatterySleeper()
        let controller = MobileBatteryController(
            reader: reader,
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        let watch = AppleDeviceID.trustedWatch(parentID: "phone-a", id: "watch-a")
        controller.setAuthorizedDeviceIDs([watch])
        controller.setBackgroundRefresh(enabled: true, interval: .seconds(600))
        await waitUntil { await reader.readCount == 1 }

        await reader.complete(0, with: MobileBatteryReadResult(snapshots: [
            watchSnapshot(id: "watch-a", parentID: "phone-a", level: 68)
        ]))
        await waitUntil { controller.snapshots.count == 1 }
        try await sleeper.waitForDuration(.seconds(600))
        await sleeper.fire(duration: .seconds(600))
        await waitUntil { await reader.readCount == 2 }
        await reader.complete(1, with: MobileBatteryReadResult(
            failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: "watch-a")]
        ))
        await waitUntil { !controller.isRefreshing }
        try await sleeper.waitForRequestCount(1, duration: .seconds(600))

        let earlyRetryRequests = await sleeper.requestCount(for: .seconds(60))
        XCTAssertEqual(earlyRetryRequests, 0)
        let configuredRefreshRequests = await sleeper.requestCount(for: .seconds(600))
        XCTAssertEqual(configuredRefreshRequests, 2)
        controller.stop()
        await reader.finishAll()
    }

    func testMissingWatchSchedulesOneMinuteRetryInsteadOfConfiguredBackgroundInterval() async throws {
        let reader = ControlledMobileBatteryReader()
        let sleeper = ControlledMobileBatterySleeper()
        let controller = MobileBatteryController(
            reader: reader,
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        controller.setAuthorizedDeviceIDs([.trustedWatch(parentID: "phone-a", id: "watch-a")])
        controller.setBackgroundRefresh(enabled: true, interval: .seconds(600))
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: MobileBatteryReadResult(
            failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: "watch-a")]
        ))
        await waitUntil { !controller.isRefreshing }

        try await sleeper.waitForDuration(.seconds(60))
        let retryRequests = await sleeper.requestCount(for: .seconds(60))
        let configuredRequests = await sleeper.requestCount(for: .seconds(600))
        XCTAssertEqual(retryRequests, 1)
        XCTAssertEqual(configuredRequests, 0)

        controller.stop()
        await reader.finishAll()
    }

    func testWatchOnlyRetriesDoNotPostponeConfiguredFullRefreshDeadline() async throws {
        let reader = ControlledMobileBatteryReader()
        let sleeper = ControlledMobileBatterySleeper()
        let now = MutableDate(Date(timeIntervalSince1970: 60_000))
        let controller = MobileBatteryController(
            reader: reader,
            clock: { now.value },
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        let phone = AppleDeviceID.trustedDevice("phone-a")
        let watch = AppleDeviceID.trustedWatch(parentID: "phone-a", id: "watch-a")
        let selected: Set<AppleDeviceID> = [phone, watch]
        controller.setAuthorizedDeviceIDs(selected)
        controller.setBackgroundAuthorizedDeviceIDs(selected)
        controller.setBackgroundRefresh(enabled: true, interval: .seconds(600))
        await waitUntil { await reader.readCount == 1 }

        await reader.complete(0, with: MobileBatteryReadResult(
            snapshots: [snapshot(level: 42, at: now.value)],
            failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: "watch-a")]
        ))
        await waitUntil { !controller.isRefreshing }

        for retry in 0..<3 {
            try await sleeper.waitForDuration(.seconds(60))
            now.value.addTimeInterval(60)
            await sleeper.fire(duration: .seconds(60))
            await waitUntil { await reader.readCount == retry + 2 }
            await reader.complete(retry + 1, with: MobileBatteryReadResult(
                failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: "watch-a")]
            ))
            await waitUntil { !controller.isRefreshing }
        }

        now.value.addTimeInterval(420)
        try await sleeper.waitForDuration(.seconds(420))
        let retainedFullRefreshIsScheduled = await sleeper.hasActiveRequest(for: .seconds(420))
        XCTAssertTrue(retainedFullRefreshIsScheduled, "the third Watch retry must leave the original t=600 full-refresh deadline intact")
        guard retainedFullRefreshIsScheduled else {
            controller.stop()
            await reader.finishAll()
            return
        }
        await sleeper.fire(duration: .seconds(420))
        await waitUntil { await reader.readCount == 5 }
        let reads = await reader.selectedIDHistory
        XCTAssertEqual(reads[4], selected, "the full configured refresh remains due at t=600 after retries at t=60, t=120, and t=180")

        controller.stop()
        await reader.finishAll()
    }

    func testChangingBackgroundIntervalDuringWatchRetryReanchorsFullRefreshDeadline() async throws {
        let reader = ControlledMobileBatteryReader()
        let sleeper = ControlledMobileBatterySleeper()
        let now = MutableDate(Date(timeIntervalSince1970: 70_000))
        let controller = MobileBatteryController(
            reader: reader,
            clock: { now.value },
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        let phone = AppleDeviceID.trustedDevice("phone-a")
        let watch = AppleDeviceID.trustedWatch(parentID: "phone-a", id: "watch-a")
        let selected: Set<AppleDeviceID> = [phone, watch]
        controller.setAuthorizedDeviceIDs(selected)
        controller.setBackgroundAuthorizedDeviceIDs(selected)
        controller.setBackgroundRefresh(enabled: true, interval: .seconds(600))
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: MobileBatteryReadResult(
            snapshots: [snapshot(level: 42, at: now.value)],
            failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: "watch-a")]
        ))
        await waitUntil { !controller.isRefreshing }

        try await sleeper.waitForDuration(.seconds(60))
        now.value.addTimeInterval(60)
        await sleeper.fire(duration: .seconds(60))
        await waitUntil { await reader.readCount == 2 }
        controller.setBackgroundRefresh(enabled: true, interval: .seconds(120))
        await reader.complete(1, with: MobileBatteryReadResult(
            failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: "watch-a")]
        ))
        await waitUntil { !controller.isRefreshing }

        try await sleeper.waitForDuration(.seconds(60))
        now.value.addTimeInterval(60)
        await sleeper.fire(duration: .seconds(60))
        await waitUntil { await reader.readCount == 3 }
        await reader.complete(2, with: MobileBatteryReadResult(
            failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: "watch-a")]
        ))
        await waitUntil { !controller.isRefreshing }

        try await sleeper.waitForDuration(.seconds(60))
        now.value.addTimeInterval(60)
        await sleeper.fire(duration: .seconds(60))
        await waitUntil { await reader.readCount == 4 }
        let reads = await reader.selectedIDHistory
        XCTAssertEqual(reads[3], selected, "interval change at t=60 reanchors the full refresh to t=180")

        controller.stop()
        await reader.finishAll()
    }

    func testDisablingBackgroundDuringWatchRetryUsesVisibleForegroundDeadline() async throws {
        let reader = ControlledMobileBatteryReader()
        let sleeper = ControlledMobileBatterySleeper()
        let now = MutableDate(Date(timeIntervalSince1970: 80_000))
        let controller = MobileBatteryController(
            reader: reader,
            clock: { now.value },
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        let phone = AppleDeviceID.trustedDevice("phone-a")
        let watch = AppleDeviceID.trustedWatch(parentID: "phone-a", id: "watch-a")
        let selected: Set<AppleDeviceID> = [phone, watch]
        controller.setAuthorizedDeviceIDs(selected)
        controller.setBackgroundAuthorizedDeviceIDs(selected)
        controller.setBackgroundRefresh(enabled: true, interval: .seconds(600))
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: MobileBatteryReadResult(
            snapshots: [snapshot(level: 42, at: now.value)],
            failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: "watch-a")]
        ))
        await waitUntil { !controller.isRefreshing }

        try await sleeper.waitForDuration(.seconds(60))
        now.value.addTimeInterval(60)
        await sleeper.fire(duration: .seconds(60))
        await waitUntil { await reader.readCount == 2 }
        controller.request("visible-panel")
        controller.setSurfaceVisible(true)
        controller.setBackgroundRefresh(enabled: false, interval: .seconds(600))
        await reader.complete(1, with: MobileBatteryReadResult(
            failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: "watch-a")]
        ))
        await waitUntil { !controller.isRefreshing }

        try await sleeper.waitForDuration(.seconds(60))
        now.value.addTimeInterval(60)
        await sleeper.fire(duration: .seconds(60))
        await waitUntil { await reader.readCount == 3 }
        let reads = await reader.selectedIDHistory
        XCTAssertEqual(reads[2], selected, "disabling background during a Watch retry must reanchor to the visible 60-second cadence")

        controller.stop()
        await reader.finishAll()
    }

    func testWatchOnlyRetryIgnoresSnapshotsAndFailuresOutsideRequestedIDs() async throws {
        let reader = ControlledMobileBatteryReader()
        let sleeper = ControlledMobileBatterySleeper()
        let controller = MobileBatteryController(
            reader: reader,
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        let phone = AppleDeviceID.trustedDevice("phone-a")
        let watchA = AppleDeviceID.trustedWatch(parentID: "phone-a", id: "watch-a")
        let watchB = AppleDeviceID.trustedWatch(parentID: "phone-a", id: "watch-b")
        let selected: Set<AppleDeviceID> = [phone, watchA, watchB]
        controller.setAuthorizedDeviceIDs(selected)
        controller.setBackgroundAuthorizedDeviceIDs(selected)
        controller.setBackgroundRefresh(enabled: true, interval: .seconds(600))
        await waitUntil { await reader.readCount == 1 }

        await reader.complete(0, with: MobileBatteryReadResult(snapshots: [
            snapshot(level: 42, at: Date()), watchSnapshot(id: "watch-a", parentID: "phone-a", level: 68)
        ]))
        await waitUntil { controller.snapshots.count == 2 }
        try await sleeper.waitForDuration(.seconds(60))
        await sleeper.fire(duration: .seconds(60))
        await waitUntil { await reader.readCount == 2 }

        let readHistory = await reader.selectedIDHistory
        XCTAssertEqual(readHistory[1], [watchB])
        await reader.complete(1, with: MobileBatteryReadResult(
            snapshots: [snapshot(level: 99, at: Date()), watchSnapshot(id: "watch-a", parentID: "phone-a", level: 99)],
            failures: [
                MobileBatteryReadFailure(category: "unsolicited-device", deviceID: "phone-a"),
                MobileBatteryReadFailure(category: "read-failed", deviceID: "watch-a")
            ]
        ))
        await waitUntil { !controller.isRefreshing }

        XCTAssertEqual(controller.snapshots.first(where: { $0.identity == "phone:phone-a" })?.batteryLevel, 42)
        XCTAssertEqual(controller.snapshots.first(where: { $0.identity == "watch:phone-a:watch-a" })?.batteryLevel, 68)
        XCTAssertTrue(controller.failures.isEmpty)
        try await sleeper.waitForRequestCount(2, duration: .seconds(60))
        let nextRetryRequests = await sleeper.requestCount(for: .seconds(60))
        XCTAssertEqual(nextRetryRequests, 2, "an unrelated Watch result must not clear or restart Watch B's retry budget")

        controller.stop()
        await reader.finishAll()
    }

    func testMissingWatchRetryBudgetSurvivesRepublishedDemandAndBackgroundToggle() async throws {
        try await assertMissingWatchRetryBudget(
            clockAdvance: 0, expectedRefresh: .seconds(600), requestsAfterReenable: 2
        )
    }

    func testMissingWatchRetryBudgetPreservesElapsedFullRefreshDeadline() async throws {
        try await assertMissingWatchRetryBudget(
            clockAdvance: 1, expectedRefresh: .seconds(599), requestsAfterReenable: 1
        )
    }

    private func assertMissingWatchRetryBudget(
        clockAdvance: TimeInterval, expectedRefresh: Duration, requestsAfterReenable: Int
    ) async throws {
        let reader = ControlledMobileBatteryReader()
        let sleeper = ControlledMobileBatterySleeper()
        let clock = MutableDate(Date())
        let controller = MobileBatteryController(
            reader: reader,
            clock: { clock.value },
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        let phone = AppleDeviceID.trustedDevice("phone-a")
        let successfulWatch = AppleDeviceID.trustedWatch(parentID: "phone-a", id: "watch-a")
        let missingWatch = AppleDeviceID.trustedWatch(parentID: "phone-a", id: "watch-b")
        let selected: Set<AppleDeviceID> = [phone, successfulWatch, missingWatch]
        controller.setAuthorizedDeviceIDs(selected)
        controller.setBackgroundAuthorizedDeviceIDs(selected)
        controller.setBackgroundRefresh(enabled: true, interval: .seconds(600))
        await waitUntil { await reader.readCount == 1 }

        await reader.complete(0, with: partialWatchResult())
        await waitUntil { !controller.isRefreshing }
        try await sleeper.waitForRequestCount(1, duration: .seconds(60))
        controller.setBackgroundRefresh(enabled: false, interval: .seconds(600))
        try await sleeper.waitForActiveRequestCount(0, duration: .seconds(60))
        controller.setBackgroundRefresh(enabled: true, interval: .seconds(600))
        await waitUntil { await reader.readCount == 2 }

        await reader.complete(1, with: partialWatchResult())
        await waitUntil { !controller.isRefreshing }
        try await sleeper.waitForRequestCount(2, duration: .seconds(60))
        controller.setAuthorizedDeviceIDs(selected)
        controller.setBackgroundAuthorizedDeviceIDs(selected)
        await sleeper.fire(duration: .seconds(60))
        await waitUntil { await reader.readCount == 3 }

        clock.value = clock.value.addingTimeInterval(clockAdvance)

        for retry in 0..<3 {
            await reader.complete(retry + 2, with: missingWatchFailureResult())
            await waitUntil { !controller.isRefreshing }
            if retry < 2 {
                try await sleeper.waitForRequestCount(retry + 3, duration: .seconds(60))
                await sleeper.fire(duration: .seconds(60))
                await waitUntil { await reader.readCount == retry + 4 }
            }
        }

        try await sleeper.waitForRequestCount(1, duration: expectedRefresh)
        let cappedRetryRequests = await sleeper.requestCount(for: .seconds(60))
        let configuredRefreshRequests = await sleeper.requestCount(for: expectedRefresh)
        XCTAssertEqual(cappedRetryRequests, 4)
        XCTAssertEqual(configuredRefreshRequests, 1)

        controller.setBackgroundRefresh(enabled: false, interval: .seconds(600))
        controller.setBackgroundRefresh(enabled: true, interval: .seconds(600))
        await waitUntil { await reader.readCount == 6 }
        await reader.complete(5, with: partialWatchResult())
        await waitUntil { !controller.isRefreshing }
        try await sleeper.waitForRequestCount(requestsAfterReenable, duration: .seconds(600))
        let retriesAfterReenable = await sleeper.requestCount(for: .seconds(60))
        XCTAssertEqual(retriesAfterReenable, 4)

        controller.revokeDeviceIDs([missingWatch])
        controller.setAuthorizedDeviceIDs(selected)
        await waitUntil { await reader.readCount == 7 }
        await reader.complete(6, with: partialWatchResult())
        await waitUntil { !controller.isRefreshing }
        try await sleeper.waitForRequestCount(5, duration: .seconds(60))
        let retriesAfterNewAuthorization = await sleeper.requestCount(for: .seconds(60))
        XCTAssertEqual(retriesAfterNewAuthorization, 5)

        controller.stop()
        await reader.finishAll()
    }

    func testRapidDisableAndReenableClearsCacheAndStartsANewReadForTheExistingClaim() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.setSurfaceVisible(true)
        controller.request("summary")
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 71))
        await waitUntil { controller.snapshots.count == 1 }

        controller.setReadingEnabled(false)
        XCTAssertTrue(controller.snapshots.isEmpty)
        controller.setReadingEnabled(true)
        await waitUntil { await reader.readCount == 2 }
        XCTAssertTrue(controller.snapshots.isEmpty)
        controller.stop()
        await reader.finishAll()
    }

    func testDisablingBatteryReadsClearsLevelsButRetainsAuthorizedRows() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        let selected: Set<AppleDeviceID> = [.trustedDevice("phone-a")]
        controller.setAuthorizedDeviceIDs(selected)
        controller.setSurfaceVisible(true)
        controller.request("panel")
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 71))
        await waitUntil { controller.snapshots.count == 1 }

        controller.setReadingEnabled(false)
        XCTAssertTrue(controller.snapshots.isEmpty)
        controller.setAuthorizedDeviceIDs(selected)
        XCTAssertTrue(controller.snapshots.isEmpty)
        let readsWhileDisabled = await reader.readCount
        XCTAssertEqual(readsWhileDisabled, 1)

        controller.setReadingEnabled(true)
        await waitUntil { await reader.readCount == 2 }
        controller.stop()
        await reader.finishAll()
    }

    func testMasterOffRevokesPendingTrustedReadsAndClearsCachedAppleRows() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.setSurfaceVisible(true)
        controller.request("panel")
        await waitUntil { await reader.readCount == 1 }

        controller.setReadingEnabled(false)

        XCTAssertTrue(controller.snapshots.isEmpty)
        XCTAssertFalse(controller.isRefreshing)
        await waitUntil { await reader.cancellationCount == 1 }
        await reader.complete(0, with: result(level: 99))
        await settle()
        XCTAssertTrue(controller.snapshots.isEmpty)
        controller.stop()
        await reader.finishAll()
    }

    func testReenablingWithNoClaimAndClosedSurfaceDoesNotRead() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.setReadingEnabled(false)
        controller.setReadingEnabled(true)
        controller.setSurfaceVisible(false)
        await settle()

        let readCount = await reader.readCount
        XCTAssertEqual(readCount, 0)
        controller.stop()
        await reader.finishAll()
    }

    func testClaimsShareWorkAndLastReleaseClearsSnapshots() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.setSurfaceVisible(true)
        controller.request("summary")
        await waitUntil { await reader.readCount == 1 }

        controller.request("bluetooth")
        controller.release("summary")
        await settle()
        let cancellationsAfterFirstRelease = await reader.cancellationCount
        XCTAssertEqual(cancellationsAfterFirstRelease, 0)

        await reader.complete(0, with: result(level: 71))
        await waitUntil { controller.snapshots.map(\.batteryLevel) == [71] }
        controller.release("bluetooth")
        XCTAssertTrue(controller.snapshots.isEmpty)
        let cancellationsAfterLastRelease = await reader.cancellationCount
        XCTAssertEqual(cancellationsAfterLastRelease, 0)
        XCTAssertFalse(controller.isRefreshing)
        XCTAssertTrue(controller.failures.isEmpty)
        controller.stop()
        await reader.finishAll()
    }

    func testClosingPopoverCancelsReadAndReopenRejectsLateGeneration() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }

        controller.setSurfaceVisible(false)
        await waitUntil { await reader.cancellationCount == 1 }
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 2 }

        await reader.complete(1, with: result(level: 38))
        await waitUntil { controller.snapshots.map(\.batteryLevel) == [38] }
        await reader.complete(0, with: result(level: 92))
        await settle()
        XCTAssertEqual(controller.snapshots.map(\.batteryLevel), [38])
        controller.stop()
        await reader.finishAll()
    }

    func testViewportPermitLossRetainsCacheAndRejectsLateSnapshot() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        let first: Set<AppleDeviceID> = [.trustedDevice("phone-a"), .trustedDevice("phone-b")]
        controller.setAuthorizedDeviceIDs(first)
        controller.request("panel")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: MobileBatteryReadResult(snapshots: [
            snapshot(id: "phone-a", level: 71, at: Date()), snapshot(id: "phone-b", level: 62, at: Date())
        ]))
        await waitUntil { controller.snapshots.count == 2 }

        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-b")])
        XCTAssertEqual(Set(controller.snapshots.map(\.id)), ["phone-a", "phone-b"])
        await waitUntil { await reader.readCount == 2 }
        await reader.complete(1, with: MobileBatteryReadResult(snapshots: [
            snapshot(id: "phone-a", level: 99, at: Date()), snapshot(id: "phone-b", level: 55, at: Date())
        ]))
        await waitUntil { controller.snapshots.first(where: { $0.id == "phone-b" })?.batteryLevel == 55 }
        XCTAssertEqual(Set(controller.snapshots.map(\.id)), ["phone-a", "phone-b"])
        XCTAssertEqual(controller.snapshots.first(where: { $0.id == "phone-a" })?.batteryLevel, 71)
        controller.stop()
        await reader.finishAll()
    }

    func testExplicitHidePurgesOnlyHiddenCachedSnapshot() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a"), .trustedDevice("phone-b")])
        controller.setSurfaceVisible(true)
        controller.request("panel")
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: MobileBatteryReadResult(snapshots: [
            snapshot(id: "phone-a", level: 71, at: Date()), snapshot(id: "phone-b", level: 62, at: Date())
        ]))
        await waitUntil { controller.snapshots.count == 2 }

        controller.revokeDeviceIDs([.trustedDevice("phone-a")])

        XCTAssertEqual(controller.snapshots.map(\.id), ["phone-b"])
        controller.stop()
        await reader.finishAll()
    }

    func testManualRefreshSupersedesReadAndStartsImmediately() async {
        let reader = ControlledMobileBatteryReader()
        let controller = MobileBatteryController(reader: reader)
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }

        controller.refresh()
        await waitUntil { await reader.readCount == 2 }
        let cancellations = await reader.cancellationCount
        XCTAssertEqual(cancellations, 1)
        await reader.complete(1, with: result(level: 52))
        await waitUntil { controller.snapshots.map(\.batteryLevel) == [52] }
        await reader.complete(0, with: result(level: 12))
        await settle()
        XCTAssertEqual(controller.snapshots.map(\.batteryLevel), [52])
        controller.stop()
        await reader.finishAll()
    }

    func testFailureRetainsTimestampAndPartialSuccessMergesByIdentity() async {
        let reader = ControlledMobileBatteryReader()
        let now = MutableDate(Date(timeIntervalSince1970: 10_000))
        let controller = MobileBatteryController(reader: reader, clock: { now.value })
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a"), .trustedDevice("phone-b")])
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 80, id: "phone-a"))
        await waitUntil { controller.snapshots.count == 1 }
        let initialTimestamp = controller.snapshots[0].observedAt

        now.value.addTimeInterval(60)
        controller.refresh()
        await waitUntil { await reader.readCount == 2 }
        await reader.complete(1, with: MobileBatteryReadResult(
            snapshots: [snapshot(id: "phone-b", level: 44, at: now.value)],
            failures: [MobileBatteryReadFailure(category: "unavailable", deviceID: "phone-a")]
        ))
        await waitUntil { controller.snapshots.count == 2 }
        XCTAssertEqual(controller.failures.map(\.category), ["unavailable"])
        XCTAssertEqual(controller.snapshots.first(where: { $0.id == "phone-a" })?.observedAt, initialTimestamp)
        XCTAssertEqual(controller.snapshots.first(where: { $0.id == "phone-a" })?.batteryLevel, 80)
        XCTAssertEqual(controller.snapshots.first(where: { $0.id == "phone-b" })?.batteryLevel, 44)
        controller.stop()
        await reader.finishAll()
    }

    func testExpiredCacheIsPrunedWhilePopoverIsClosed() async throws {
        let reader = ControlledMobileBatteryReader()
        let now = MutableDate(Date(timeIntervalSince1970: 20_000))
        let sleeper = ControlledMobileBatterySleeper()
        let controller = MobileBatteryController(
            reader: reader,
            clock: { now.value },
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 63, at: now.value))
        await waitUntil { controller.snapshots.count == 1 }
        try await sleeper.waitForDuration(.seconds(1_200))

        controller.setSurfaceVisible(false)
        now.value.addTimeInterval(1_200)
        await sleeper.fire(duration: .seconds(1_200))
        await waitUntil { controller.snapshots.isEmpty }
        controller.stop()
        await reader.finishAll()
    }

    func testVerifiedSnapshotExpiresAtTwentyMinutes() async throws {
        let reader = ControlledMobileBatteryReader()
        let now = MutableDate(Date(timeIntervalSince1970: 22_000))
        let sleeper = ControlledMobileBatterySleeper()
        let controller = MobileBatteryController(
            reader: reader,
            clock: { now.value },
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 64, at: now.value))
        await waitUntil { controller.snapshots.count == 1 }
        try await sleeper.waitForDuration(.seconds(1_200))

        now.value.addTimeInterval(1_200)
        await sleeper.fire(duration: .seconds(1_200))
        await waitUntil { controller.snapshots.isEmpty }
        controller.stop()
        await reader.finishAll()
    }

    func testRefreshesEverySixtySecondsWithoutOverlappingCycles() async throws {
        let reader = ControlledMobileBatteryReader()
        let sleeper = ControlledMobileBatterySleeper()
        let controller = MobileBatteryController(
            reader: reader,
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 42))
        await waitUntil { !controller.isRefreshing }
        try await sleeper.waitForDuration(.seconds(60))

        let countBeforeRefresh = await reader.readCount
        XCTAssertEqual(countBeforeRefresh, 1)
        await sleeper.fire(duration: .seconds(60))
        await waitUntil { await reader.readCount == 2 }
        controller.stop()
        await reader.finishAll()
    }

    func testDeallocationCancelsAReaderThatNeverReturns() async {
        let reader = ControlledMobileBatteryReader()
        weak var weakController: MobileBatteryController?
        do {
            let controller = MobileBatteryController(reader: reader)
            controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
            weakController = controller
            controller.request("summary")
            controller.setSurfaceVisible(true)
            await waitUntil { await reader.readCount == 1 }
        }
        await waitUntil { weakController == nil }
        await waitUntil { await reader.cancellationCount == 1 }
        await reader.finishAll()
    }

    func testSameIdentitySnapshotIsReplacedByLatestReading() async {
        let reader = ControlledMobileBatteryReader()
        let now = MutableDate(Date(timeIntervalSince1970: 30_000))
        let controller = MobileBatteryController(reader: reader, clock: { now.value })
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 71, at: now.value))
        await waitUntil { controller.snapshots.count == 1 }

        now.value.addTimeInterval(60)
        controller.refresh()
        await waitUntil { await reader.readCount == 2 }
        await reader.complete(1, with: result(level: 82, at: now.value))
        await waitUntil { controller.snapshots.first?.batteryLevel == 82 }

        XCTAssertEqual(controller.snapshots.count, 1)
        XCTAssertEqual(controller.snapshots.first?.observedAt, now.value)
        controller.stop()
        await reader.finishAll()
    }

    func testEmptySuccessPreservesCachedReadingAndTimestamp() async {
        let reader = ControlledMobileBatteryReader()
        let now = MutableDate(Date(timeIntervalSince1970: 40_000))
        let controller = MobileBatteryController(reader: reader, clock: { now.value })
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 73, at: now.value))
        await waitUntil { controller.snapshots.count == 1 }
        let originalTimestamp = controller.snapshots[0].observedAt

        now.value.addTimeInterval(300)
        controller.refresh()
        await waitUntil { await reader.readCount == 2 }
        await reader.complete(1, with: MobileBatteryReadResult())
        await waitUntil { !controller.isRefreshing }

        XCTAssertEqual(controller.snapshots.map(\.batteryLevel), [73])
        XCTAssertEqual(controller.snapshots.first?.observedAt, originalTimestamp)
        controller.stop()
        await reader.finishAll()
    }

    func testCacheExpiresAfterFinalClaimReleasesWhileKeepingResults() async throws {
        let reader = ControlledMobileBatteryReader()
        let now = MutableDate(Date(timeIntervalSince1970: 50_000))
        let sleeper = ControlledMobileBatterySleeper()
        let controller = MobileBatteryController(
            reader: reader,
            clock: { now.value },
            sleep: { duration in try await sleeper.sleep(duration) }
        )
        controller.setAuthorizedDeviceIDs([.trustedDevice("phone-a")])
        controller.request("summary")
        controller.setSurfaceVisible(true)
        await waitUntil { await reader.readCount == 1 }
        await reader.complete(0, with: result(level: 64, at: now.value))
        await waitUntil { controller.snapshots.count == 1 }
        try await sleeper.waitForDuration(.seconds(1_200))

        controller.release("summary", keepingResults: true)
        XCTAssertEqual(controller.snapshots.map(\.batteryLevel), [64])
        now.value.addTimeInterval(1_200)
        await sleeper.fire(duration: .seconds(1_200))
        await waitUntil { controller.snapshots.isEmpty }

        controller.stop()
        await reader.finishAll()
    }

    private func snapshot(id: String = "phone-a", level: Int, at date: Date) -> MobileBatterySnapshot {
        MobileBatterySnapshot(
            id: id,
            parentID: nil,
            name: "Phone",
            model: "iPhone",
            batteryLevel: level,
            isCharging: nil,
            transport: .usb,
            observedAt: date
        )
    }

    private func result(level: Int, id: String = "phone-a", at date: Date = Date()) -> MobileBatteryReadResult {
        MobileBatteryReadResult(snapshots: [snapshot(id: id, level: level, at: date)])
    }

    private func watchSnapshot(id: String, parentID: String, level: Int, at date: Date = Date()) -> MobileBatterySnapshot {
        MobileBatterySnapshot(
            id: id,
            parentID: parentID,
            name: "Watch",
            model: "Watch7,4",
            batteryLevel: level,
            isCharging: nil,
            transport: .usb,
            observedAt: date
        )
    }

    private func partialWatchResult() -> MobileBatteryReadResult {
        MobileBatteryReadResult(snapshots: [
            snapshot(level: 42, at: Date()), watchSnapshot(id: "watch-a", parentID: "phone-a", level: 68)
        ], failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: "watch-b")])
    }

    private func missingWatchFailureResult() -> MobileBatteryReadResult {
        MobileBatteryReadResult(failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: "watch-b")])
    }

    private func settle() async {
        for _ in 0..<8 { await Task.yield() }
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping () async -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !(await condition()), ContinuousClock.now < deadline {
            await Task.yield()
        }
        let didBecomeTrue = await condition()
        XCTAssertTrue(didBecomeTrue, "condition did not become true before timeout")
    }
}

private final class MutableDate: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Date

    init(_ value: Date) { storage = value }

    var value: Date {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}

actor ControlledMobileBatteryReader: MobileBatteryReading {
    private var continuations: [Int: CheckedContinuation<MobileBatteryReadResult, any Error>] = [:]
    private var discoveryContinuations: [Int: CheckedContinuation<[AppleDeviceCandidate], any Error>] = [:]
    private(set) var readCount = 0
    private(set) var discoveryCount = 0
    private(set) var cancellationCount = 0
    private(set) var selectedIDHistory: [Set<AppleDeviceID>] = []

    func discover() async throws -> [AppleDeviceCandidate] {
        let index = discoveryCount
        discoveryCount += 1
        return try await withCheckedThrowingContinuation { discoveryContinuations[index] = $0 }
    }

    func read(selectedIDs: Set<AppleDeviceID>) async throws -> MobileBatteryReadResult {
        guard !selectedIDs.isEmpty else { return MobileBatteryReadResult() }
        selectedIDHistory.append(selectedIDs)
        let index = readCount
        readCount += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuations[index] = $0 }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
    }

    func complete(_ index: Int, with result: MobileBatteryReadResult) {
        continuations.removeValue(forKey: index)?.resume(returning: result)
    }

    func completeDiscovery(_ index: Int, with candidates: [AppleDeviceCandidate]) {
        discoveryContinuations.removeValue(forKey: index)?.resume(returning: candidates)
    }

    func finishAll() {
        let pending = continuations.values
        continuations.removeAll()
        for continuation in pending { continuation.resume(throwing: CancellationError()) }
        let pendingDiscovery = discoveryContinuations.values
        discoveryContinuations.removeAll()
        for continuation in pendingDiscovery { continuation.resume(throwing: CancellationError()) }
    }

    private func recordCancellation() { cancellationCount += 1 }
}

private actor ControlledMobileBatterySleeper {
    struct WaitTimeout: Error {}
    private struct Waiter {
        let duration: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var nextID = 0
    private var continuations: [Int: Waiter] = [:]
    private var requestedDurations: [Duration] = []

    func sleep(_ duration: Duration) async throws {
        let id = nextID
        nextID += 1
        requestedDurations.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                continuations[id] = Waiter(duration: duration, continuation: $0)
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func waitForDuration(_ duration: Duration, timeout: Duration = .seconds(5)) async throws {
        try await waitUntil(timeout: timeout) {
            self.continuations.values.contains { Self.approximatelyMatches($0.duration, duration) }
        }
    }

    func waitForRequestCount(_ count: Int, duration: Duration, timeout: Duration = .seconds(5)) async throws {
        try await waitUntil(timeout: timeout) {
            self.requestedDurations.filter { Self.approximatelyMatches($0, duration) }.count >= count
        }
    }

    func waitForActiveRequestCount(_ count: Int, duration: Duration, timeout: Duration = .seconds(5)) async throws {
        try await waitUntil(timeout: timeout) {
            self.continuations.values.filter { Self.approximatelyMatches($0.duration, duration) }.count == count
        }
    }

    private func waitUntil(timeout: Duration, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw WaitTimeout() }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    func requestCount(for duration: Duration) -> Int {
        requestedDurations.filter { Self.approximatelyMatches($0, duration) }.count
    }

    func hasActiveRequest(for duration: Duration) -> Bool {
        continuations.values.contains { Self.approximatelyMatches($0.duration, duration) }
    }

    /// The scheduler converts the remaining interval to whole milliseconds and
    /// rounds up, so a request made from the real clock can land a sub-
    /// millisecond away from the exact interval the test names. Compare with a
    /// 10 ms tolerance: large enough to absorb that rounding and CI scheduling
    /// delay, small enough that neighbouring whole-second intervals (599 s and
    /// 600 s) never alias.
    private static func approximatelyMatches(_ lhs: Duration, _ rhs: Duration) -> Bool {
        func seconds(_ duration: Duration) -> Double {
            let components = duration.components
            return Double(components.seconds)
                + Double(components.attoseconds) / 1_000_000_000_000_000_000
        }
        return abs(seconds(lhs) - seconds(rhs)) < 0.01
    }

    func fire(duration: Duration) {
        guard let id = continuations.first(where: { $0.value.duration == duration })?.key,
              let waiter = continuations.removeValue(forKey: id) else { return }
        waiter.continuation.resume()
    }

    private func cancel(_ id: Int) {
        continuations.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }
}
