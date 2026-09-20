import Foundation
import XCTest
@testable import StatusTrioCore

/// The Bluetooth controller used to start one `system_profiler` run per caller
/// with nothing serializing them, and it kept polling after the popover that
/// needed the data was gone. These tests pin the read latch and the surface
/// gate that replaced both behaviours.
@MainActor
final class BluetoothPollingLifetimeTests: XCTestCase {
    private func makeController(
        reader: DeferredBluetoothDeviceReader,
        stateMonitor: AvailableBluetoothStateMonitor = AvailableBluetoothStateMonitor(),
        safetyNetSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) -> BluetoothDeviceController {
        BluetoothDeviceController(
            worker: reader,
            stateMonitor: stateMonitor,
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            safetyNetSleep: safetyNetSleep
        )
    }

    /// A read that is in flight swallows the next request into one follow-up,
    /// so a burst of triggers cannot spawn one process per trigger.
    func testReadsCoalesceIntoOneFollowUpWhileAReadIsInFlight() async {
        let reader = DeferredBluetoothDeviceReader()
        let controller = makeController(reader: reader)
        controller.activate()
        await waitUntil { reader.readCount == 1 }

        controller.refresh()
        controller.refresh()
        controller.refresh()
        XCTAssertEqual(reader.readCount, 1, "extra triggers must not start extra reads")

        reader.complete(.success([]))
        await waitUntil { reader.readCount == 2 }
        XCTAssertEqual(reader.readCount, 2, "three requests collapse into one follow-up")

        reader.complete(.success([]))
        await waitUntil { !reader.hasPendingRead }
        XCTAssertEqual(reader.readCount, 2)

        controller.deactivate()
    }

    /// The adapter powering off discards the in-flight read. Its completion
    /// must still release the latch, or every later refresh is coalesced into a
    /// follow-up that never starts and the row freezes forever.
    func testSupersededReadReleasesTheLatchAndTheNextRefreshRuns() async {
        let reader = DeferredBluetoothDeviceReader()
        let monitor = AvailableBluetoothStateMonitor()
        let controller = makeController(reader: reader, stateMonitor: monitor)
        controller.activate()
        await waitUntil { reader.readCount == 1 }

        monitor.emit(authorization: .allowed, managerState: .poweredOff)
        reader.complete(.success([
            BluetoothDevice(id: "1", name: "AirPods Pro", kind: .audio, isConnected: true)
        ]))
        await Task.yield()

        XCTAssertEqual(controller.availability, .poweredOff)
        XCTAssertTrue(controller.devices.isEmpty, "a superseded read must not republish devices")

        monitor.emit(authorization: .allowed, managerState: .poweredOn)
        await waitUntil { reader.readCount == 2 }

        reader.complete(.success([
            BluetoothDevice(id: "2", name: "MX Keys", kind: .peripheral, isConnected: true)
        ]))
        await waitUntil { controller.devices.map(\.id) == ["2"] }

        controller.deactivate()
    }

    /// The safety net is a fallback for the connection notifications, and it may
    /// only run while something on screen shows device state.
    func testSafetyNetPollRunsOnlyWhileASurfaceIsHeld() async {
        let reader = DeferredBluetoothDeviceReader()
        let sleeper = ManualEventSleeper()
        let controller = makeController(
            reader: reader,
            safetyNetSleep: { duration in await sleeper.sleep(duration) }
        )
        controller.activate()
        await waitUntil { reader.readCount == 1 }
        reader.complete(.success([]))
        await waitUntil { !reader.hasPendingRead }

        XCTAssertFalse(controller.isSafetyNetPolling, "a poll started with nothing on screen")

        controller.holdVisibleSurface("bluetooth.summary")
        _ = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertTrue(controller.isSafetyNetPolling)
        XCTAssertEqual(sleeper.durations.first, .seconds(30))

        sleeper.releaseAll()
        await waitUntil { reader.readCount == 2 }
        reader.complete(.success([]))
        await waitUntil { !reader.hasPendingRead }

        controller.releaseVisibleSurface("bluetooth.summary")
        XCTAssertFalse(controller.isSafetyNetPolling)
        let callCountWhenReleased = sleeper.callCount
        sleeper.releaseAll()
        await Task.yield()
        XCTAssertEqual(sleeper.callCount, callCountWhenReleased, "a released surface must stop polling")
        XCTAssertEqual(reader.readCount, 2)

        controller.deactivate()
    }

    /// Two surfaces (the summary row and the detail page) can be on screen in
    /// either order, so the gate is a claim count rather than a boolean.
    func testTheLastReleasedSurfaceStopsThePoll() async {
        let sleeper = ManualEventSleeper()
        let controller = makeController(
            reader: DeferredBluetoothDeviceReader(),
            safetyNetSleep: { duration in await sleeper.sleep(duration) }
        )
        controller.activate()

        controller.holdVisibleSurface("bluetooth.summary")
        controller.holdVisibleSurface("bluetooth.detail")
        controller.releaseVisibleSurface("bluetooth.summary")

        XCTAssertTrue(controller.isSafetyNetPolling)
        controller.releaseVisibleSurface("bluetooth.detail")
        XCTAssertFalse(controller.isSafetyNetPolling)
        controller.releaseVisibleSurface("bluetooth.detail")
        XCTAssertFalse(controller.isSafetyNetPolling)

        controller.deactivate()
    }

