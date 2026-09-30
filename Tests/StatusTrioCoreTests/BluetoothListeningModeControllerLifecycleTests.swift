import CoreAudio
import Foundation
import XCTest

@testable import StatusTrioCore

/// A discovery source that returns canned endpoints and counts how often it was
/// asked, so the tests can pin the plan's "one discovery per refresh, never on a
/// timer" guarantee without touching CoreAudio.
private final class FakeEndpointProvider: CoreAudioBluetoothEndpointProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    let endpoints: [BluetoothListeningModeEndpoint]

    init(endpoints: [BluetoothListeningModeEndpoint]) {
        self.endpoints = endpoints
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _callCount
    }

    func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint] {
        lock.lock()
        _callCount += 1
        lock.unlock()
        return endpoints
    }
}

/// The lifecycle the row depends on: resolution only for connected AirPods, a
/// write that publishes an in-flight state and reconciles it against the
/// read-back, a failure that rolls back to what the device actually reports,
/// cancellation when the device goes away, and no residual work once the panel
/// closes. The write side reuses the same scripted backend the HAL suite proves,
/// so the controller is tested against the real confirm/unconfirm/fail outcomes
/// rather than a mock of them.
@MainActor
final class BluetoothListeningModeControllerLifecycleTests: XCTestCase {
    private let deviceAddress = "AA:BB:CC:DD:EE:FF"
    private var key: String { BluetoothBatteryReader.normalizedAddress(deviceAddress) }
    private let endpointID: AudioDeviceID = 42

    // MARK: - Fixtures

    private func device(connected: Bool = true, airPods: Bool = true) -> BluetoothDevice {
        BluetoothDevice(
            id: deviceAddress,
            name: airPods ? "AirPods Pro" : "Plain Buds",
            kind: .audio,
            isConnected: connected
        )
    }

    private func capability(
        modes: [BluetoothListeningMode] = [.noiseCancellation, .transparency, .adaptive],
        current: BluetoothListeningMode? = .noiseCancellation,
        canSet: Bool = true
    ) -> BluetoothListeningModeCapability {
        BluetoothListeningModeCapability(
            audioDeviceID: endpointID,
            availableModes: modes,
            currentMode: current,
            canSet: canSet
        )
    }

    private func endpoint(
        address: String? = "aa:bb:cc:dd:ee:ff",
        isDefault: Bool = true,
        capability: BluetoothListeningModeCapability? = nil
    ) -> BluetoothListeningModeEndpoint {
        BluetoothListeningModeEndpoint(
            audioDeviceID: endpointID,
            capability: capability ?? self.capability(),
            isDefaultOutput: isDefault,
            bluetoothAddress: address
        )
    }

    /// A controller whose HAL writes through a scripted backend and settles the
    /// read-back instantly, with a short failure linger so rollback tests can
    /// observe the failure before it clears.
    private func makeController(
        endpoints: [BluetoothListeningModeEndpoint],
        backend: FakeListeningModeBackend = FakeListeningModeBackend(),
        attempts: Int = 16
    ) -> (BluetoothListeningModeController, FakeEndpointProvider) {
        // The production linger, not a shortened one. `.failed` is the only
        // state this suite asserts on that clears itself, and a test can only
        // see it by polling: at the 30 ms this helper used to pass, a runner
        // whose main actor resumes the poll loop less often than that never
        // looks inside the window at all, and the test fails on a product
        // behaviour that never changed. Two CI runs failed exactly that way
        // (`36681666541`, `36687697162`) before this was the reason.
        let hal = BluetoothListeningModeHAL(
            backend: backend,
            sleeper: ImmediateListeningModeSleeper(),
            retryAttempts: attempts,
            retryDelay: .milliseconds(1)
        )
        let provider = FakeEndpointProvider(endpoints: endpoints)
        let controller = BluetoothListeningModeController(
            hal: hal,
            endpointProvider: provider,
            failureClearDelay: Self.failureClearDelay
        )
        return (controller, provider)
    }

    /// The linger a failure stays published for. It is what the app uses, and the
    /// window a poll has to land inside, so the two cannot disagree.
    private static let failureClearDelay: Duration = .seconds(2)

