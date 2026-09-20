# Wi-Fi Scan Cadence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the Wi-Fi network list from running a full all-channel `scanForNetworks` plus a `networksetup` subprocess on every ~5-second status yield, stop scanning when the user leaves the Wi-Fi page, and bound the no-interface recovery that rebuilds the whole CoreWLAN event stack every 30 seconds on Macs that have no Wi-Fi interface.

**Architecture:** Keep `WiFiNetworkController` as the owner of the scanned list and give it an injectable scan worker, an injected clock and a minimum scan interval, so the automatic path (`refresh(nameAccess:)`) reuses the cached list inside the interval while the explicit path (`refreshNow(nameAccess:)`) always scans. `SystemStatusStore` gains the symmetric `closeWiFiDetails()` that the Bluetooth and battery pages already have, and `WiFiMonitor` counts consecutive reads that report no interface at all and stops restarting its event stack after a bounded number of them.

**Tech Stack:** Swift 6 SwiftPM package (`swift-tools-version: 6.0`, macOS 15 deployment target), SwiftUI, AppKit, CoreWLAN, Network, XCTest and Swift Testing (`import Testing`).

**Spec:** Derived from the 2026-09-20 code review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3. The local machine is Xcode 27 / Swift 6.4 — a local build is NOT proof that CI compiles.
- Forbidden in this repo: `isolated deinit`, enabling the `IsolatedDeinit` experimental feature, `weak let` (use `weak var`), passing actor-isolated methods directly as function values (use an explicit closure), assuming `Bundle.module` resource/lproj casing.
- The app must build with the macOS 26 SDK or newer; `scripts/build-app.sh` enforces it and `scripts/verify-platform-version.sh` asserts the binary. Do not weaken either.
- Run `swift test` and `swift build -c release` before committing Swift changes.
- If a change touches actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources, a non-publishing release preflight is mandatory: `gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false` then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`.
- Any user-visible behavior change requires release notes added to the existing unreleased `release-notes/1.3.0/en.md` and `release-notes/1.3.0/zh-Hans.md`.
- Any change to menu bar icon rendering or icon settings must be mirrored in the Dock icon in the same change (SettingsStore option derivation, StatusBarController subscriptions, AppIconController subscriptions/state, `DockIconRenderKey` cache inputs, `DockIconRenderer` rendering, plus tests for both).
- Tests are mixed: most files use Swift Testing (`import Testing`, `@Test`, `#expect`, `@MainActor` suites), some use XCTest (`XCTAssert*`, `XCTSkipUnless`). Read the test file you extend and match its framework and style.

## Review Focus

- **A Mac mini or Mac Studio on Ethernet has no Wi-Fi interface, and every read reports `.unavailable`.** `WiFiMonitor.recoverIfAllowed(at:)` (`Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift:654-663`) fires every 30 seconds forever, rebuilding a `CWWiFiClient` (an XPC connection to `wifid`), re-registering six events and a new `NWPathMonitor` — about 2,880 times a day on hardware that will never have Wi-Fi. Pinned by `testInterfaceAbsentHostGivesUpRebuildingTheEventStackAfterTheLimit` in `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift`.
- **A user who backs out of the Wi-Fi page keeps a 30-second all-channel scan running for as long as the popover stays open.** `StatusPopoverView` sets `panel = .summary` without deactivating the controller (`Sources/StatusTrioCore/UI/StatusPopoverView.swift:288`), unlike the Bluetooth and battery pages at `:278-283` and `:298-301`. Pinned by `testLeavingTheWiFiPageStopsThePeriodicScan` in `Tests/StatusTrioCoreTests/WiFiNetworkScanCadenceTests.swift`.
- **Every Wi-Fi status yield arrives about every 5 seconds and after every CoreWLAN link-quality event.** `SystemStatusStore.applyWiFi(_:)` calls `wifiNetworks.refresh(nameAccess:)` for each one (`Sources/StatusTrioCore/Store/SystemStatusStore.swift:345-348`), and each call used to start a full scan. Pinned by `testStatusYieldsReuseTheCachedScanInsideTheInterval` and `testAutomaticRefreshScansAgainAfterTheInterval`.
- **A user who taps the refresh button, toggles the radio, or joins a network must see the change immediately.** Those three paths must bypass the interval, while keeping the single-flight guard so a scan that is already running is not duplicated. Pinned by `testManualRefreshBypassesTheInterval`, `testPowerToggleScansImmediately`, and `testAssociationScansImmediatelyAfterConnecting`.
- **A transient read failure on a Mac that does have Wi-Fi must keep recovering.** The new cap applies only to reads that report no interface at all, so the existing `testStaleReadFailureRecoversAndLaterSuccessRestoresState` (`Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:415-460`) keeps passing. Pinned by `testInterfaceAbsentStreakResetsWhenTheInterfaceComesBack`.

---

