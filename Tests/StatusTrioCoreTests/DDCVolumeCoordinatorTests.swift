import XCTest
@testable import StatusTrioCore

@MainActor
final class DDCVolumeCoordinatorTests: XCTestCase {
    func testSelectionImmediatelyReadsAndEmitsValidatedScalar() async {
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 50, maximum: 100)
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(
            transport: transport,
            sleep: { try await Task.sleep(for: $0) }
        ) { updates.append($0) }

        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil { updates.count == 1 }

        XCTAssertEqual(updates.first?.outputID, 93)
        XCTAssertEqual(updates.first?.uid, "DISPLAY-A")
        XCTAssertEqual(updates.first?.scalar, 0.5)
        coordinator.stop()
    }

    func testBurstWritesOnlyLatestValueAndReadsBackAfterWrite() async {
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 50, maximum: 100)
        let coordinator = DDCVolumeCoordinator(transport: transport, debounce: .milliseconds(20), sleep: { try await Task.sleep(for: $0) }) { _ in }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        coordinator.setVolume(0.2)
        coordinator.setVolume(0.4)
        coordinator.setVolume(0.8)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(transport.writeValues, [80])
        XCTAssertEqual(transport.operations, ["resolve", "read", "write", "read"])
        coordinator.stop()
    }

    func testSwitchBeforeDebounceDropsQueuedWrite() async {
        let transport = FakeDDCTransport()
        let coordinator = DDCVolumeCoordinator(transport: transport, debounce: .milliseconds(50), sleep: { try await Task.sleep(for: $0) }) { _ in }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        coordinator.setVolume(0.8)
        coordinator.select(outputID: 94, uid: "DISPLAY-B")
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(transport.writeValues.isEmpty)
        coordinator.stop()
    }

    func testBlockedReadKeepsMainActorResponsiveAndDropsLateGeneration() async {
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 30, maximum: 100)
        transport.blockNextRead()
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport, sleep: { try await Task.sleep(for: $0) }) { updates.append($0) }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await transport.waitUntilReadBlocked()

        coordinator.select(outputID: 94, uid: "DISPLAY-B")
        coordinator.refresh()
        XCTAssertEqual(coordinator.generation, 2)
        transport.releaseBlockedRead()
        await waitUntil { updates.contains { $0.uid == "DISPLAY-B" } }

        XCTAssertFalse(updates.contains { $0.uid == "DISPLAY-A" })
        XCTAssertEqual(transport.maximumConcurrentReads, 1)
        coordinator.stop()
    }

    func testClosedPollingUsesTenSeconds() async {
        let sleeper = ManualDDCSleeper()
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 70, maximum: 100)
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport, sleep: { duration in try await sleeper.sleep(duration) }) { updates.append($0) }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil { updates.count == 1 }
        await sleeper.waitForNextSleep()
        let closedInterval = await sleeper.duration()
        XCTAssertEqual(closedInterval, .seconds(10))
        coordinator.stop()
        await sleeper.releaseNext()
    }

    func testDetailsPollingAndWakeRefresh() async {
        let sleeper = ManualDDCSleeper()
        let transport = FakeDDCTransport()
        transport.reply = DDCVolumeReply(current: 70, maximum: 100)
        var updates: [DDCVolumeUpdate] = []
        let coordinator = DDCVolumeCoordinator(transport: transport, sleep: { duration in try await sleeper.sleep(duration) }) { updates.append($0) }
        coordinator.setDetailsVisible(true)
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        await waitUntil { updates.count == 1 }
        await sleeper.waitForNextSleep()
        let openInterval = await sleeper.duration()
        XCTAssertEqual(openInterval, .seconds(2))

        coordinator.setDisplayAsleep(true)
        coordinator.setDisplayAsleep(false)
        await waitUntil { updates.count == 2 }
        await sleeper.releaseNext()
        coordinator.stop()
    }

    func testSuccessfulReadResetsFailureBackoff() async {
        let sleeper = ManualDDCSleeper()
        let transport = FakeDDCTransport()
        transport.failReads = 3
        let coordinator = DDCVolumeCoordinator(transport: transport, sleep: { duration in try await sleeper.sleep(duration) }) { _ in }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        for interval in [Duration.seconds(2), .seconds(4), .seconds(8)] {
            await sleeper.waitForNextSleep()
            let observed = await sleeper.duration()
            XCTAssertEqual(observed, interval)
            if interval == .seconds(8) { transport.reply = DDCVolumeReply(current: 40, maximum: 100) }
            await sleeper.releaseNext()
        }
        await sleeper.waitForNextSleep()
        let successfulPollInterval = await sleeper.duration()
        XCTAssertEqual(successfulPollInterval, .seconds(10))
        transport.reply = nil
        await sleeper.releaseNext()
        await sleeper.waitForNextSleep()
        let resetInterval = await sleeper.duration()
        XCTAssertEqual(resetInterval, .seconds(2))
        coordinator.stop()
    }

    func testPollingIntervalsBackOffAndResetOnSuccess() async {
        let sleeper = ManualDDCSleeper()
        let transport = FakeDDCTransport()
        transport.failReads = 6
        let coordinator = DDCVolumeCoordinator(transport: transport, sleep: { duration in try await sleeper.sleep(duration) }) { _ in }
        coordinator.select(outputID: 93, uid: "DISPLAY-A")
        for interval in [Duration.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60)] {
            await sleeper.waitForNextSleep()
            let observed = await sleeper.duration()
            XCTAssertEqual(observed, interval)
            await sleeper.releaseNext()
        }
        coordinator.stop()
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 where !predicate() { try? await Task.sleep(for: .milliseconds(5)) }
    }
}

