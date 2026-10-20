import Foundation
import XCTest

@testable import StatusTrioCore

@MainActor
final class HuaweiTransportLifecycleTests: XCTestCase {
    private let address = "AA:BB:CC:DD:EE:FF"

    func testAlreadyCancelledWriteDoesNotStartTransport() async throws {
        let channel = LifecycleFakeChannel()
        let transport = makeTransport(channel: channel)

        let task: Task<HuaweiNoiseState, any Error> = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.setMode(.cancellation, address: "A8:37:59:F1:77:3D")
        }

        try await assertCancellation(task)
        XCTAssertEqual(channel.readCount, 0)
        XCTAssertEqual(channel.writeCount, 0)
        XCTAssertEqual(transport.transportThreadCount, 0)
    }

    func testCancelledQueuedWriteNeverReachesChannel() async throws {
        let channel = LifecycleFakeChannel()
        let firstStarted = BlockingGate()
        channel.blockNextState(beforeSideEffect: firstStarted)
        let queued = AsyncSignal()
        let transport = makeTransport(
            channel: channel,
            didEnqueue: { request in
                if case .setMode = request {
                    queued.signal()
                }
            }
        )

        let first: Task<HuaweiNoiseState, any Error> = Task.detached {
            try await transport.state(address: "A8:37:59:F1:77:3D")
        }
        defer {
            firstStarted.release()
            first.cancel()
        }
        try await firstStarted.entered.wait(seconds: 2)

        let second: Task<HuaweiNoiseState, any Error> = Task.detached {
            try await transport.setMode(.cancellation, address: "A8:37:59:F1:77:3D")
        }
        defer { second.cancel() }
        try await queued.wait(seconds: 2)
        second.cancel()
        firstStarted.release()

        _ = try await taskValue(first, seconds: 2)
        try await assertCancellation(second)
        XCTAssertEqual(channel.writeCount, 0)
    }

    func testCancelledRunningWriteStopsBeforeReadback() async throws {
        let channel = LifecycleFakeChannel()
        let writeStarted = BlockingGate()
        channel.blockNextWrite(afterSideEffect: writeStarted)
        let transport = makeTransport(channel: channel)

        let task: Task<HuaweiNoiseState, any Error> = Task.detached {
            try await transport.setMode(.cancellation, address: "A8:37:59:F1:77:3D")
        }
        defer {
            writeStarted.release()
            task.cancel()
        }
        try await writeStarted.entered.wait(seconds: 2)
        task.cancel()
        writeStarted.release()

        try await assertCancellation(task)
        XCTAssertEqual(channel.writeCount, 1)
        XCTAssertEqual(channel.readCount, 0)
    }

    func testCancellationAfterCompletionDoesNotChangeResult() async throws {
        let channel = LifecycleFakeChannel()
        let transport = makeTransport(channel: channel)
        let task: Task<HuaweiNoiseState, any Error> = Task.detached {
            try await transport.setMode(.awareness, address: "A8:37:59:F1:77:3D")
        }

        let result = try await taskValue(task, seconds: 2)
        task.cancel()

        XCTAssertEqual(result.mode, HuaweiNoiseMode.awareness)
        XCTAssertEqual(channel.writeCount, 1)
        XCTAssertEqual(channel.readCount, 1)
    }

    func testCloseSignalDoesNotTreatDuplicateCutoffAsAnotherCutoff() async throws {
        let closed = CloseSignal()
        closed.signal(0)
        closed.signal(0)

        do {
            try await closed.wait(for: 1, seconds: 0.05)
            XCTFail("A duplicate cutoff 0 satisfied cutoff 1")
        } catch LifecycleTestError.signalTimedOut {
            // Expected: only cutoff 1 can satisfy cutoff 1.
        }

        closed.signal(1)
        try await closed.wait(for: 1, seconds: 2)
    }

    func testCloseAllSkipsCancelledQueuedWrites() async throws {
        let channel = LifecycleFakeChannel()
        let firstStarted = BlockingGate()
        channel.blockNextState(beforeSideEffect: firstStarted)
        let queued = AsyncSignal()
        let closed = CloseSignal()
        let transport = makeTransport(
            channel: channel,
            didEnqueue: { request in
                if case .setMode = request {
                    queued.signal()
                }
            },
            didCloseSessions: { cutoff in
                channel.closeSessions(through: cutoff)
                closed.signal(cutoff)
            }
        )

        let first: Task<HuaweiNoiseState, any Error> = Task.detached {
            try await transport.state(address: "A8:37:59:F1:77:3D")
        }
        defer {
            firstStarted.release()
            first.cancel()
        }
        try await firstStarted.entered.wait(seconds: 2)
        let second: Task<HuaweiNoiseState, any Error> = Task.detached {
            try await transport.setMode(.cancellation, address: "A8:37:59:F1:77:3D")
        }
        defer { second.cancel() }
        try await queued.wait(seconds: 2)
        second.cancel()

        transport.closeAll()
        firstStarted.release()

        try await assertCancellation(second)
        try await assertCancellation(first)
        try await closed.wait(for: 0, seconds: 2)
        XCTAssertEqual(channel.writeCount, 0)
        XCTAssertEqual(channel.connectionCount, 0)
    }

    func testCloseDuringNestedRunLoopDoesNotReenterDrain() async throws {
        let channel = LifecycleFakeChannel()
        let firstStarted = BlockingGate()
        channel.blockNextState(pumpingRunLoop: firstStarted)
        let nestedReady = AsyncSignal()
        channel.didNestedRunLoop = { nestedReady.signal() }
        let queued = AsyncSignal()
        let closed = CloseSignal()
        let transport = makeTransport(
            channel: channel,
            didEnqueue: { request in
                if case .setMode = request {
                    queued.signal()
                }
            },
            didCloseSessions: { cutoff in
                channel.closeSessions(through: cutoff)
                closed.signal(cutoff)
            }
        )

        let first: Task<HuaweiNoiseState, any Error> = Task.detached {
            try await transport.state(address: "A8:37:59:F1:77:3D")
        }
        defer {
            firstStarted.release()
            first.cancel()
        }
        try await nestedReady.wait(seconds: 2)
        let second: Task<HuaweiNoiseState, any Error> = Task.detached {
            try await transport.setMode(.cancellation, address: "A8:37:59:F1:77:3D")
        }
        defer { second.cancel() }
        try await queued.wait(seconds: 2)
        transport.closeAll()
        firstStarted.release()

        try await assertCancellation(first)
        try await assertCancellation(second)
        try await closed.wait(for: 0, seconds: 2)
        XCTAssertEqual(channel.maximumExecutionDepth, 1)
        XCTAssertEqual(channel.writeCount, 0)
        XCTAssertEqual(channel.connectionCount, 0)
    }

    func testCloseDuringStartupInvalidatesOldSession() async throws {
        let channel = LifecycleFakeChannel()
        let startup = BlockingGate()
        let transport = makeTransport(
            channel: channel,
            didStartTransportThread: { try? startup.block() }
        )

        let old: Task<HuaweiNoiseState, any Error> = Task.detached {
            try await transport.state(address: "A8:37:59:F1:77:3D")
        }
        defer {
            startup.release()
            old.cancel()
        }
        try await startup.entered.wait(seconds: 2)

        transport.closeAll()
        startup.release()

        try await assertCancellation(old)
        XCTAssertEqual(channel.readCount, 0)
        XCTAssertEqual(channel.connectionCount, 0)
        XCTAssertEqual(transport.transportThreadCount, 1)
    }

    func testCloseAfterRunLoopAcquiredBeforePendingAppendCancelsOperation() async throws {
        let channel = LifecycleFakeChannel()
        let acquired = BlockingGate()
        let transport = makeTransport(channel: channel, didAcquireRunLoop: { try? acquired.block() })

        let operation: Task<HuaweiNoiseState, any Error> = Task.detached {
            try await transport.state(address: "A8:37:59:F1:77:3D")
        }
        defer {
            acquired.release()
            operation.cancel()
        }
        try await acquired.entered.wait(seconds: 2)

        transport.closeAll()
        acquired.release()

        try await assertCancellation(operation)
        XCTAssertEqual(channel.readCount, 0)
        XCTAssertEqual(channel.connectionCount, 0)
        XCTAssertEqual(transport.transportThreadCount, 1)
    }

    func testReopenAfterStartupCloseUsesNewSession() async throws {
        let channel = LifecycleFakeChannel()
        let startup = BlockingGate()
        let closed = CloseSignal()
        let transport = makeTransport(
            channel: channel,
            didStartTransportThread: { try? startup.block() },
            didCloseSessions: { cutoff in
                channel.closeSessions(through: cutoff)
                closed.signal(cutoff)
            }
        )

        let old: Task<HuaweiNoiseState, any Error> = Task.detached {
            try await transport.state(address: "A8:37:59:F1:77:3D")
        }
        defer {
            startup.release()
            old.cancel()
        }
        try await startup.entered.wait(seconds: 2)
        transport.closeAll()
        startup.release()
        try await assertCancellation(old)

        let reopened = try await taskValue(
            Task { try await transport.state(address: "A8:37:59:F1:77:3D") },
            seconds: 2
        )
        XCTAssertEqual(reopened.mode, HuaweiNoiseMode.cancellation)
        XCTAssertEqual(channel.connectionCount, 1)
        XCTAssertEqual(transport.transportThreadCount, 1)

        transport.closeAll()
        try await closed.wait(for: 1, seconds: 2)
        transport.closeAll()
        try await closed.wait(for: 2, seconds: 2)
        XCTAssertEqual(channel.connectionCount, 0)

        let afterRepeatedClose = try await taskValue(
            Task { try await transport.state(address: "A8:37:59:F1:77:3D") },
            seconds: 2
        )
        XCTAssertEqual(afterRepeatedClose.mode, HuaweiNoiseMode.cancellation)
        XCTAssertEqual(channel.connectionCount, 1)
        XCTAssertEqual(transport.transportThreadCount, 1)

        transport.closeAll()
        try await closed.wait(for: 3, seconds: 2)
        XCTAssertEqual(channel.connectionCount, 0)
    }

    func testCloseBeforeFirstUseThenReadStartsCleanSession() async throws {
        let channel = LifecycleFakeChannel()
        let closed = CloseSignal()
        let transport = makeTransport(
            channel: channel,
            didCloseSessions: { cutoff in
                channel.closeSessions(through: cutoff)
                closed.signal(cutoff)
            }
        )

        transport.closeAll()
        transport.closeAll()

        let state = try await taskValue(
            Task { try await transport.state(address: "A8:37:59:F1:77:3D") },
            seconds: 2
        )
        XCTAssertEqual(state.mode, HuaweiNoiseMode.cancellation)
        XCTAssertEqual(channel.readCount, 1)
        XCTAssertEqual(channel.operationThreads, ["StatusTrio.HuaweiRFCOMM"])
        XCTAssertEqual(channel.connectionCount, 1)
        XCTAssertEqual(transport.transportThreadCount, 1)

        transport.closeAll()
        try await closed.wait(for: 2, seconds: 2)
        XCTAssertEqual(channel.connectionCount, 0)
    }

    private func makeTransport(
        channel: LifecycleFakeChannel,
        didStartTransportThread: (@Sendable () -> Void)? = nil,
        didAcquireRunLoop: (@Sendable () -> Void)? = nil,
        didEnqueue: (@Sendable (HuaweiRFCOMMTransport.OperationRequest) -> Void)? = nil,
        didCloseSessions: (@Sendable (UInt64) -> Void)? = nil
    ) -> HuaweiRFCOMMTransport {
        HuaweiRFCOMMTransport(hooks: .init(
            didStartTransportThread: didStartTransportThread,
            didAcquireRunLoop: didAcquireRunLoop,
            didEnqueue: didEnqueue,
            runOperation: { request, context in
                try channel.run(request, context: context)
            },
            didCloseSessions: didCloseSessions
        ))
    }

    private func assertCancellation<T: Sendable>(
        _ task: Task<T, any Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        guard await taskCompletes(task, seconds: 2) else {
            throw LifecycleTestError.taskTimedOut
        }
        do {
            _ = try await task.value
            XCTFail("Expected CancellationError", file: file, line: line)
        } catch is CancellationError {
            return
        } catch {
            XCTFail("Expected CancellationError, got \(error)", file: file, line: line)
        }
    }
}