### Task 1: Inject The Scan Worker And Floor Automatic Scans

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/WiFiNetworkController.swift:58-68` (`WiFiScanPayload`, `WiFiScanWorkerResult`, `WiFiAssociationWorkerResult` become internal), `:79-93` (`CoreWLANNetworkWorker` conforms to a new protocol), `:367-425` (stored state, `init`, `activate`, `refresh`), `:621-634` (`schedulePeriodicRefresh`)
- Test: `Tests/StatusTrioCoreTests/WiFiNetworkScanCadenceTests.swift` (Create, XCTest — the Wi-Fi controller has no test file today, and its neighbours `WiFiClassifierTests` and `WirelessListModelsTests` both use `XCTestCase`, so this file matches them)

**Interfaces:**
- Consumes: `WiFiScanPayload`, `WiFiScanWorkerResult`, `WiFiAssociationWorkerResult` (`Sources/StatusTrioCore/Monitoring/WiFiNetworkController.swift:58-75`), `AsyncRequestGate` (`Sources/StatusTrioCore/Models/WiFiNetworkModels.swift:274-285`), the `now:` clock injection from `WiFiMonitor.init` (`Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift:334-350`) and the `periodicRefreshSleep` injection shape from `SystemStatusStore.init` (`Sources/StatusTrioCore/Store/SystemStatusStore.swift:41-59`).
- Produces: `protocol WiFiNetworkScanning: AnyObject` with `func scan(completion: @escaping @Sendable (WiFiScanWorkerResult) -> Void)`, `func setPower(_ isOn: Bool, completion: @escaping @Sendable (Bool) -> Void)`, `func associate(to network: WiFiNetwork, password: String?, completion: @escaping @Sendable (WiFiAssociationWorkerResult) -> Void)`; `CoreWLANNetworkWorker` conforms unchanged.
- Produces: `WiFiNetworkController.init(credentialStore:scanWorker:now:minimumScanInterval:periodicRefreshInterval:periodicRefreshSleep:)` with defaults `CoreWLANNetworkWorker()`, `Date.init`, `30`, `.seconds(30)` and `Task.sleep`, plus `func refresh(nameAccess:)` that reuses the cached list inside the interval and `func refreshNow(nameAccess:)` that always scans.

- [ ] **Step 1: Write the failing cadence tests**

Create `Tests/StatusTrioCoreTests/WiFiNetworkScanCadenceTests.swift`:

```swift
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

    /// The 30-second periodic loop is a floor, not a second cadence: with the
    /// injected sleeper it must ask for a scan no more often than the interval.
    func testThePeriodicLoopHonoursTheInterval() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let sleeper = ManualEventSleeper()
        let controller = makeController(
            scanner: scanner,
            clock: clock,
            periodicRefreshSleep: { _ in await sleeper.sleep() }
        )

        controller.activate(nameAccess: .authorized)
        await waitUntil { controller.state == .ready }
        await sleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertEqual(sleeper.durations.first, .seconds(30))

        sleeper.releaseAll()
        await Task.yield()
        XCTAssertEqual(scanner.scanCount, 1, "the loop fired inside the interval")

        clock.advance(by: 30)
        await sleeper.waitForCallCount(2, timeout: .seconds(1))
        sleeper.releaseAll()
        await waitUntil { scanner.scanCount == 2 }

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
```

`WiFiCredentialStoring` requires `resolveCredential(for:) -> WiFiCredentialResult` and `save(_:for:) -> Bool` (`Sources/StatusTrioCore/Monitoring/WiFiPasswordStore.swift:4-11`), which is what `InMemoryWiFiCredentialStore` implements; it is never asked for a credential because every fixture network is open (`WiFiSecurityKind.requiresPassword` is false at `Sources/StatusTrioCore/Models/WiFiNetworkModels.swift:29-31`).

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter WiFiNetworkScanCadenceTests`
Expected: compile failure — `cannot find 'WiFiNetworkScanning' in scope`, `extra arguments at positions #2, #3, #4, #5` for `WiFiNetworkController.init`.

- [ ] **Step 3: Promote the worker result types and add the scan protocol**

In `Sources/StatusTrioCore/Monitoring/WiFiNetworkController.swift`, remove `private` from `WiFiScanPayload` (`:58`), `WiFiScanWorkerResult` (`:63`) and `WiFiAssociationWorkerResult` (`:70`). They are file-private today, so nothing else can name them, and the injected scanner the tests need has to speak in those terms. Add the protocol above `CoreWLANNetworkWorker` (`:79`):

```swift
/// The scan, power and association calls the network list needs. CoreWLAN is
/// synchronous and serialized on the worker's own queue; the protocol exists so
/// a test can answer instantly and count the scans, which is how the cadence is
/// observable without sweeping every channel.
protocol WiFiNetworkScanning: AnyObject {
    func scan(completion: @escaping @Sendable (WiFiScanWorkerResult) -> Void)
    func setPower(_ isOn: Bool, completion: @escaping @Sendable (Bool) -> Void)
    func associate(
        to network: WiFiNetwork,
        password: String?,
        completion: @escaping @Sendable (WiFiAssociationWorkerResult) -> Void
    )
}
```

and make the existing worker conform by changing its declaration line (`:79`) to:

