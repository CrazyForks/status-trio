import Foundation
import XCTest

@testable import StatusTrioCore

@MainActor
final class HuaweiTransportLifecycleTests: XCTestCase {
    func testAlreadyCancelledOperationDoesNotStartTransport() async {
        let probe = LifecycleProbe()
        let transport = makeTransport(probe: probe)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.state(address: "AA:BB:CC:DD:EE:FF")
        }

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertEqual(probe.operationCount, 0)
        XCTAssertEqual(transport.transportThreadCount, 0)
    }

    func testCloseDuringRunningOperationCancelsBeforeSideEffect() async {
        let probe = LifecycleProbe()
        let operationStarted = expectation(description: "operation started")
        let closed = expectation(description: "sessions closed")
        let gate = DispatchSemaphore(value: 0)
        let transport = makeTransport(
            probe: probe,
            runOperation: { request, context in
                operationStarted.fulfill()
                guard gate.wait(timeout: .now() + 2) == .success else {
                    throw LifecycleProbeError.gateTimedOut
                }
                return try probe.execute(request, context: context)
            },
            didCloseSessions: { _ in closed.fulfill() }
        )
        let task = Task.detached {
            try await transport.setMode(.cancellation, address: "AA:BB:CC:DD:EE:FF")
        }

        await fulfillment(of: [operationStarted], timeout: 2)
        transport.closeAll()
        gate.signal()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        await fulfillment(of: [closed], timeout: 2)
        XCTAssertEqual(probe.operationCount, 0)
    }

    func testCloseDuringStartupInvalidatesOperation() async {
        let probe = LifecycleProbe()
        let startupEntered = expectation(description: "startup entered")
        let closed = expectation(description: "sessions closed")
        let gate = DispatchSemaphore(value: 0)
        let transport = makeTransport(
            probe: probe,
            didStartTransportThread: {
                startupEntered.fulfill()
                _ = gate.wait(timeout: .now() + 2)
            },
            didCloseSessions: { _ in closed.fulfill() }
        )
        let task = Task.detached {
            try await transport.state(address: "AA:BB:CC:DD:EE:FF")
        }

        await fulfillment(of: [startupEntered], timeout: 2)
        transport.closeAll()
        gate.signal()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        await fulfillment(of: [closed], timeout: 2)
        XCTAssertEqual(probe.operationCount, 0)
        XCTAssertEqual(transport.transportThreadCount, 1)
    }

    func testQueuedOperationsDoNotReenterTransportDrain() async throws {
        let probe = LifecycleProbe()
        let firstStarted = expectation(description: "first operation started")
        let secondQueued = expectation(description: "second operation queued")
        let gate = DispatchSemaphore(value: 0)
        let secondAddress = "11:22:33:44:55:66"
        let transport = makeTransport(
            probe: probe,
            didEnqueue: { request in
                if case .state(let address) = request, address == secondAddress {
                    secondQueued.fulfill()
                }
            },
            runOperation: { request, context in
                if probe.noteRunStarted() == 1 {
                    firstStarted.fulfill()
                    guard gate.wait(timeout: .now() + 2) == .success else {
                        throw LifecycleProbeError.gateTimedOut
                    }
                }
                return try probe.execute(request, context: context)
            }
        )
        let first = Task.detached {
            try await transport.state(address: "AA:BB:CC:DD:EE:FF")
        }

        await fulfillment(of: [firstStarted], timeout: 2)
        let second = Task.detached {
            try await transport.state(address: "11:22:33:44:55:66")
        }
        await fulfillment(of: [secondQueued], timeout: 2)
        gate.signal()

        let firstState = try await first.value
        let secondState = try await second.value
        XCTAssertEqual(firstState.mode, HuaweiNoiseMode.cancellation)
        XCTAssertEqual(secondState.mode, HuaweiNoiseMode.cancellation)
        XCTAssertEqual(probe.operationCount, 2)
        XCTAssertEqual(probe.maximumExecutionDepth, 1)
        XCTAssertEqual(transport.transportThreadCount, 1)
    }

    func testCloseAndReopenUsesFreshSessionOnSameTransportThread() async throws {
        let probe = LifecycleProbe()
        let closed = expectation(description: "sessions closed")
        let transport = makeTransport(
            probe: probe,
            didCloseSessions: { _ in closed.fulfill() }
        )

        _ = try await transport.state(address: "AA:BB:CC:DD:EE:FF")
        transport.closeAll()
        await fulfillment(of: [closed], timeout: 2)

        _ = try await transport.state(address: "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(probe.sessionGenerations, [0, 1])
        XCTAssertEqual(transport.transportThreadCount, 1)
    }

    private func makeTransport(
        probe: LifecycleProbe,
        didStartTransportThread: (@Sendable () -> Void)? = nil,
        didEnqueue: (@Sendable (HuaweiRFCOMMTransport.OperationRequest) -> Void)? = nil,
        runOperation: (
            @Sendable (HuaweiRFCOMMTransport.OperationRequest, HuaweiRFCOMMTransport.OperationContext) throws -> HuaweiNoiseState
        )? = nil,
        didCloseSessions: (@Sendable (UInt64) -> Void)? = nil
    ) -> HuaweiRFCOMMTransport {
        HuaweiRFCOMMTransport(hooks: .init(
            didStartTransportThread: didStartTransportThread,
            didEnqueue: didEnqueue,
            runOperation: runOperation ?? { request, context in
                try probe.execute(request, context: context)
            },
            didCloseSessions: didCloseSessions
        ))
    }
}

private final class LifecycleProbe: @unchecked Sendable {
    private struct State {
        var operations = 0
        var runStarts = 0
        var executionDepth = 0
        var maximumExecutionDepth = 0
        var sessionGenerations: [UInt64] = []
    }

    private let lock = NSLock()
    private var state = State()

    var operationCount: Int { lock.withLock { state.operations } }
    var maximumExecutionDepth: Int { lock.withLock { state.maximumExecutionDepth } }
    var sessionGenerations: [UInt64] { lock.withLock { state.sessionGenerations } }

    func noteRunStarted() -> Int {
        lock.withLock {
            state.runStarts += 1
            return state.runStarts
        }
    }

    func execute(
        _ request: HuaweiRFCOMMTransport.OperationRequest,
        context: HuaweiRFCOMMTransport.OperationContext
    ) throws -> HuaweiNoiseState {
        lock.withLock {
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
        lock.withLock {
            state.operations += 1
            state.sessionGenerations.append(context.sessionGeneration)
        }

        switch request {
        case .state:
            return HuaweiNoiseState(level: 0, mode: HuaweiNoiseMode.cancellation.rawValue)!
        case .setMode(let mode, _):
            return HuaweiNoiseState(level: 0, mode: mode.rawValue)!
        }
    }
}

private enum LifecycleProbeError: Error {
    case gateTimedOut
}