private final class LifecycleFakeChannel: @unchecked Sendable {
    private struct State {
        var readCount = 0
        var writeCount = 0
        var sessions: [String: UInt64] = [:]
        var stateBlock: BlockingGate?
        var statePumpsRunLoop = false
        var writeBlock: BlockingGate?
        var operationThreads: [String] = []
        var executionDepth = 0
        var maximumExecutionDepth = 0
        var closeCount = 0
    }

    private let lock = NSLock()
    private var state = State()

    var readCount: Int { lock.withLock { state.readCount } }
    var writeCount: Int { lock.withLock { state.writeCount } }
    var connectionCount: Int { lock.withLock { state.sessions.count } }
    var operationThreads: [String] { lock.withLock { state.operationThreads } }
    var maximumExecutionDepth: Int { lock.withLock { state.maximumExecutionDepth } }
    var closeCount: Int { lock.withLock { state.closeCount } }
    var didNestedRunLoop: (@Sendable () -> Void)?

    func blockNextState(beforeSideEffect gate: BlockingGate) {
        lock.withLock {
            state.stateBlock = gate
            state.statePumpsRunLoop = false
        }
    }

    func blockNextState(pumpingRunLoop gate: BlockingGate) {
        lock.withLock {
            state.stateBlock = gate
            state.statePumpsRunLoop = true
        }
    }