```swift
private final class CoreWLANNetworkWorker: @unchecked Sendable, WiFiNetworkScanning {
```

- [ ] **Step 4: Inject the worker, the clock and the interval**

In the same file, replace the stored properties and `init` (`:375-389`):

```swift
    private let worker: any WiFiNetworkScanning
    private let credentialWorker: WiFiCredentialWorker
    private let now: () -> Date
    /// A full scan sweeps every channel, so the automatic path may not run one
    /// more often than this. Explicit user actions bypass it.
    private let minimumScanInterval: TimeInterval
    private let periodicRefreshInterval: Duration
    private let periodicRefreshSleep: @Sendable (Duration) async throws -> Void
    private var scanGate = AsyncRequestGate()
    private var connectionGate = AsyncRequestGate()
    private var pendingNetwork: WiFiNetwork?
    private(set) var isActive = false
    /// When the last scan started, which is what the interval is measured from.
    private var lastScanStartedAt: Date?
    private var periodicRefreshTask: Task<Void, Never>?
    private var lastNameAccess: WiFiNameAccess = .notDetermined

    init(
        credentialStore: any WiFiCredentialStoring = KeychainWiFiPasswordStore(),
        scanWorker: any WiFiNetworkScanning = CoreWLANNetworkWorker(),
        now: @escaping () -> Date = Date.init,
        minimumScanInterval: TimeInterval = 30,
        periodicRefreshInterval: Duration = .seconds(30),
        periodicRefreshSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        credentialWorker = WiFiCredentialWorker(store: credentialStore)
        self.worker = scanWorker
        self.now = now
        self.minimumScanInterval = minimumScanInterval
        self.periodicRefreshInterval = periodicRefreshInterval
        self.periodicRefreshSleep = periodicRefreshSleep
    }
```

- [ ] **Step 5: Split the automatic path from the explicit one**

Replace `refresh(nameAccess:)` (`:413-425`) with the interval-aware version plus the explicit entry point:

```swift
    /// The automatic path: the periodic loop and every Wi-Fi status yield come
    /// through here. Inside the interval the cached list is kept, because the
    /// list only changes when the radio or the association changes, and those
    /// paths call `refreshNow(nameAccess:)`.
    func refresh(nameAccess: WiFiNameAccess? = nil) {
        if let nameAccess { lastNameAccess = nameAccess }
        guard hasScanElapsed else { return }
        startScan()
    }

    /// The explicit path: the refresh button, the radio toggle and a completed
    /// association. A user asked for this, so it scans even inside the interval.
    func refreshNow(nameAccess: WiFiNameAccess? = nil) {
        if let nameAccess { lastNameAccess = nameAccess }
        startScan()
    }

    private var hasScanElapsed: Bool {
        guard let lastScanStartedAt else { return true }
        return now().timeIntervalSince(lastScanStartedAt) >= minimumScanInterval
    }

    private func startScan() {
        guard isActive, !state.isScanning, !state.isConnectionFlow else { return }

        let request = scanGate.advance()
        lastScanStartedAt = now()
        state = .scanning
        worker.scan { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.scanGate.accepts(request), !self.state.isConnectionFlow else { return }
                self.receiveScanResult(result)
            }
        }
    }
```

- [ ] **Step 6: Use the injected sleeper in the periodic loop**

Replace `schedulePeriodicRefresh()` (`:621-634`):

```swift
    private func schedulePeriodicRefresh() {
        periodicRefreshTask?.cancel()
        let interval = periodicRefreshInterval
        let sleep = periodicRefreshSleep
        periodicRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard let self, self.isActive else { return }
                self.refresh()
            }
        }
    }
```

- [ ] **Step 7: Run the tests**

Run: `swift test --filter WiFiNetworkScanCadenceTests`
Run: `swift test --filter SystemStatusStoreTests`
Run: `swift test --filter WirelessListModelsTests`
Run: `swift test --filter WiFiClassifierTests`
Expected: PASS. `SystemStatusStoreTests.testReportsWhetherPopoverDetailsAreOpen` (`:68-100`) still drives `WiFiNetworkController()` with its default CoreWLAN worker; it only asserts `isActive`, which is set synchronously.

- [ ] **Step 8: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/WiFiNetworkController.swift \
        Tests/StatusTrioCoreTests/WiFiNetworkScanCadenceTests.swift
git commit -m "perf: floor Wi-Fi network scans and reuse the cached list"
```

---

### Task 2: Scan Immediately On Explicit User Actions

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/WiFiNetworkController.swift:426-445` (`setPower`), `:559-593` (`receiveAssociationResult`)
- Modify: `Sources/StatusTrioCore/UI/WiFiNetworkListView.swift:66` (manual refresh button)
- Test: `Tests/StatusTrioCoreTests/WiFiNetworkScanCadenceTests.swift` (XCTest, extend)

**Interfaces:**
- Consumes: `refreshNow(nameAccess:)` from Task 1.
- Produces: no new API; the manual button, the radio toggle and a completed association go through `refreshNow(nameAccess:)`.

- [ ] **Step 1: Write the failing explicit-action tests**