    /// Deactivating the controller keeps the surface claims (they belong to the
    /// views) but must not leave a poll running.
    func testDeactivateStopsThePollWithoutDroppingSurfaceClaims() async {
        let sleeper = ManualEventSleeper()
        let controller = makeController(
            reader: DeferredBluetoothDeviceReader(),
            safetyNetSleep: { duration in await sleeper.sleep(duration) }
        )
        controller.activate()
        controller.holdVisibleSurface("bluetooth.summary")
        XCTAssertTrue(controller.isSafetyNetPolling)

        controller.deactivate()
        XCTAssertTrue(controller.hasVisibleSurface)
        XCTAssertFalse(controller.isSafetyNetPolling)
    }

    /// A cancelled poll's `defer` must not clear the reference to the poll that
    /// replaced it. A stop and a start can land in the same main-actor turn,
    /// before the cancelled task has run its `defer`; an unconditional
    /// `periodicRefreshTask = nil` then makes `isSafetyNetPolling` lie and
    /// leaves the running task uncancellable.
    func testARestartInTheSameTurnKeepsTheNewPollTrackedAndCancellable() async {
        let reader = ImmediateBluetoothDeviceReader()
        let sleeper = ManualEventSleeper()
        // The poll's guard also stops it when the surface goes away, so
        // cancellation is only observable from inside the sleep it was parked
        // in: after the sleep resumes, `Task.isCancelled` is the answer.
        let cancellations = SleepCancellationRecorder()
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: AvailableBluetoothStateMonitor(),
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            safetyNetSleep: { duration in
                await sleeper.sleep(duration)
                cancellations.record(Task.isCancelled)
            }
        )
        controller.activate()
        await waitUntil { reader.readCount == 1 }
        controller.holdVisibleSurface("bluetooth.summary")
        _ = await sleeper.waitForCallCount(1, timeout: .seconds(1))

        // Stop and restart inside one turn, before the cancelled task's `defer`.
        controller.releaseVisibleSurface("bluetooth.summary")
        controller.holdVisibleSurface("bluetooth.summary")
        XCTAssertTrue(controller.isSafetyNetPolling, "the restarted poll must be tracked")

        // Let the replacement reach its own sleep, then release both so the
        // superseded task runs through to its `defer`.
        _ = await sleeper.waitForCallCount(2, timeout: .seconds(1))
        sleeper.releaseAll()
        await waitUntil { reader.readCount >= 3 }
        await settle()
        XCTAssertTrue(
            controller.isSafetyNetPolling,
            "a superseded poll's defer must not clear the replacement's reference"
        )

        // The replacement must still be cancellable: letting go of the last
        // surface has to cancel the task the restart created.
        controller.releaseVisibleSurface("bluetooth.summary")
        XCTAssertFalse(controller.isSafetyNetPolling)
        sleeper.releaseAll()
        await settle()
        XCTAssertEqual(
            cancellations.resumed.last,
            true,
            "the restarted poll must actually be cancelled"
        )

        controller.deactivate()
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the Bluetooth controller")
    }

    /// Lets every main-actor task that is already runnable finish.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
        for _ in 0..<20 { await Task.yield() }
    }
}

/// Answers every read straight away, so a test that only cares about the poll's
/// task lifetime never has to complete a read by hand.
private final class ImmediateBluetoothDeviceReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var readCount: Int { lock.withLock { count } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock { count += 1 }
        completion(.success([]))
    }
}

/// Records what each parked sleep saw when it resumed, which is how a test tells
/// "the task was cancelled" apart from "the task's guard happened to stop it".
private final class SleepCancellationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    var resumed: [Bool] { lock.withLock { values } }

    func record(_ cancelled: Bool) {
        lock.withLock { values.append(cancelled) }
    }
}

/// Answers device reads only when the test says so, which is what makes the
/// in-flight latch observable.
private final class DeferredBluetoothDeviceReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@Sendable (BluetoothWorkerResult) -> Void] = []
    private var count = 0

    var readCount: Int { lock.withLock { count } }
    var hasPendingRead: Bool { lock.withLock { !pending.isEmpty } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock {
            count += 1
            pending.append(completion)
        }
    }

    func complete(_ result: BluetoothWorkerResult) {
        let completion = lock.withLock { pending.isEmpty ? nil : pending.removeFirst() }
        completion?(result)
    }
}

@MainActor
private final class AvailableBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() { onStateChange?(.allowed, .poweredOn) }
    func stop() {}

    func emit(authorization: BluetoothAuthorizationStatus, managerState: BluetoothManagerState) {
        onStateChange?(authorization, managerState)
    }
}

private final class SilentBluetoothBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]) -> Void) {
        completion([:])
    }
}