    func blockNextWrite(afterSideEffect gate: BlockingGate) {
        lock.withLock { state.writeBlock = gate }
    }

    func closeSessions(through cutoff: UInt64) {
        lock.withLock {
            state.closeCount += 1
            state.sessions = state.sessions.filter { $0.value > cutoff }
        }
    }

    func run(
        _ request: HuaweiRFCOMMTransport.OperationRequest,
        context: HuaweiRFCOMMTransport.OperationContext
    ) throws -> HuaweiNoiseState {
        lock.withLock {
            state.operationThreads.append(Thread.current.name ?? "")
            state.executionDepth += 1
            state.maximumExecutionDepth = max(
                state.maximumExecutionDepth,
                state.executionDepth
            )
        }
        defer {
            lock.withLock { state.executionDepth -= 1 }
        }
        try context.checkpoint()

        switch request {
        case .state(let address):
            let (gate, pumpsRunLoop) = lock.withLock {
                defer { state.stateBlock = nil }
                return (state.stateBlock, state.statePumpsRunLoop)
            }
            if pumpsRunLoop {
                try gate?.block(pumpingRunLoop: didNestedRunLoop)
            } else {
                try gate?.block()
            }
            try context.checkpoint()
            lock.withLock {
                state.readCount += 1
                state.sessions[address] = context.sessionGeneration
            }
            return HuaweiNoiseState(level: 0, mode: HuaweiNoiseMode.cancellation.rawValue)!

        case .setMode(let mode, let address):
            lock.withLock {
                state.writeCount += 1
                state.sessions[address] = context.sessionGeneration
            }
            let gate = lock.withLock {
                defer { state.writeBlock = nil }
                return state.writeBlock
            }
            try gate?.block()
            try context.checkpoint()
            lock.withLock { state.readCount += 1 }
            return HuaweiNoiseState(level: 0, mode: mode.rawValue)!
        }
    }
}