Add to `WiFiNetworkScanCadenceTests`:

```swift
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
```

`FakeWiFiNetworkScanner` already carries the knobs those tests use — `var associates`, `associateCount`, and an `associate` body that reports `.success(.unavailable)` when `associates` is true — because Task 1's Step 1 adds the complete fake.

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter WiFiNetworkScanCadenceTests`
Expected: two failures and no compile error. `testPowerToggleScansImmediately` times out waiting for the second scan (`Timed out waiting for the Wi-Fi network controller`) and `testAssociationScansImmediatelyAfterConnecting` does the same, because both paths still call the interval-aware `refresh()`. Task 1's `testManualRefreshBypassesTheInterval` already passes: it calls `refreshNow` directly, and this step is what puts the power and association paths on that same entry point.

- [ ] **Step 3: Route the power toggle through the explicit path**

In `Sources/StatusTrioCore/Monitoring/WiFiNetworkController.swift`, replace the `setPower` completion (`:434-444`):

```swift
        worker.setPower(enabled) { [weak self] changed in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                if changed {
                    self.state = .ready
                    self.refreshNow()
                } else {
                    self.state = .failed
                }
            }
        }
```

- [ ] **Step 4: Route a completed association through the explicit path**

In `receiveAssociationResult` (`:567-582`), replace the trailing `refresh()` in the `.success` case with `refreshNow()`:

```swift
        case let .success(connectionDetails):
            self.details = connectionDetails
            state = .ready
            pendingNetwork = nil
            credentialIssue = nil
            if rememberPassword, let suppliedPassword {
                credentialWorker.save(suppliedPassword, for: network.identity) { [weak self] saved in
                    Task { @MainActor [weak self] in
                        guard let self, self.connectionGate.accepts(request) else { return }
                        if !saved {
                            self.credentialIssue = .saveFailed
                        }
                    }
                }
            }
            refreshNow()
```

- [ ] **Step 5: Route the manual button through the explicit path**

In `Sources/StatusTrioCore/UI/WiFiNetworkListView.swift`, change the refresh button at `:66`:

```swift
            Button(action: { controller.refreshNow(nameAccess: wifi.nameAccess) }) {
                Image(systemName: "arrow.clockwise")
            }
```

The button's own closure is one line and has no test target; the behaviour behind it is what `testManualRefreshBypassesTheInterval` pins, and leaving the call on `refresh(nameAccess:)` would make the button do nothing for 30 seconds after the page opened.

- [ ] **Step 6: Run the tests**

Run: `swift test --filter WiFiNetworkScanCadenceTests`
Run: `swift test --filter SystemStatusStoreTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/WiFiNetworkController.swift \
        Sources/StatusTrioCore/UI/WiFiNetworkListView.swift \
        Tests/StatusTrioCoreTests/WiFiNetworkScanCadenceTests.swift
git commit -m "feat: rescan Wi-Fi immediately on explicit refresh, power and association"
```

---

### Task 3: Leaving The Wi-Fi Page Stops The Scan Loop

**Files:**
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift:302-311` (`activateWiFiPanel`, a new `closeWiFiDetails`)
- Modify: `Sources/StatusTrioCore/UI/StatusPopoverView.swift:284-293` (Wi-Fi page `onBack`)
- Test: `Tests/StatusTrioCoreTests/WiFiNetworkScanCadenceTests.swift` (XCTest, extend)

**Interfaces:**
- Consumes: `SystemStatusStore.activateWiFiPanel()` (`Sources/StatusTrioCore/Store/SystemStatusStore.swift:302-305`), `WiFiNetworkController.deactivate()` (`Sources/StatusTrioCore/Monitoring/WiFiNetworkController.swift:398-411`), `SystemStatusStore.hasOpenPopoverPanel` (`:317-319`).
- Produces: `SystemStatusStore.closeWiFiDetails()`; the Wi-Fi page's back row calls it before switching the panel, exactly as the battery and Bluetooth pages do at `Sources/StatusTrioCore/UI/StatusPopoverView.swift:278-283` and `:298-301`.

- [ ] **Step 1: Write the failing leave-the-page tests**

Add to `WiFiNetworkScanCadenceTests`:

```swift
    /// Backing out of the Wi-Fi page used to leave the controller active: the
    /// 30-second loop kept scanning while the popover stayed open.
    func testLeavingTheWiFiPageStopsThePeriodicScan() async {
        let scanner = FakeWiFiNetworkScanner()
        let clock = ManualScanClock()
        let sleeper = ManualEventSleeper()
        let networks = makeController(
            scanner: scanner,
            clock: clock,
            periodicRefreshSleep: { _ in await sleeper.sleep() }
        )
        let store = SystemStatusStore(
            batteryMonitor: CadenceBatteryMonitor(),
            wifiMonitor: CadenceWiFiMonitor(),
            volumeMonitor: CadenceVolumeMonitor(),
            wifiNetworks: networks
        )

        store.activateWiFiPanel()
        await waitUntil { scanner.scanCount == 1 }
        await sleeper.waitForCallCount(1, timeout: .seconds(1))
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
    /// `StatusBarController.popoverDidClose` takes at
    /// `Sources/StatusTrioCore/UI/StatusBarController.swift:422-431`.
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
```

