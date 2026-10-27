import Foundation
import XCTest
@testable import StatusTrioCore

private final class EnergyReadGate: @unchecked Sendable {
    private let lock = NSLock()
    let gate = DispatchSemaphore(value: 0)
    private var reads = 0
    var count: Int { lock.withLock { reads } }

    func read(_ apps: [EnergyApplication]) -> ApplicationEnergySnapshot {
        let count = lock.withLock { reads += 1; return reads }
        let readAt = ProcessInfo.processInfo.systemUptime
        _ = gate.wait(timeout: .now() + 5)
        return ApplicationEnergySnapshot(readAt: readAt, processes: apps.map {
            ProcessEnergySample(pid: 1, startedAt: 1, app: $0,
                cpuNanoseconds: UInt64(count) * 1_000_000_000,
                energyNanojoules: UInt64(count) * 1_000_000_000)
        })
    }
}

@MainActor
final class ApplicationEnergyControllerTests: XCTestCase {
    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<1_000 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for energy reader")
    }

    func testDisabledCollectorDoesNotReadAndClosingDropsLateResultsAndQueuedReads() async {
        let gate = EnergyReadGate()
        let controller = ApplicationEnergyController(reader: { gate.read($0) },
            applications: { [EnergyApplication(id: "/App.app", name: "App")] })
        controller.refresh()
        XCTAssertEqual(gate.count, 0)
        controller.activate()
        await waitUntil { gate.count == 1 }
        for _ in 0..<20 { controller.refresh() }
        XCTAssertEqual(gate.count, 1)
        controller.deactivate()
        gate.gate.signal()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(gate.count, 1)
        XCTAssertTrue(controller.ranking.apps.isEmpty)
        controller.refresh()
        XCTAssertEqual(gate.count, 1)
    }

    func testReopeningNeverUsesThePreviousSessionBaseline() async {
        let gate = EnergyReadGate()
        let controller = ApplicationEnergyController(reader: { gate.read($0) },
            applications: { [EnergyApplication(id: "/App.app", name: "App")] })
        controller.activate()
        await waitUntil { gate.count == 1 }
        controller.deactivate()
        controller.activate()
        gate.gate.signal()
        await waitUntil { gate.count == 2 }
        XCTAssertTrue(controller.ranking.apps.isEmpty)
        gate.gate.signal()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(controller.ranking.phase, .sampling)
        controller.deactivate()
    }

    func testPublishedRankingExpiresWhileTheNextReadIsBlocked() async {
        let gate = EnergyReadGate()
        let controller = ApplicationEnergyController(reader: { gate.read($0) },
            applications: { [EnergyApplication(id: "/App.app", name: "App")] })
        controller.activate()
        await waitUntil { gate.count == 1 }
        gate.gate.signal()
        // Ensure the two actual samples form a nonzero observation interval.
        try? await Task.sleep(for: .milliseconds(600))
        controller.refresh()
        await waitUntil { gate.count == 2 }
        gate.gate.signal()
        await waitUntil { controller.ranking.phase == .ready }
        XCTAssertEqual(controller.ranking.apps.map(\.name), ["App"])
        controller.refresh()
        await waitUntil { gate.count == 3 }
        controller.refresh(now: ProcessInfo.processInfo.systemUptime + 16)
        XCTAssertTrue(controller.ranking.apps.isEmpty)
        XCTAssertEqual(controller.ranking.phase, .sampling)
        controller.deactivate()
        gate.gate.signal()
    }
}