    /// Polls the main actor until `condition` holds, so a spawned write task gets a
    /// chance to run and publish before the assertion. Fails if it never settles.
    ///
    /// The deadline is generous because the write it waits for runs on a spawned
    /// task: locally all of these settle in about a quarter of a second together,
    /// and a `macos-26` runner has taken several seconds for the same work. It is
    /// only a bound on a genuinely stuck write; what a state can be *seen* in is
    /// the linger above, not this.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("condition was not met within \(timeout)")
    }

    // MARK: - Resolution

    func testRefreshPublishesPresentationForResolvedEndpoint() {
        let (controller, _) = makeController(endpoints: [endpoint()])
        controller.refresh(devices: [device()])

        let presentation = controller.presentations[key]
        XCTAssertEqual(presentation?.availableModes, [.noiseCancellation, .transparency, .adaptive])
        XCTAssertEqual(presentation?.selectedMode, .noiseCancellation, "the current mode highlights")
        XCTAssertEqual(presentation?.actionState, .idle)
    }

    func testRefreshIgnoresDisconnectedAndNonAirPods() {
        let (controller, provider) = makeController(endpoints: [endpoint()])
        controller.refresh(devices: [device(connected: false), device(airPods: false)])

        XCTAssertTrue(controller.presentations.isEmpty, "nothing to control")
        XCTAssertEqual(provider.callCount, 0, "discovery runs only when there is an eligible device")
    }

    func testRefreshUsesConservativeFallbackWhenEndpointCarriesNoAddress() {
        // §6's accepted fallback path end-to-end: a single connected AirPods, a single
        // controllable endpoint that is the default output, no address evidence.
        let (controller, _) = makeController(endpoints: [endpoint(address: nil, isDefault: true)])
        controller.refresh(devices: [device()])
        XCTAssertNotNil(controller.presentations[key])
    }

    func testRefreshSkipsAmbiguousIdentityAndPublishesNothing() {
        // Two connected AirPods sharing no address evidence is ambiguous, so neither
        // resolves and no button appears — the safe outcome.
        let (controller, _) = makeController(endpoints: [endpoint(address: nil, isDefault: true)])
        let other = BluetoothDevice(
            id: "11:22:33:44:55:66",
            name: "Other AirPods",
            kind: .audio,
            isConnected: true
        )
        controller.refresh(devices: [device(), other])
        XCTAssertTrue(controller.presentations.isEmpty, "ambiguous identity fails closed")
    }

    func testRefreshDropsPresentationWhenDeviceGoesAway() async {
        let (controller, _) = makeController(endpoints: [endpoint()])
        controller.refresh(devices: [device()])
        XCTAssertNotNil(controller.presentations[key])

        controller.refresh(devices: [])
        XCTAssertTrue(controller.presentations.isEmpty)

        // The dropped address has no lingering presentation the next refresh could
        // accidentally resurrect from an old write's late completion.
        await waitUntil { controller.presentations.isEmpty }
    }

    // MARK: - Write: confirmed

    func testSetModePublishesChangingThenConfirms() async {
        // A scriptless backend stores the write, so the read-back settles on the target
        // and the controller reports it confirmed.
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2 // NC
        let (controller, _) = makeController(endpoints: [endpoint()], backend: backend)
        controller.refresh(devices: [device()])

        controller.setMode(.transparency, for: device())
        XCTAssertEqual(controller.presentations[key]?.actionState, .changing(to: .transparency))
        XCTAssertEqual(
            controller.presentations[key]?.selectedMode,
            .noiseCancellation,
            "the last confirmed selection stays visible while switching"
        )

        await waitUntil { controller.presentations[key]?.actionState == .idle }
        XCTAssertEqual(controller.presentations[key]?.selectedMode, .transparency)
        XCTAssertEqual(backend.writeCount, 1)
    }

    func testReTapOfSelectedModeWritesNothing() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 3 // already Transparency, and the capability highlights it
        let cap = capability(current: .transparency)
        let (controller, _) = makeController(
            endpoints: [endpoint(capability: cap)],
            backend: backend
        )
        controller.refresh(devices: [device()])
        XCTAssertEqual(controller.presentations[key]?.selectedMode, .transparency)

        controller.setMode(.transparency, for: device())

        XCTAssertEqual(controller.presentations[key]?.actionState, .idle, "a re-tap never starts a write")
        await waitUntil { backend.writeCount == 0 }
        XCTAssertEqual(backend.writeCount, 0)
    }

    func testRepeatTapWhileChangingDoesNotStackAWrite() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        backend.lstmReadScript = [2, 2, 2] // never confirms, so the first write lingers
        let (controller, _) = makeController(
            endpoints: [endpoint()],
            backend: backend,
            attempts: 4
        )
        controller.refresh(devices: [device()])

        controller.setMode(.transparency, for: device())
        XCTAssertEqual(controller.presentations[key]?.actionState, .changing(to: .transparency))
        // A second tap on a different mode while one is in flight is ignored.
        controller.setMode(.adaptive, for: device())
        XCTAssertEqual(
            controller.presentations[key]?.actionState,
            .changing(to: .transparency),
            "the in-flight request is not replaced mid-write"
        )
    }

    // MARK: - Write: unconfirmed / failed rollback

    func testUnconfirmedWriteRollsBackToObservedMode() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        backend.lstmReadScript = [2, 2, 2] // the setter accepted it but the device stays on NC
        let (controller, _) = makeController(
            endpoints: [endpoint()],
            backend: backend,
            attempts: 3
        )
        controller.refresh(devices: [device()])

        controller.setMode(.transparency, for: device())
        await waitUntil { self.isFailed(controller.presentations[key]?.actionState) }

        let presentation = controller.presentations[key]
        XCTAssertEqual(presentation?.selectedMode, .noiseCancellation, "rolls back to the observed mode")
        XCTAssertNotEqual(presentation?.selectedMode, .transparency, "never shows the mode that failed to land")
        XCTAssertTrue(isFailed(presentation?.actionState))

        // The failure then clears itself back to idle without changing the selection.
        await waitUntil { controller.presentations[key]?.actionState == .idle }
        XCTAssertEqual(controller.presentations[key]?.selectedMode, .noiseCancellation)
    }

    func testFailedWriteRollsBackThroughAReRead() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        backend.writeStatus = kAudioHardwareBadObjectError
        let (controller, _) = makeController(endpoints: [endpoint()], backend: backend)
        controller.refresh(devices: [device()])

        controller.setMode(.transparency, for: device())
        await waitUntil { self.isFailed(controller.presentations[key]?.actionState) }

        // The `.failed` path re-reads the live mode, which still reads NC.
        XCTAssertEqual(controller.presentations[key]?.selectedMode, .noiseCancellation)
        XCTAssertTrue(isFailed(controller.presentations[key]?.actionState))
    }

    // MARK: - Cancellation & teardown

    func testStopClearsSurfaceAndStopsPublishing() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        backend.lstmReadScript = [2, 2, 2]
        let (controller, _) = makeController(endpoints: [endpoint()], backend: backend, attempts: 8)
        controller.refresh(devices: [device()])
        controller.setMode(.transparency, for: device())

        controller.stop()
        XCTAssertTrue(controller.presentations.isEmpty)

        // A completion from the cancelled write cannot repopulate a cleared surface.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(controller.presentations.isEmpty)
    }

    func testDroppedAddressRejectsLateCompletion() async {
        // Start a write that will finish unconfirmed, then drop the device so the
        // write's generation is invalidated; its late apply must not republish.
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        backend.lstmReadScript = [2, 2, 2]
        let (controller, _) = makeController(endpoints: [endpoint()], backend: backend, attempts: 8)
        controller.refresh(devices: [device()])
        controller.setMode(.transparency, for: device())

        controller.refresh(devices: []) // supersede the write's generation

        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertNil(controller.presentations[key], "a stale completion is discarded")
    }

    func testDiscoveryRunsOncePerRefreshNotOnATimer() async {
        let (controller, provider) = makeController(endpoints: [endpoint()])
        controller.refresh(devices: [device()])
        XCTAssertEqual(provider.callCount, 1)

        // No background task re-reads it: left alone, the count never climbs.
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(provider.callCount, 1, "there is no polling")
    }

    private func isFailed(_ state: BluetoothListeningModeActionState?) -> Bool {
        if case .failed = state { return true }
        return false
    }
}