Append the three store-level monitor fakes to the same file:

```swift
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
    func requestNameAccess() {}
}

@MainActor
private final class CadenceVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter WiFiNetworkScanCadenceTests`
Expected: compile failure — `value of type 'SystemStatusStore' has no member 'closeWiFiDetails'`.

- [ ] **Step 3: Add the store method**

In `Sources/StatusTrioCore/Store/SystemStatusStore.swift`, after `activateWiFiPanel()` (`:302-305`) add:

```swift
    /// Leaving the Wi-Fi page stops its scan loop. The page also holds a
    /// 30-second periodic scan and a `networksetup` subprocess per scan, and the
    /// popover can stay open on another page for a long time.
    func closeWiFiDetails() {
        wifiNetworks.deactivate()
    }
```

- [ ] **Step 4: Call it from the back row**

In `Sources/StatusTrioCore/UI/StatusPopoverView.swift`, change the Wi-Fi page's `onBack` (`:288`):

```swift
            case .wifi(let showDetails):
                WiFiNetworkListView(
                    controller: store.wifiNetworks,
                    wifi: store.popupSnapshot.wifi,
                    onBack: {
                        store.closeWiFiDetails()
                        panel = .summary
                    },
                    onRequestNameAccess: requestWiFiNameAccess,
                    onOpenWiFiSettings: openWiFiSettings,
                    onOpenLocationSettings: openLocationSettings,
                    showsDetailsInitially: showDetails
                )
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter WiFiNetworkScanCadenceTests`
Run: `swift test --filter SystemStatusStoreTests`
Run: `swift test --filter PopoverScrollTargetsTests`
Run: `swift test --filter SettingsRowHitAreaTests`
Expected: PASS. Both popover-hosting suites build the real `StatusPopoverView`, so a mistake in the closure's signature shows up there.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/Store/SystemStatusStore.swift \
        Sources/StatusTrioCore/UI/StatusPopoverView.swift \
        Tests/StatusTrioCoreTests/WiFiNetworkScanCadenceTests.swift
git commit -m "fix: stop the Wi-Fi scan loop when leaving the Wi-Fi page"
```

---

### Task 4: Bound The No-Interface Recovery

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift:314-333` (stored state), `:334-371` (`init`), `:391-399` (`recover`), `:486-492` (`receive`), `:654-663` (`recoverIfAllowed`)
- Test: `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:415-460` (XCTest, extend the existing monitor suite and its `makeMonitor` helper at `:1244-1281`)

**Interfaces:**
- Consumes: `WiFiStatusReading.interface` (`Sources/StatusTrioCore/Monitoring/WiFiStatusReader.swift:5-8`), where `nil` means CoreWLAN reported no interface at all; `WiFiMonitor.recoverIfAllowed(at:)` and its `staleInterval` gate (`Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift:654-663`).
- Produces: `WiFiMonitor.init(..., noInterfaceRecoveryLimit: Int = 3)` plus `var interfaceAbsentStreak: Int` (internal, read-only for tests); `recover()` resets the streak, the internal recovery path increments it and stops rebuilding once the limit is reached.

- [ ] **Step 1: Write the failing recovery-cap tests**

Add to `WiFiClassifierTests` (inside the existing `@MainActor final class WiFiClassifierTests: XCTestCase`), next to `testStaleReadFailureRecoversAndLaterSuccessRestoresState` (`:415`):

