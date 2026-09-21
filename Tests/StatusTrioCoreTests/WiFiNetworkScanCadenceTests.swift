import Foundation
import XCTest
@testable import StatusTrioCore

/// A full `scanForNetworks(withSSID: nil)` sweeps every channel, and it used to
/// run on every Wi-Fi status yield, which is about every five seconds. These
/// tests pin the interval that now floors the automatic path, the explicit path
/// that bypasses it, and the single flight that keeps a running scan from being
/// duplicated.
@MainActor
final class WiFiNetworkScanCadenceTests: XCTestCase {
    private func makeController(
        scanner: FakeWiFiNetworkScanner,
        clock: ManualScanClock = ManualScanClock(),
        minimumScanInterval: TimeInterval = 30,
        periodicRefreshSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) -> WiFiNetworkController {
        WiFiNetworkController(
            credentialStore: InMemoryWiFiCredentialStore(),
            scanWorker: scanner,
            now: { clock.now },
            minimumScanInterval: minimumScanInterval,
            periodicRefreshSleep: periodicRefreshSleep
        )
    }

    func testActivationScansOnce() async {
        let scanner = FakeWiFiNetworkScanner()
        let controller = makeController(scanner: scanner)

        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }

        XCTAssertEqual(scanner.scanCount, 1)
        XCTAssertEqual(controller.networks.map(\.ssid), ["Studio"])
        controller.deactivate()
    }

    /// The status-yield path: five yields inside the interval reuse the cached
    /// list instead of sweeping the channels five more times.
    func testStatusYieldsReuseTheCachedScanInsideTheInterval() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let controller = makeController(scanner: scanner, clock: clock)
        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }

        for _ in 0..<5 {
            clock.advance(by: 1)
            controller.refresh(nameAccess: .authorized)
        }
        await Task.yield()

        XCTAssertEqual(scanner.scanCount, 1)
        XCTAssertEqual(controller.networks.map(\.ssid), ["Studio"])
        controller.deactivate()
    }

    func testAutomaticRefreshScansAgainAfterTheInterval() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let controller = makeController(scanner: scanner, clock: clock)
        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }

        scanner.result = .success(WiFiScanPayload(
            networks: [makeScanNetwork("Guest", known: false)],
            details: .unavailable
        ))
        clock.advance(by: 29)
        controller.refresh(nameAccess: .authorized)
        await Task.yield()
        XCTAssertEqual(scanner.scanCount, 1, "inside the interval the cached list is reused")

        clock.advance(by: 1)
        controller.refresh(nameAccess: .authorized)
        await waitUntil { scanner.scanCount == 2 }
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(controller.networks.map(\.ssid), ["Guest"])
        controller.deactivate()
    }

    /// A scan that is still in flight must never be started twice.
    func testAScanInFlightIsNotDuplicated() async {
        let scanner = FakeWiFiNetworkScanner()
        scanner.holdsCompletions = true
        let clock = ManualScanClock()
        let controller = makeController(scanner: scanner, clock: clock)

        controller.activate(nameAccess: .authorized)
        clock.advance(by: 60)
        controller.refresh(nameAccess: .authorized)

        XCTAssertEqual(scanner.scanCount, 1)
        XCTAssertEqual(controller.state, .scanning)

        scanner.completeNext()
        await waitUntil { controller.state == .ready }
        controller.deactivate()
    }

    /// The refresh button asks for a scan now, even if one ran a moment ago.
    func testManualRefreshBypassesTheInterval() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let controller = makeController(scanner: scanner, clock: clock)
        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }

        scanner.result = .success(WiFiScanPayload(
            networks: [makeScanNetwork("Studio 5G")],
            details: .unavailable
        ))
        controller.refreshNow(nameAccess: .authorized)
        await waitUntil { scanner.scanCount == 2 }
        await waitUntil { controller.state == .ready }

        XCTAssertEqual(controller.networks.map(\.ssid), ["Studio 5G"])
        controller.deactivate()
    }

    /// Switching the radio is a user action: the list must not sit on the cached
    /// result from before the radio changed.
    func testPowerToggleScansImmediately() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let controller = makeController(scanner: scanner, clock: clock)
        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }

        controller.setPower(false)
        await waitUntil { scanner.scanCount == 2 }

        XCTAssertEqual(clock.now.timeIntervalSinceReferenceDate, 0, "the clock never moved")
        controller.deactivate()
    }

    /// The association finished, so the cached list is definitely out of date.
    func testAssociationScansImmediatelyAfterConnecting() async {
        let scanner = FakeWiFiNetworkScanner()
        scanner.associates = true
        let clock = ManualScanClock()
        let controller = makeController(scanner: scanner, clock: clock)
        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }

        controller.connect(to: makeScanNetwork("Studio"), password: nil, rememberPassword: false)
        await waitUntil { scanner.scanCount == 2 }

        XCTAssertEqual(scanner.associateCount, 1)
        XCTAssertEqual(clock.now.timeIntervalSinceReferenceDate, 0)
        controller.deactivate()
    }

    /// The 30-second periodic loop is a floor, not a second cadence: with the
    /// injected sleeper it must ask for a scan no more often than the interval.
    func testThePeriodicLoopHonoursTheInterval() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let sleeper = ManualEventSleeper()
        let controller = makeController(
            scanner: scanner,
            clock: clock,
            periodicRefreshSleep: { duration in await sleeper.sleep(duration) }
        )

        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }
        _ = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertEqual(sleeper.durations.first, .seconds(30))

        sleeper.releaseAll()
        await Task.yield()
        XCTAssertEqual(scanner.scanCount, 1, "the loop fired inside the interval")

        clock.advance(by: 30)
        _ = await sleeper.waitForCallCount(2, timeout: .seconds(1))
        sleeper.releaseAll()
        await waitUntil { scanner.scanCount == 2 }

        controller.deactivate()
    }

    /// A scan that is in flight when the page is left used to leave `state` on
    /// `.scanning` permanently: `deactivate()` drops the completion through the
    /// `isActive` guard, and every later `refresh`/`refreshNow` is then blocked
    /// by the `!state.isScanning` guard in `startScan()`, with the view's refresh
    /// button disabled. Leaving the session must end its scan state so that a
    /// later activation starts clean.
    func testReactivatingAfterLeavingMidScanStartsAFreshScan() async {
        let scanner = FakeWiFiNetworkScanner()
        scanner.holdsCompletions = true
        let clock = ManualScanClock()
        let controller = makeController(scanner: scanner, clock: clock)

        controller.activate(nameAccess: .authorized)
        await waitUntil { scanner.scanCount == 1 }
        XCTAssertEqual(controller.state, .scanning)

        controller.deactivate()
        XCTAssertFalse(controller.state.isScanning, "the abandoned scan must not stick")

        // The clock never moves: the fresh activation may only scan because the
        // floor timestamp was cleared with the scan state.
        scanner.holdsCompletions = false
        controller.activate(nameAccess: .authorized)
        await waitUntil { scanner.scanCount == 2 }
        await waitUntil { controller.state == .ready }

        XCTAssertFalse(controller.state.isScanning, "the page must not be stuck scanning")
        controller.deactivate()
    }

    /// Backing out of the Wi-Fi page used to leave the controller active: the
    /// 30-second loop kept scanning while the popover stayed open.
    func testLeavingTheWiFiPageStopsThePeriodicScan() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let sleeper = ManualEventSleeper()
        let networks = makeController(
            scanner: scanner,
            clock: clock,
            periodicRefreshSleep: { duration in await sleeper.sleep(duration) }
        )
        let store = SystemStatusStore(
            batteryMonitor: CadenceBatteryMonitor(),
            wifiMonitor: CadenceWiFiMonitor(),
            volumeMonitor: CadenceVolumeMonitor(),
            wifiNetworks: networks
        )

        store.activateWiFiPanel()
        await waitUntil { scanner.scanCount == 1 }
        _ = await sleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertTrue(store.hasOpenPopoverPanel)

        store.closeWiFiDetails()

        XCTAssertFalse(networks.isActive)
        XCTAssertFalse(store.hasOpenPopoverPanel)

        clock.advance(by: 60)
        sleeper.releaseAll()
        await Task.yield()
        XCTAssertEqual(scanner.scanCount, 1, "the page was left, so nothing may scan again")
    }

    /// Closing the popover releases the controller too, which is the path
    /// `StatusBarController.popoverDidClose` takes.
    func testClosingThePopoverDetailsStopsTheScan() async {
        let scanner = FakeWiFiNetworkScanner()
        let networks = makeController(scanner: scanner)
        let store = SystemStatusStore(
            batteryMonitor: CadenceBatteryMonitor(),
            wifiMonitor: CadenceWiFiMonitor(),
            volumeMonitor: CadenceVolumeMonitor(),
            wifiNetworks: networks
        )

        store.activateWiFiPanel()
        await waitUntil { scanner.scanCount == 1 }
        store.closePopoverDetails()

        XCTAssertFalse(networks.isActive)
        XCTAssertFalse(store.hasOpenPopoverPanel)
    }

    /// The refresh button used to stay enabled for the whole connection flow even
    /// though the controller ignored it. The button and the controller now share
    /// `allowsRefresh`, so this pins the controller half of that contract: while an
    /// association owns the controller, neither the automatic nor the explicit
    /// refresh path may start a scan.
    ///
    /// It lives in this file because the injectable scan worker lives here.
    func testRefreshIsIgnoredWhileAConnectionFlowIsInFlight() async {
        let scanner = FakeWiFiNetworkScanner()
        let controller = makeController(scanner: scanner)
        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }

        let network = makeScanNetwork("Studio")
        controller.connect(to: network, password: nil, rememberPassword: false)

        // `connect` enters the joining state synchronously; the fake worker hops
        // its completion onto the main actor, so it has not landed yet.
        XCTAssertEqual(controller.state, .connecting(network.identity))

        let scansBeforeTheGate = scanner.scanCount
        controller.refresh(nameAccess: .authorized)
        controller.refreshNow(nameAccess: .authorized)
        await Task.yield()

        XCTAssertEqual(
            scanner.scanCount,
            scansBeforeTheGate,
            "both refresh paths must be ignored while the connection flow is in flight"
        )
        XCTAssertEqual(scanner.associateCount, 1, "the gate must not block the association itself")

        controller.deactivate()
    }

    /// The gate has to be a block, not a latch: a join that ends without connecting
    /// must leave the list refreshable, or the user is stuck with a dead button.
    func testRefreshWorksAgainAfterAJoiningAttemptSettles() async {
        let scanner = FakeWiFiNetworkScanner()
        let controller = makeController(scanner: scanner)
        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }

        controller.connect(to: makeScanNetwork("Studio"), password: nil, rememberPassword: false)
        await waitUntil { controller.state == .networkUnavailable }

        let scansAfterTheFlow = scanner.scanCount
        controller.refreshNow(nameAccess: .authorized)
        await waitUntil { scanner.scanCount == scansAfterTheFlow + 1 }

        controller.deactivate()
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the Wi-Fi network controller")
    }
}