private final class BlockingGate: @unchecked Sendable {
    let entered = AsyncSignal()
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    func block() throws {
        entered.signal()
        guard releaseSemaphore.wait(timeout: .now() + 5) == .success else {
            throw LifecycleTestError.gateTimedOut
        }
    }

    func block(pumpingRunLoop didEnter: (@Sendable () -> Void)?) throws {
        entered.signal()
        didEnter?()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if releaseSemaphore.wait(timeout: .now()) == .success {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
        throw LifecycleTestError.gateTimedOut
    }

    func release() {
        releaseSemaphore.signal()
    }
}

private final class CloseSignal: @unchecked Sendable {
    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let lock = NSLock()
    private var observedCutoffs: Set<UInt64> = []
    private var nextWaiterID: UInt64 = 0
    private var waiters: [UInt64: [Waiter]] = [:]

    func signal(_ cutoff: UInt64) {
        let ready: [Waiter] = lock.withLock {
            observedCutoffs.insert(cutoff)
            return waiters.removeValue(forKey: cutoff) ?? []
        }
        for waiter in ready {
            waiter.continuation.resume(returning: true)
        }
    }

    func wait(for cutoff: UInt64, seconds: TimeInterval) async throws {
        let completed = await withCheckedContinuation { continuation in
            let registration: (UInt64?, Bool) = lock.withLock {
                if observedCutoffs.contains(cutoff) {
                    return (nil, true)
                }
                let id = nextWaiterID
                nextWaiterID &+= 1
                waiters[cutoff, default: []].append(Waiter(
                    id: id,
                    continuation: continuation
                ))
                return (id, false)
            }
            if registration.1 {
                continuation.resume(returning: true)
                return
            }
            guard let id = registration.0 else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                let continuation: CheckedContinuation<Bool, Never>? = self.lock.withLock {
                    guard var cutoffWaiters = self.waiters[cutoff],
                          let index = cutoffWaiters.firstIndex(where: { $0.id == id })
                    else {
                        return nil
                    }
                    let waiter = cutoffWaiters.remove(at: index)
                    if cutoffWaiters.isEmpty {
                        self.waiters.removeValue(forKey: cutoff)
                    } else {
                        self.waiters[cutoff] = cutoffWaiters
                    }
                    return waiter.continuation
                }
                continuation?.resume(returning: false)
            }
        }
        guard completed else {
            throw LifecycleTestError.signalTimedOut
        }
    }
}