```swift
    /// A Mac with no Wi-Fi interface (a Mac mini or Mac Studio on Ethernet)
    /// reports `.unavailable` on every read. Recovery used to rebuild the whole
    /// CoreWLAN event stack every 30 seconds for the life of the process; it now
    /// gives up after a bounded number of attempts.
    func testInterfaceAbsentHostGivesUpRebuildingTheEventStackAfterTheLimit() async {
        let clock = ManualWiFiClock(now: Date(timeIntervalSinceReferenceDate: 4_000))
        let reader = FakeWiFiSystemReader(result: makeReading(mode: .station, rssi: -50))
        let eventMonitor = FakeWiFiEventMonitor()
        let pathMonitor = FakeWiFiPathMonitor()
        let monitor = makeMonitor(
            reader: reader,
            eventMonitor: eventMonitor,
            pathMonitor: pathMonitor,
            clock: clock
        )
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        XCTAssertEqual(eventMonitor.restartCount, 0)

        // The interface is gone: `FakeWiFiSystemReader(result: nil)` is exactly
        // what `CWWiFiClient.shared().interface()` returning nil looks like.
        reader.result = nil
        for _ in 0..<6 {
            clock.advance(by: 30.001)
            monitor.refresh()
            let status = await iterator.next()
            XCTAssertEqual(status, .placeholder)
        }

        XCTAssertEqual(eventMonitor.restartCount, 3, "recovery must stop at the limit")
        XCTAssertEqual(pathMonitor.cancelCount, 3)
        XCTAssertEqual(pathMonitor.startCount, 4, "one start plus three restarts")
        XCTAssertEqual(monitor.interfaceAbsentStreak, 6)
        monitor.stop()
    }

    /// A transient failure on a Mac that does have Wi-Fi is not the no-interface
    /// case, so it keeps retrying: the cap only counts reads that report no
    /// interface at all.
    func testInterfaceAbsentStreakResetsWhenTheInterfaceComesBack() async {
        let clock = ManualWiFiClock(now: Date(timeIntervalSinceReferenceDate: 4_500))
        let reader = FakeWiFiSystemReader(result: makeReading(mode: .station, rssi: -50))
        let eventMonitor = FakeWiFiEventMonitor()
        let monitor = makeMonitor(reader: reader, eventMonitor: eventMonitor, clock: clock)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        reader.result = nil
        clock.advance(by: 30.001)
        monitor.refresh()
        _ = await iterator.next()
        XCTAssertEqual(monitor.interfaceAbsentStreak, 1)
        XCTAssertEqual(eventMonitor.restartCount, 1)

        reader.result = makeReading(mode: .station, rssi: -58)
        monitor.refresh()
        let restored = await iterator.next()
        XCTAssertEqual(restored, WiFiStatus(state: .connected, rssi: -58))
        XCTAssertEqual(monitor.interfaceAbsentStreak, 0)

        // The next absence starts a fresh budget instead of inheriting the old one.
        reader.result = nil
        clock.advance(by: 30.001)
        monitor.refresh()
        _ = await iterator.next()
        XCTAssertEqual(eventMonitor.restartCount, 2)
        monitor.stop()
    }
```

Extend the file's `makeMonitor` helper (`:1244-1281`) with one parameter, added after `clock`:

```swift
        noInterfaceRecoveryLimit: Int = 3,
```

and insert the matching argument in its `WiFiMonitor(...)` call, between `refreshDebounceSleep:` and `readTimeout:`:

```swift
            noInterfaceRecoveryLimit: noInterfaceRecoveryLimit,
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter WiFiClassifierTests`
Expected: `testInterfaceAbsentHostGivesUpRebuildingTheEventStackAfterTheLimit` fails with `XCTAssertEqual failed: ("6") is not equal to ("3")` — every 30-second window still rebuilds the event stack — and the file fails to compile on `noInterfaceRecoveryLimit` and `interfaceAbsentStreak` until Step 3 lands.

- [ ] **Step 3: Count interface-absent reads and cap the recovery**

In `Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift`, add to the stored state next to `isPersistentReadFailure` (`:331`):

```swift
    /// Consecutive reads that reported no interface at all, which is what a Mac
    /// without Wi-Fi hardware returns on every read. Rebuilding the CoreWLAN
    /// event stack for those is pure waste, so the attempts are bounded.
    private(set) var interfaceAbsentStreak = 0
    private let noInterfaceRecoveryLimit: Int
```

add the parameter to `init` after `refreshDebounceSleep` (`:342-345`) and assign it in the body:

```swift
        noInterfaceRecoveryLimit: Int = 3,
```

```swift
        self.noInterfaceRecoveryLimit = noInterfaceRecoveryLimit
```

- [ ] **Step 4: Reset the streak in `receive`, and stop the recovery at the limit**

In `receive(_:)` (`:486-492`), replace the no-interface guard:

```swift
    private func receive(_ result: WiFiStatusReading) {
        guard let reading = result.interface else {
            interfaceAbsentStreak += 1
            publish(.unavailable, rssi: nil, ssid: nil, nameAccess: nameAuthorizer.access)
            return
        }

        interfaceAbsentStreak = 0
        lastRecoveryAttempt = nil
        isPersistentReadFailure = false
```

and replace `recoverIfAllowed(at:)` (`:654-663`):

```swift
    /// External triggers (a wake, an explicit `recover()`) start a fresh budget;
    /// the internal retry path is the one that is bounded.
    func recover() {
        guard lifecycle == .running else { return }
        interfaceAbsentStreak = 0
        restartMonitoring()
    }

    private func recoverIfAllowed(at date: Date) {
        guard interfaceAbsentStreak < noInterfaceRecoveryLimit else { return }
        if
            let lastRecoveryAttempt,
            date.timeIntervalSince(lastRecoveryAttempt) < staleInterval
        {
            return
        }

        restartMonitoring()
    }

    private func restartMonitoring() {
        readGeneration &+= 1
        lastRecoveryAttempt = now()
        eventMonitor.restart(delegate: self, events: Self.monitoredEvents)
        pathMonitor.cancel()
        startPathMonitoring()
    }
```

`recover()` keeps its public signature (`:391-399`) so `SystemStatusStore.recoverAll()` and `clientConnectionInvalidated()` at `:522-528` are unchanged; they now reset the budget, which is what makes a wake or a plug-in Wi-Fi adapter recoverable. The existing `testStaleReadFailureRecoversAndLaterSuccessRestoresState` needs only two recoveries, so the cap of three leaves it green.

- [ ] **Step 5: Run the tests**