private final class FakeDDCTransport: DDCVolumeTransport, @unchecked Sendable {
    private let lock = NSLock()
    var reply: DDCVolumeReply?
    var failReads = 0
    private(set) var writeValues: [UInt16] = []
    private(set) var operations: [String] = []
    private(set) var readCount = 0
    private(set) var maximumConcurrentReads = 0
    private var activeReads = 0
    private var readGate: DispatchSemaphore?
    private var blockedRead = DispatchSemaphore(value: 0)

    func blockNextRead() { lock.withLock { readGate = DispatchSemaphore(value: 0) } }
    func waitUntilReadBlocked() async { for _ in 0..<100 { if lock.withLock({ readGate == nil && activeReads == 1 }) { return }; try? await Task.sleep(for: .milliseconds(5)) } }
    func releaseBlockedRead() { blockedRead.signal() }

    func resolve(uid: String) -> DDCDisplayTarget? { lock.withLock { operations.append("resolve") }; return DDCDisplayTarget(uid: uid, service: nil) }
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReply? {
        let gate = lock.withLock { () -> DispatchSemaphore? in
            operations.append("read")
            readCount += 1
            activeReads += 1
            maximumConcurrentReads = max(maximumConcurrentReads, activeReads)
            let gate = readGate
            readGate = nil
            return gate
        }
        if gate != nil { blockedRead.wait() }
        return lock.withLock {
            activeReads -= 1
            if failReads > 0 { failReads -= 1; return nil }
            return reply
        }
    }
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool { lock.withLock { operations.append("write"); writeValues.append(value) }; return true }
    func waitForReadCount(_ count: Int) async { for _ in 0..<100 { if lock.withLock({ readCount >= count }) { return }; try? await Task.sleep(for: .milliseconds(5)) } }
}

private actor ManualDDCSleeper {
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private(set) var lastDuration: Duration?
    func sleep(_ duration: Duration) async throws {
        lastDuration = duration
        try await withCheckedThrowingContinuation { waiters.append($0) }
    }
    func waitForNextSleep() async { for _ in 0..<100 where waiters.isEmpty { try? await Task.sleep(for: .milliseconds(5)) } }
    func duration() -> Duration? { lastDuration }
    func releaseNext() { if !waiters.isEmpty { waiters.removeFirst().resume() } }
}