private final class AsyncSignal: @unchecked Sendable {
    private struct Waiter {
        let id: UInt64
        let target: Int
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let lock = NSLock()
    private var count = 0
    private var nextWaiterID: UInt64 = 0
    private var waiters: [Waiter] = []

    func signal(target: Int = 1) {
        let ready: [Waiter] = lock.withLock {
            count = max(count + 1, target)
            let ready = waiters.filter { $0.target <= count }
            waiters.removeAll { $0.target <= count }
            return ready
        }
        for waiter in ready {
            waiter.continuation.resume(returning: true)
        }
    }

    fileprivate func wait(
        for target: Int = 1,
        seconds: TimeInterval
    ) async throws {
        let completed = await withCheckedContinuation { continuation in
            let registration: (UInt64?, Bool) = lock.withLock {
                if count >= target {
                    return (nil, true)
                }
                let id = nextWaiterID
                nextWaiterID &+= 1
                waiters.append(Waiter(
                    id: id,
                    target: target,
                    continuation: continuation
                ))
                return (id, false)
            }
            if registration.1 {
                continuation.resume(returning: true)
                return
            }
            guard let id = registration.0 else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                let continuation: CheckedContinuation<Bool, Never>? = self.lock.withLock {
                    guard let index = self.waiters.firstIndex(where: { $0.id == id }) else {
                        return nil
                    }
                    return self.waiters.remove(at: index).continuation
                }
                continuation?.resume(returning: false)
            }
        }
        guard completed else {
            throw LifecycleTestError.signalTimedOut
        }
    }
}

private enum LifecycleTestError: Error {
    case gateTimedOut
    case signalTimedOut
    case taskTimedOut
}

private func taskValue<T: Sendable>(
    _ task: Task<T, any Error>,
    seconds: TimeInterval = 2,
) async throws -> T {
    guard await taskCompletes(task, seconds: seconds) else {
        throw LifecycleTestError.taskTimedOut
    }
    do {
        return try await task.value
    } catch {
        XCTFail("Expected task value, got \(error)")
        throw error
    }
}

private func taskCompletes<T: Sendable>(
    _ task: Task<T, any Error>,
    seconds: TimeInterval
) async -> Bool {
    let completed = await withCheckedContinuation { continuation in
        let state = CompletionState(continuation)
        let monitor = Task {
            do {
                _ = try await task.value
            } catch {}
            state.finish(true)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            if state.finish(false) {
                task.cancel()
                monitor.cancel()
            }
        }
    }
    return completed
}

private final class CompletionState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    @discardableResult
    func finish(_ completed: Bool) -> Bool {
        let continuation: CheckedContinuation<Bool, Never>? = lock.withLock {
            guard let continuation else { return nil }
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: completed)
        return continuation != nil
    }
}