Run: `swift test --filter WiFiClassifierTests`
Run: `swift test --filter WiFiNetworkScanCadenceTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift \
        Tests/StatusTrioCoreTests/WiFiClassifierTests.swift
git commit -m "fix: bound the no-interface Wi-Fi recovery attempts"
```

---

### Task 5: Verification, Release Notes And Preflight

**Files:**
- Modify: `release-notes/1.3.0/en.md` (append a section at the end)
- Modify: `release-notes/1.3.0/zh-Hans.md` (append the matching section at the end)

**Interfaces:**
- Consumes: every task above.
- Produces: no Swift API.

- [ ] **Step 1: Add the English release notes**

Append to `release-notes/1.3.0/en.md`:

```markdown
## Wi-Fi scanning stops when you stop looking
- The Wi-Fi page used to sweep every channel about every five seconds for as long as it was open, even after you went back to the summary. It now scans when you open the page, when you tap refresh, when you switch the radio, and when a connection finishes, and keeps the last result in between.
- Leaving the Wi-Fi page stops its scan loop instead of leaving it running in the background.
- On Macs without a Wi-Fi interface — a Mac mini or Mac Studio on Ethernet, for example — the app no longer rebuilds its Wi-Fi monitoring every 30 seconds; it now tries a few times and then waits for a wake or a network change.
- Nothing about the list itself changes: the same networks, the same details, and the same manual refresh button.
```

- [ ] **Step 2: Add the Chinese release notes**

Append to `release-notes/1.3.0/zh-Hans.md`:

```markdown
## 离开 Wi-Fi 页面后不再持续扫描
- Wi-Fi 页面此前在打开期间约每 5 秒扫描一次全部信道，返回摘要页后依然如此。现在只在打开页面、点按刷新、切换无线开关以及连接完成后扫描，其余时间沿用上一次的结果。
- 离开 Wi-Fi 页面会停止扫描循环，不再留在后台空转。
- 对于没有 Wi-Fi 网卡的 Mac（例如使用有线网络的 Mac mini 或 Mac Studio），App 不再每 30 秒重建一次 Wi-Fi 监控，而是尝试有限次数后等待唤醒或网络变化。
- 列表本身没有任何变化：同样的网络、同样的详情，手动刷新按钮也保持原样。
```

- [ ] **Step 3: Validate the release notes**

Run: `bash scripts/validate-appcast-notes.sh`
Expected: PASS — both files still start with a `# Version %VERSION% (Build %BUILD%)` / `# 版本 %VERSION%（构建 %BUILD%）` heading.

- [ ] **Step 4: Run the full acceptance sequence**

Run: `swift test`
Run: `swift build -c release`
Run: `git diff --check`
Run: `git status --short`
Expected: all tests pass, the release build succeeds, no whitespace errors, and only the files listed in this plan are modified.

- [ ] **Step 5: Measure, and record both numbers in the commit message**

> **⏳ Outstanding owner action** — the before/after CoreWLAN scan count is a merge gate and no commit on this branch carries it. The owner must either run it or explicitly waive it before merging. The procedure is the `pgrep -x networksetup` loop below: 12 samples 5 s apart with the Wi-Fi page open, then the same again after backing out to the summary. The dev bundle needs its own run, because the sampled process must be the build under test rather than the installed copy. No number is recorded here.

With the Wi-Fi page open for 60 seconds, count the CoreWLAN scans the build before the change and the build after it perform. The scan count is observable from the injected `FakeWiFiNetworkScanner` in tests and, on the running app, from the `networksetup` subprocesses each scan spawns:

```bash
for i in $(seq 1 12); do pgrep -x networksetup >/dev/null && echo "scan at $i"; sleep 5; done
```

Expected: no `networksetup` spawn inside the interval; about one per 30 seconds with the page open, and none after backing out to the summary.

- [ ] **Step 6: Run the non-publishing release preflight**

Run:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref perf/wifi-scan-cadence \
  -f version=1.3.0 \
  -f build=12 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: the workflow passes without publishing. This change touches `@MainActor` types, SwiftUI view closures and the async sleep injections, so the preflight is mandatory.

- [ ] **Step 7: Record the preflight**

Append the run ID and result to `docs/swift-ci-compatibility.md` if the run failed at any stage; a passing run needs no entry.

- [ ] **Step 8: Commit**

```bash
git add release-notes/1.3.0/en.md release-notes/1.3.0/zh-Hans.md
git commit -m "docs(release-notes): record the Wi-Fi scan cadence fix in 1.3.0"
```

---

## Verification