/// The network fixtures carry an open security so `connect(to:password:)` goes
/// straight to association instead of stopping at the password prompt.
private func makeScanNetwork(_ ssid: String, known: Bool = true) -> WiFiNetwork {
    WiFiNetwork(
        identity: WiFiNetworkIdentity(ssid: ssid, security: .open),
        candidates: [
            WiFiNetworkCandidate(ssid: ssid, bssid: nil, rssi: -50, channel: 6, security: .open)
        ],
        connectedBSSID: nil,
        isKnown: known
    )
}

/// Answers scans with one known network, and only when the test releases them if
/// `holdsCompletions` is set.
private final class FakeWiFiNetworkScanner: WiFiNetworkScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@Sendable (WiFiScanWorkerResult) -> Void] = []
    private var count = 0
    private var associations = 0

    var holdsCompletions = false
    /// True when the worker should report the association as completed.
    var associates = false
    var result: WiFiScanWorkerResult = .success(
        WiFiScanPayload(networks: [makeScanNetwork("Studio")], details: .unavailable)
    )

    var scanCount: Int { lock.withLock { count } }
    var associateCount: Int { lock.withLock { associations } }

    func scan(completion: @escaping @Sendable (WiFiScanWorkerResult) -> Void) {
        let result = lock.withLock { () -> WiFiScanWorkerResult in
            count += 1
            return self.result
        }
        if holdsCompletions {
            lock.withLock { pending.append(completion) }
        } else {
            completion(result)
        }
    }

    func completeNext() {
        let completion = lock.withLock { pending.isEmpty ? nil : pending.removeFirst() }
        let result = lock.withLock { self.result }
        completion?(result)
    }

    /// Reports the radio change as applied, which is what `setPower` returning
    /// true means, so the controller takes its "changed" path.
    func setPower(_ isOn: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        completion(true)
    }

    func associate(
        to network: WiFiNetwork,
        password: String?,
        completion: @escaping @Sendable (WiFiAssociationWorkerResult) -> Void
    ) {
        lock.withLock { associations += 1 }
        completion(associates ? .success(.unavailable) : .networkUnavailable)
    }
}

private final class ManualScanClock {
    private(set) var now = Date(timeIntervalSinceReferenceDate: 0)

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

/// The credential store is only reached for a password-protected network, and
/// every security used by this file is open, so the answers are never read.
private final class InMemoryWiFiCredentialStore: WiFiCredentialStoring, @unchecked Sendable {
    func resolveCredential(for identity: WiFiNetworkIdentity) -> WiFiCredentialResult {
        .noCredential
    }

    func save(_ password: String, for identity: WiFiNetworkIdentity) -> Bool {
        false
    }
}

// The store-level tests only exercise the Wi-Fi panel's lifetime, so the three
// status monitors are inert: they publish nothing and never touch the system.

@MainActor
private final class CadenceBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class CadenceWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class CadenceVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