1. `swift test` — the whole suite passes, including the new `WiFiNetworkScanCadenceTests`, the extended `WiFiClassifierTests`, and the existing `SystemStatusStoreTests`, `WirelessListModelsTests`, `PopoverScrollTargetsTests` and `SettingsRowHitAreaTests`.
2. `swift build -c release` — succeeds.
3. `grep -rn "scanForNetworks" Sources/` — three hits, all inside `CoreWLANNetworkWorker` (`scanSynchronously` and `associateSynchronously`), none on the periodic or status-yield path.
4. `grep -rn "refresh(nameAccess:" Sources/` — the only call sites left are `SystemStatusStore`'s two automatic ones (`:289` on popover open and `:347` on a status yield); `grep -rn "refreshNow" Sources/` shows the definition plus the three explicit callers (the `WiFiNetworkListView` refresh button, `setPower`, `receiveAssociationResult`).
5. `bash scripts/validate-appcast-notes.sh` — passes with the two new release-note sections.
6. `git diff --check` and `git status --short` — no whitespace errors, only intended files touched.
7. Measurement from Task 5 Step 5 recorded in the final commit message.
8. `gh workflow run release.yml --repo lingyired/status-trio --ref perf/wifi-scan-cadence -f version=1.3.0 -f build=12 -f publish=false` followed by `gh run watch <run-id> --repo lingyired/status-trio --exit-status` — passes.

## Out of Scope

- Changing what the Wi-Fi list, the details section or the password sheet display, or their localization keys.
- Replacing `NetworksetupWiFiKnownNetworkProvider`'s `/usr/sbin/networksetup -listpreferredwirelessnetworks` call (`Sources/StatusTrioCore/Monitoring/WiFiKnownNetworkProvider.swift:39-65`) with a CoreWLAN or `SCPreferences` read: it runs inside the already-floored scan, so it is paid once per scan rather than once per status yield.
- The keychain hardening of `KeychainWiFiPasswordStore` and the deprecated Security APIs — that is R-12's plan.
- The main-actor CoreAudio work and the `deinit` thread affinity in `WiFiMonitor` — the `WiFiMonitor.swift` conflict with R-06 is split by function (this plan owns `recover`/`receive`/`recoverIfAllowed` only).
- The 5-second status poll cadence itself and the `SystemStatusStore` poll loop restructuring — that is R-03's plan. This plan only stops that poll from triggering scans.
- The status poll's `liveVolume` republishing and any battery-monitor change.

## File Ownership & Conflicts

| File | Other 2026-09-20 plans | Rule |
| --- | --- | --- |
| `Monitoring/WiFiNetworkController.swift` | R-12 (`2026-09-20-keychain-hardening.md` changes `WiFiPasswordStore.swift` and the credential path in this file) | Land R-12 first: it reworks the credential store and the two deprecated Security calls. This plan then only changes the scan worker, the clock and the interval, none of which R-12 touches. |
| `Monitoring/WiFiMonitor.swift` | R-06 (`2026-09-20-volume-monitor-main-actor-io.md` owns `deinit`/thread affinity) | Either order, never simultaneously. Split by function: this plan owns `recover()`, `receive(_:)` and `recoverIfAllowed(at:)`; R-06 owns `deinit` and the read/watchdog path. Review both diffs together. |
| `UI/StatusPopoverView.swift` | R-18 (`2026-09-20-toolchain-method-reference-compliance.md` changes the handler arguments this view receives) | **R-18 lands first.** It rewrites how the closures are passed at `Sources/StatusTrioCore/UI/StatusBarController.swift` and the `SettingsDisclosureRow` call sites; this plan then only edits the Wi-Fi `onBack` body at `:288`. |
| `UI/WiFiNetworkListView.swift` | R-13 (`2026-09-20-single-instance-and-pasteboard.md` touches the copy action in this view) | Land R-13 first; this plan changes only the header refresh button at `:66`. |
| `Store/SystemStatusStore.swift` | R-01 (`2026-09-20-bluetooth-polling-and-lifetime.md`), R-03 (`2026-09-20-status-poll-scheduling.md`) | **R-03 lands first, then R-01, then this plan.** This plan adds one method (`closeWiFiDetails()`) next to `activateWiFiPanel()`; R-01 edits `activateBluetoothForPopover()`, `setPopoverVisible(_:)` and `closePopoverDetails()` in the same region. |
| `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift` | R-20 (`2026-09-20-compiler-warning-cleanup.md` fixes a `weak var` warning in this file) | Land R-20 first (it is a warning-only change on a different line) or resolve the trivial conflict; this plan adds tests and one `makeMonitor` parameter. |
| `Tests/StatusTrioCoreTests/WiFiNetworkScanCadenceTests.swift` | none | New file, owned by this plan. |
| `release-notes/1.3.0/en.md`, `release-notes/1.3.0/zh-Hans.md` | R-01, R-09 (`2026-09-20-update-source-fallback-policy.md`), R-13 | Notes are append-only in this version; keep every section and re-run `bash scripts/validate-appcast-notes.sh`. |
| `docs/swift-ci-compatibility.md` | R-18 | Append-only record; add this plan's failed runs, if any, at the end. |

Recommended merge order: **R-03 → R-01 → R-12 → R-18 → R-20 → this plan (R-02)**, with R-06 free to land before or after as long as it is not concurrent with this plan's `WiFiMonitor.swift` edits. R-02 lands late because it is the plan that touches the most shared files, and every earlier plan's change to `StatusPopoverView`, `StatusBarController` and `SystemStatusStore` makes this plan's diff smaller rather than larger.
