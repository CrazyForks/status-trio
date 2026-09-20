# Bluetooth Polling And Lifetime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the unconditional 15-second `system_profiler` poll, drive Bluetooth device state from connect/disconnect notifications with a debounce, read paired devices and battery levels from a single profiler report, and make the controller release its observers and CoreBluetooth state when it is deallocated without `deactivate()`.

**Architecture:** Keep `BluetoothDeviceController` as the single owner of Bluetooth state and keep the existing event-driven shape. Add three small, injectable collaborators — a timestamped report cache shared by the two profiler workers, a nonisolated connection-event monitor backed by `IOBluetoothDevice` notifications, and a teardown-owned observer bag — then gate the safety-net poll and the connection-event registration on a counted "visible surface" claim so the popover's lifetime bounds the work.

**Tech Stack:** Swift 6 SwiftPM package (`swift-tools-version: 6.0`, macOS 15 deployment target), SwiftUI, AppKit, CoreBluetooth, IOBluetooth, XCTest and Swift Testing (`import Testing`).

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

- **A user who denied Bluetooth must never see a permission prompt because the popover opened.** `BluetoothPanelActivation.shouldActivate` (`Sources/StatusTrioCore/Models/WiFiNetworkModels.swift:440-446`) stays the only gate for starting `CoreBluetoothStateMonitor`; the new surface claim must not start it. Pinned by `testHoldingASurfaceDoesNotStartTheStateMonitor` in `Tests/StatusTrioCoreTests/BluetoothPermissionTimingTests.swift`.
- **A user with the grant who opens and closes the popover must stop paying for polling.** After `setPopoverVisible(false)` the 15-second profiler loop must be cancelled while the already-running CoreBluetooth state monitor stays up (the existing `testEnabledBluetoothMonitorSurvivesPopupClose` and `testOpeningThePopoverActivatesBluetoothWhenAlreadyAuthorized` in `Tests/StatusTrioCoreTests/BluetoothPermissionTimingTests.swift:67-119` pin the monitor half). Pinned by `testClosingThePopoverStopsTheSafetyNetPoll` in `Tests/StatusTrioCoreTests/BluetoothPollingLifetimeTests.swift`.
- **A profiler read that is superseded must not wedge the controller.** When the adapter powers off while a read is in flight, the discarded completion must still release the in-flight latch, or every later refresh is coalesced into a follow-up that never starts. Pinned by `testSupersededReadReleasesTheLatchAndTheNextRefreshRuns`.
- **Battery levels claimed by the summary row must not spawn a second `system_profiler`.** The level read happens right after the device read inside one `refresh()`, so it has to reuse that report; a report older than the freshness window must still spawn. Pinned by `testBatteryReadReusesTheDeviceReportWithoutSpawningAgain` and `testBatteryReadSpawnsWhenTheSharedReportIsStale` in `Tests/StatusTrioCoreTests/BluetoothBatteryReaderTests.swift`.
- **A controller released without `deactivate()` must not leak observers or leave CoreBluetooth running.** `CBCentralManager` retains its delegate, so `CoreBluetoothStateMonitor` is never deallocated unless `stop()` runs. Pinned by `testDeinitWithoutDeactivateRemovesObserversAndStopsTheStateMonitor` and `testDeinitWithoutDeactivateStopsTheConnectionEventMonitor`.

---

### Task 1: Share One `system_profiler` Report

**Files:**
- Create: `Sources/StatusTrioCore/Monitoring/BluetoothProfilerReportCache.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift:33-73` (`SystemProfilerBluetoothPairedDeviceWorker`)
- Modify: `Sources/StatusTrioCore/Monitoring/BluetoothBatteryReader.swift:99-130` (`SystemProfilerBluetoothBatteryWorker`)
- Test: `Tests/StatusTrioCoreTests/BluetoothBatteryReaderTests.swift` (Swift Testing — this file uses `import Testing`, `@Test`, `#expect`; keep that framework)

**Interfaces:**
- Consumes: `BluetoothPairedDeviceReader.parse(json:) -> [BluetoothDevice]?` (`Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift:79-119`) and `BluetoothBatteryReader.parse(json:) -> [String: BluetoothBatteryLevel]` (`Sources/StatusTrioCore/Monitoring/BluetoothBatteryReader.swift:39-72`), both unchanged.
- Produces: `final class BluetoothProfilerReportCache: @unchecked Sendable` with `static let shared`, `static let defaultMaxAge: TimeInterval = 5`, `func store(_ data: Data, at date: Date = Date())`, `func freshData(maxAge: TimeInterval = BluetoothProfilerReportCache.defaultMaxAge, now: Date = Date()) -> Data?`.
- Produces: `SystemProfilerBluetoothPairedDeviceWorker.init(outputProvider:reportCache:)` and `SystemProfilerBluetoothBatteryWorker.init(outputProvider:reportCache:)`; both keep the existing trailing-closure call shape `SystemProfilerBluetoothPairedDeviceWorker { data }` used at `Tests/StatusTrioCoreTests/BluetoothPairedDeviceListTests.swift:109` and `:125`.

- [ ] **Step 1: Write the failing shared-report tests**

Append to `Tests/StatusTrioCoreTests/BluetoothBatteryReaderTests.swift`, inside the existing `struct BluetoothBatteryReaderTests` (before its closing brace), a private fixture and two tests. The fixture is one real `SPBluetoothDataType` report that carries both a device entry and a battery level:

```swift
    private let sharedReport = """
    {
      "SPBluetoothDataType": [
        {
          "device_connected": [
            {
              "AirPods Pro": {
                "device_address": "AC:90:85:C2:9C:1F",
                "device_minorType": "Headphones",
                "device_batteryLevelMain": "95%"
              }
            }
          ],
          "device_not_connected": []
        }
      ]
    }
    """

    /// One refresh reads the paired devices and then the battery levels. Both
    /// parse the same JSON, so the second read must reuse the first report
    /// instead of running `/usr/sbin/system_profiler` again.
    @Test func batteryReadReusesTheDeviceReportWithoutSpawningAgain() async {
        let reportCache = BluetoothProfilerReportCache()
        let data = Data(sharedReport.utf8)
        let deviceWorker = SystemProfilerBluetoothPairedDeviceWorker(
            outputProvider: { data },
            reportCache: reportCache
        )
        let spawnCount = ProfilerSpawnCounter()
        let batteryWorker = SystemProfilerBluetoothBatteryWorker(
            outputProvider: {
                spawnCount.increment()
                return nil
            },
            reportCache: reportCache
        )

        let devices = DeviceResultBox()
        deviceWorker.read { devices.set($0) }
        await waitUntil { devices.value != nil }

        let levels = BatteryLevelResultBox()
        batteryWorker.read { levels.set($0) }
        await waitUntil { levels.value != nil }

        #expect(spawnCount.value == 0, "the battery read spawned a second profiler")
        #expect(levels.value?[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")]?.main == 95)
    }

    /// A battery read that happens on its own has no fresh report to reuse, so
    /// it still asks the system for one and keeps that answer for the next read.
    @Test func batteryReadSpawnsWhenTheSharedReportIsStale() async {
        let reportCache = BluetoothProfilerReportCache()
        let stale = Data("""
        {"SPBluetoothDataType": [{"device_connected": [], "device_not_connected": []}]}
        """.utf8)
        reportCache.store(stale, at: Date().addingTimeInterval(-60))

        let spawnCount = ProfilerSpawnCounter()
        let data = Data(sharedReport.utf8)
        let batteryWorker = SystemProfilerBluetoothBatteryWorker(
            outputProvider: {
                spawnCount.increment()
                return data
            },
            reportCache: reportCache
        )

        let levels = BatteryLevelResultBox()
        batteryWorker.read { levels.set($0) }
        await waitUntil { levels.value != nil }

        #expect(spawnCount.value == 1)
        #expect(levels.value?[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")]?.main == 95)
    }
```

Add these private helpers at the end of the same file, next to the existing `BluetoothBatteryReaderTests` struct:

```swift
/// The workers answer on their own serial queues, so the tests collect results
/// and call counts behind a lock.
private final class ProfilerSpawnCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class DeviceResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: BluetoothWorkerResult?

    var value: BluetoothWorkerResult? { lock.withLock { stored } }
    func set(_ result: BluetoothWorkerResult) { lock.withLock { stored = result } }
}

private final class BatteryLevelResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: BluetoothBatteryLevel]?

    var value: [String: BluetoothBatteryLevel]? { lock.withLock { stored } }
    func set(_ levels: [String: BluetoothBatteryLevel]) { lock.withLock { stored = levels } }
}
```

`BluetoothBatteryReaderTests` has no `waitUntil` yet; add this helper inside the struct, copied from the same-named helper at `Tests/StatusTrioCoreTests/BluetoothPairedDeviceListTests.swift:137-143`:

```swift
    /// The readers answer on their own serial queues.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for the profiler read")
    }
```

- [ ] **Step 2: Run the new tests and verify RED**

Run: `swift test --filter BluetoothBatteryReaderTests`
Expected: compile failure — `cannot find 'BluetoothProfilerReportCache' in scope` and `extra arguments at positions #2` for both workers.

- [ ] **Step 3: Create the report cache**

Create `Sources/StatusTrioCore/Monitoring/BluetoothProfilerReportCache.swift`:

```swift
import Foundation

/// One `system_profiler -json SPBluetoothDataType` run feeds both the paired
/// device list and the battery levels: both parsers read the same JSON, so a
/// second process would only repeat work the first one already did. The device
/// worker fills the cache, the battery worker reads it, and neither owns the
/// other, so the app shares a single instance.
final class BluetoothProfilerReportCache: @unchecked Sendable {
    static let shared = BluetoothProfilerReportCache()

    /// A report older than this is treated as absent, so a battery read that
    /// happens on its own still asks the system for current data instead of
    /// reusing a level that may already be stale.
    static let defaultMaxAge: TimeInterval = 5

    private let lock = NSLock()
    private var entry: (data: Data, storedAt: Date)?

    func store(_ data: Data, at date: Date = Date()) {
        lock.withLock { entry = (data, date) }
    }

    func freshData(
        maxAge: TimeInterval = BluetoothProfilerReportCache.defaultMaxAge,
        now: Date = Date()
    ) -> Data? {
        lock.withLock {
            guard let entry, now.timeIntervalSince(entry.storedAt) < maxAge else { return nil }
            return entry.data
        }
    }
}
```

- [ ] **Step 4: Make the device worker publish its report**

In `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`, replace `SystemProfilerBluetoothPairedDeviceWorker` (`:33-73`) with:

```swift
final class SystemProfilerBluetoothPairedDeviceWorker: @unchecked Sendable, BluetoothPairedDeviceReading {
    typealias OutputProvider = @Sendable () -> Data?
    private let queue = DispatchQueue(label: "StatusTrio.SystemProfilerBluetoothPairedDeviceWorker")
    private let outputProvider: OutputProvider
    private let reportCache: BluetoothProfilerReportCache

    init(
        outputProvider: @escaping OutputProvider = SystemProfilerBluetoothPairedDeviceWorker.readSystemProfilerOutput,
        reportCache: BluetoothProfilerReportCache = .shared
    ) {
        self.outputProvider = outputProvider
        self.reportCache = reportCache
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        queue.async {
            guard let data = self.outputProvider(),
                  let devices = BluetoothPairedDeviceReader.parse(json: data) else {
                completion(.failed)
                return
            }
            // The battery reader reuses these exact bytes instead of spawning a
            // second profiler moments later.
            self.reportCache.store(data)
            completion(.success(devices))
        }
    }

    static func readSystemProfilerOutput() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPBluetoothDataType"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }
}
```

Keep the doc comment that sits above the type at `:25-32` exactly as it is.

- [ ] **Step 5: Make the battery worker reuse that report**

In `Sources/StatusTrioCore/Monitoring/BluetoothBatteryReader.swift`, replace `SystemProfilerBluetoothBatteryWorker` (`:99-130`) with:

```swift
final class SystemProfilerBluetoothBatteryWorker: @unchecked Sendable, BluetoothBatteryReading {
    typealias OutputProvider = @Sendable () -> Data?
    private let queue = DispatchQueue(label: "StatusTrio.SystemProfilerBluetoothBatteryWorker")
    private let outputProvider: OutputProvider
    private let reportCache: BluetoothProfilerReportCache

    init(
        outputProvider: @escaping OutputProvider = SystemProfilerBluetoothBatteryWorker.readSystemProfilerOutput,
        reportCache: BluetoothProfilerReportCache = .shared
    ) {
        self.outputProvider = outputProvider
        self.reportCache = reportCache
    }

    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]) -> Void) {
        queue.async {
            guard let data = self.reportCache.freshData() ?? self.outputProvider() else {
                completion([:])
                return
            }
            self.reportCache.store(data)
            completion(BluetoothBatteryReader.parse(json: data))
        }
    }

    static func readSystemProfilerOutput() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPBluetoothDataType"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter BluetoothBatteryReaderTests`
Run: `swift test --filter BluetoothPairedDeviceListTests`
Expected: PASS. The trailing-closure call sites at `BluetoothPairedDeviceListTests.swift:109` and `:125` still compile because `reportCache` is not a function type.

- [ ] **Step 7: Confirm no other profiler spawn remains**

Run: `grep -rn "system_profiler" Sources/`
Expected: exactly four hits — the `executableURL` and `arguments` lines of each of the two `readSystemProfilerOutput()` methods (`Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift` and `Sources/StatusTrioCore/Monitoring/BluetoothBatteryReader.swift`) — and no other spawn site.

- [ ] **Step 8: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/BluetoothProfilerReportCache.swift \
        Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift \
        Sources/StatusTrioCore/Monitoring/BluetoothBatteryReader.swift \
        Tests/StatusTrioCoreTests/BluetoothBatteryReaderTests.swift
git commit -m "perf: read paired devices and battery levels from one profiler report"
```

---

### Task 2: Latch Device Reads And Coalesce A Pending Refresh

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift:239-245` (stored state), `:300-311` (`deactivate`), `:313-338` (`refresh`), `:384-403` (`receiveSystemState`)
- Test: `Tests/StatusTrioCoreTests/BluetoothPollingLifetimeTests.swift` (Create, XCTest — this file uses `XCTestCase`, `XCTAssert*`, `@MainActor`, matching the neighbouring Bluetooth test files)

**Interfaces:**
- Consumes: `AsyncRequestGate` (`Sources/StatusTrioCore/Models/WiFiNetworkModels.swift:274-285`) and the single-read latch shape from `WiFiMonitor.refresh()` (`Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift:440-473`).
- Produces: `BluetoothDeviceController.refresh()` runs at most one `worker.read` at a time and keeps at most one follow-up; no new public API.

- [ ] **Step 1: Write the failing latch tests**

Create `Tests/StatusTrioCoreTests/BluetoothPollingLifetimeTests.swift`:

```swift
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
        stateMonitor: AvailableBluetoothStateMonitor = AvailableBluetoothStateMonitor()
    ) -> BluetoothDeviceController {
        BluetoothDeviceController(
            worker: reader,
            stateMonitor: stateMonitor,
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
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

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the Bluetooth controller")
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
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter BluetoothPollingLifetimeTests`
Expected: the file compiles and `testReadsCoalesceIntoOneFollowUpWhileAReadIsInFlight` fails on `XCTAssertEqual(reader.readCount, 1, "extra triggers must not start extra reads")`, because today each `refresh()` starts its own read (the assertion sees 4). `testSupersededReadReleasesTheLatchAndTheNextRefreshRuns` also fails: the superseded completion still reaches `requestGate.accepts` as an accepted request in the current code path and republishes the devices it carried.

- [ ] **Step 3: Add the latch state and the invalidation helper**

In `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`, replace the stored properties at `:239-245` with:

```swift
    private(set) var isActive = false
    private var requestGate = AsyncRequestGate()
    private var batteryRequestGate = AsyncRequestGate()
    /// One device read at a time, with at most one coalesced follow-up. Without
    /// this, every trigger started its own `/usr/sbin/system_profiler` process.
    private var isDeviceReadInFlight = false
    private var isRefreshPending = false
    private var batteryLevelsEnabled = false
    private var periodicRefreshTask: Task<Void, Never>?
    private var applicationObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
```

- [ ] **Step 4: Replace `refresh()` with the latched version**

Replace `refresh()` (`:313-338`) with:

```swift
    func refresh() {
        guard isActive, availability == .available else { return }
        // Coalesce bursts: at most one read and one follow-up are retained,
        // whatever order the triggers arrive in.
        guard !isDeviceReadInFlight else {
            isRefreshPending = true
            return
        }
        isDeviceReadInFlight = true
        let request = requestGate.advance()
        worker.read { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.requestGate.accepts(request) else { return }
                self.isDeviceReadInFlight = false
                guard self.isActive else { return }
                switch result {
                case let .success(devices):
                    self.devices = devices
                    self.availability = .available
                    self.refreshBatteryLevels()
                case .poweredOff:
                    self.availability = .poweredOff
                    self.clearBatteryLevels()
                    self.stopPeriodicRefresh()
                case .unavailable:
                    self.availability = .unavailable
                    self.clearBatteryLevels()
                    self.stopPeriodicRefresh()
                case .failed:
                    self.availability = .failed
                    self.clearBatteryLevels()
                }
                if self.isRefreshPending {
                    self.isRefreshPending = false
                    self.refresh()
                }
            }
        }
    }

    /// Invalidates any in-flight device read. The completion that belongs to the
    /// invalidated read is discarded, so the latch has to be released here or no
    /// later refresh could ever start.
    private func invalidateDeviceRead() {
        _ = requestGate.advance()
        isDeviceReadInFlight = false
        isRefreshPending = false
    }
```

- [ ] **Step 5: Route the invalidation sites through the helper**

In `deactivate()` (`:300-311`) replace `_ = requestGate.advance()` with `invalidateDeviceRead()`. In `receiveSystemState` (`:384-403`) replace the `_ = requestGate.advance()` in the non-available branch with `invalidateDeviceRead()`. Both become:

```swift
    func deactivate() {
        guard isActive else { return }
        isActive = false
        invalidateDeviceRead()
        batteryLevelRequests.removeAll()
        updateBatteryLevelRequests()
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        removeSystemObservers()
        stateMonitor.stop()
        availability = .idle
    }
```

```swift
        if mappedAvailability == .available {
            schedulePeriodicRefresh()
            refresh()
        } else {
            invalidateDeviceRead()
            clearBatteryLevels()
            stopPeriodicRefresh()
        }
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter BluetoothPollingLifetimeTests`
Run: `swift test --filter WirelessListModelsTests/testBluetoothControllerRefreshesPairedDevicesAcrossStateAndPanelLifecycle`
Run: `swift test --filter BluetoothBatteryControllerTests`
Expected: PASS. The lifecycle test at `Tests/StatusTrioCoreTests/WirelessListModelsTests.swift:272-347` still sees one, two and three reads because the stub completes synchronously.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift \
        Tests/StatusTrioCoreTests/BluetoothPollingLifetimeTests.swift
git commit -m "fix: latch Bluetooth device reads and coalesce one pending refresh"
```

---

### Task 3: Poll Only While A Bluetooth Surface Is Visible

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift:465-478` (`schedulePeriodicRefresh`), `:480-483` (`stopPeriodicRefresh`), `:293-298` (`activate`)
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift:240-245` (`closeBluetoothDetails`), `:252-257` (`activateBluetoothForPopover`), `:272-290` (`setPopoverVisible`), `:307-311` (`closePopoverDetails`)
- Modify: `Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift:42-52` (summary row claims) and `:174-183` (detail page claims)
- Test: `Tests/StatusTrioCoreTests/BluetoothPollingLifetimeTests.swift` (XCTest)
- Test: `Tests/StatusTrioCoreTests/BluetoothPermissionTimingTests.swift:67-119` (XCTest, extend)

**Interfaces:**
- Consumes: `AsyncRequestGate`-style token counting already used for battery claims at `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift:340-363`.
- Produces: `BluetoothDeviceController.holdVisibleSurface(_ token: String)`, `releaseVisibleSurface(_ token: String)`, `hasVisibleSurface: Bool`, `isSafetyNetPolling: Bool`, `init(..., safetyNetInterval: Duration = .seconds(30), safetyNetSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) })`.
- Produces: `SystemStatusStore.setPopoverVisible(_:)` holds and releases the `"bluetooth.popover"` surface and `activateBluetoothForPopover()` asks for one read on open.

- [ ] **Step 1: Write the failing surface-gate tests**

First extend the helper in `BluetoothPollingLifetimeTests` so the safety-net sleep can be driven by hand (`ManualEventSleeper` already exists at `Tests/StatusTrioCoreTests/ManualEventSleeper.swift`):

```swift
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
```

Then add to `BluetoothPollingLifetimeTests`:

```swift
    /// The safety net is a fallback for the connection notifications, and it may
    /// only run while something on screen shows device state.
    func testSafetyNetPollRunsOnlyWhileASurfaceIsHeld() async {
        let reader = DeferredBluetoothDeviceReader()
        let sleeper = ManualEventSleeper()
        let controller = makeController(
            reader: reader,
            safetyNetSleep: { _ in await sleeper.sleep() }
        )
        controller.activate()
        await waitUntil { reader.readCount == 1 }
        reader.complete(.success([]))
        await waitUntil { !reader.hasPendingRead }

        XCTAssertFalse(controller.isSafetyNetPolling, "a poll started with nothing on screen")

        controller.holdVisibleSurface("bluetooth.summary")
        await sleeper.waitForCallCount(1, timeout: .seconds(1))
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
            safetyNetSleep: { _ in await sleeper.sleep() }
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
            safetyNetSleep: { _ in await sleeper.sleep() }
        )
        controller.activate()
        controller.holdVisibleSurface("bluetooth.summary")
        XCTAssertTrue(controller.isSafetyNetPolling)

        controller.deactivate()
        XCTAssertTrue(controller.hasVisibleSurface)
        XCTAssertFalse(controller.isSafetyNetPolling)
    }
```

Add to `BluetoothPermissionTimingTests` (XCTest), as a new test next to `testOpeningThePopoverKeepsUnauthorizedBluetoothIdle` (`:123-149`):

```swift
    /// Holding a surface only allows polling; it never starts the state monitor,
    /// so the row cannot raise the permission prompt on its own.
    func testHoldingASurfaceDoesNotStartTheStateMonitor() {
        let stateMonitor = BluetoothStateMonitorSpy(authorization: .notDetermined)
        let bluetoothController = BluetoothDeviceController(
            stateMonitor: stateMonitor,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        bluetoothController.holdVisibleSurface("bluetooth.summary")

        XCTAssertEqual(stateMonitor.startCount, 0)
        XCTAssertFalse(bluetoothController.isActive)
        XCTAssertFalse(bluetoothController.isSafetyNetPolling)
    }

    /// The popover is what holds the Bluetooth surface, and closing it must stop
    /// the poll while the already-running state monitor stays warm: the summary
    /// row still reports device state the next time it opens, and starting the
    /// monitor is what raises the permission prompt.
    func testClosingThePopoverStopsTheSafetyNetPoll() {
        let stateMonitor = BluetoothStateMonitorSpy(authorization: .allowed)
        let bluetoothController = BluetoothDeviceController(
            worker: PermissionTimingBluetoothReader(),
            stateMonitor: stateMonitor,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let store = SystemStatusStore(
            batteryMonitor: EmptyBatteryMonitorForBluetoothTiming(),
            wifiMonitor: EmptyWiFiMonitorForBluetoothTiming(),
            volumeMonitor: EmptyVolumeMonitorForBluetoothTiming(),
            bluetoothDevices: bluetoothController
        )

        store.setPopoverVisible(true)
        XCTAssertTrue(bluetoothController.hasVisibleSurface)

        // The adapter reports ready: the poll may now run, and it is the surface
        // claim that allows it.
        stateMonitor.emit(authorization: .allowed, managerState: .poweredOn)
        XCTAssertTrue(bluetoothController.isSafetyNetPolling)

        store.setPopoverVisible(false)
        XCTAssertFalse(bluetoothController.hasVisibleSurface)
        XCTAssertFalse(bluetoothController.isSafetyNetPolling)

        store.setPopoverVisible(true)
        stateMonitor.emit(authorization: .allowed, managerState: .poweredOn)
        XCTAssertTrue(bluetoothController.isSafetyNetPolling)
        store.closePopoverDetails()
        XCTAssertFalse(bluetoothController.hasVisibleSurface)
        XCTAssertFalse(bluetoothController.isSafetyNetPolling)
        XCTAssertEqual(stateMonitor.stopCount, 0, "the state monitor is not what the popover owns")
    }
```

The spy needs an emit hook, mirroring `BluetoothStateMonitorStub.emit` at `Tests/StatusTrioCoreTests/WirelessListModelsTests.swift:377-380`. Add it to `BluetoothStateMonitorSpy` (`:152-170`):

```swift
    func emit(authorization: BluetoothAuthorizationStatus, managerState: BluetoothManagerState) {
        onStateChange?(authorization, managerState)
    }
```

and add the stub that keeps the test off the real profiler, next to `EmptyVolumeMonitorForBluetoothTiming` (`:197-207`):

```swift
/// The default worker runs `/usr/sbin/system_profiler`; a unit test that makes
/// the adapter report ready must not.
private final class PermissionTimingBluetoothReader: BluetoothPairedDeviceReading {
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(.success([]))
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter BluetoothPollingLifetimeTests`
Run: `swift test --filter BluetoothPermissionTimingTests`
Expected: compile failure — `extra argument 'safetyNetSleep' in call`, `value of type 'BluetoothDeviceController' has no member 'holdVisibleSurface'`, `hasVisibleSurface`, `isSafetyNetPolling`.

- [ ] **Step 3: Add the claim API and gate the safety net**

In `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`, add the stored properties next to `batteryLevelRequests` and replace `schedulePeriodicRefresh()` / `stopPeriodicRefresh()` (`:465-483`) with:

```swift
    /// Surfaces that show Bluetooth device state, by token. The safety-net poll
    /// runs only while at least one is held, so a closed popover costs nothing.
    /// A count, not a boolean: the summary row and the detail page can appear in
    /// either order, and the last writer must not decide for both.
    private var visibleSurfaces: Set<String> = []

    /// Whether a visible surface is showing Bluetooth device state.
    var hasVisibleSurface: Bool {
        !visibleSurfaces.isEmpty
    }

    /// Whether the safety-net poll is running.
    var isSafetyNetPolling: Bool {
        periodicRefreshTask != nil
    }

    /// Claims the safety net for a visible Bluetooth surface.
    func holdVisibleSurface(_ token: String) {
        guard visibleSurfaces.insert(token).inserted else { return }
        schedulePeriodicRefresh()
    }

    /// Releases a surface's claim, whatever order it arrives in.
    func releaseVisibleSurface(_ token: String) {
        guard visibleSurfaces.remove(token) != nil else { return }
        guard !hasVisibleSurface else { return }
        stopPeriodicRefresh()
    }

    private func schedulePeriodicRefresh() {
        guard isActive, hasVisibleSurface, availability == .available else { return }
        guard periodicRefreshTask == nil else { return }
        let interval = safetyNetInterval
        let sleep = safetyNetSleep
        periodicRefreshTask = Task { @MainActor [weak self] in
            defer { self?.periodicRefreshTask = nil }
            while !Task.isCancelled {
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard let self, self.isActive, self.hasVisibleSurface, self.availability == .available else {
                    return
                }
                self.refresh()
            }
        }
    }

    private func stopPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
    }
```

The `defer` matters: the loop can exit on its own when the adapter stops being available, and `schedulePeriodicRefresh()` refuses to start a second task while `periodicRefreshTask` is set. Without it, one power-off would kill the safety net for the rest of the process.

- [ ] **Step 4: Add the two initializer parameters**

In the same file, add to `init` (`:247-262`) after `workspaceNotificationCenter`:

```swift
    /// How often the safety net re-reads the paired-device database while a
    /// Bluetooth surface is visible. Connection notifications deliver the
    /// interesting changes, so this is deliberately slow.
    private let safetyNetInterval: Duration
    private let safetyNetSleep: @Sendable (Duration) async throws -> Void
```

and in the initializer body:

```swift
        self.safetyNetInterval = safetyNetInterval
        self.safetyNetSleep = safetyNetSleep
```

with the matching parameters, added after `workspaceNotificationCenter` in the signature:

```swift
        safetyNetInterval: Duration = .seconds(30),
        safetyNetSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
```

Make `activate()` (`:293-298`) resume a poll whose surface claim is still held:

```swift
    func activate() {
        guard !isActive else { return }
        isActive = true
        registerSystemObservers()
        stateMonitor.start()
        schedulePeriodicRefresh()
    }
```

- [ ] **Step 5: Hold and release the popover surface in the store**

In `Sources/StatusTrioCore/Store/SystemStatusStore.swift`, replace `activateBluetoothForPopover()` (`:252-257`) and `setPopoverVisible(_:)` (`:272-290`), and extend `closePopoverDetails()` (`:307-311`):

```swift
    /// The popover is a Bluetooth surface: its summary row reports device names
    /// while it is open. The claim is a token rather than a boolean so the
    /// SwiftUI row and the detail page can hold their own claims independently.
    private static let bluetoothPopoverSurface = "bluetooth.popover"

    /// Enables the Bluetooth monitor when the popover opens, so the row can
    /// report device names. Starting the monitor is what raises the system
    /// permission prompt, so this only runs for an app that already holds the
    /// grant; every other state is left for the row to report and for the
    /// user's tap to resolve.
    private func activateBluetoothForPopover() {
        guard BluetoothPanelActivation.shouldActivate(
            authorization: bluetoothDevices.authorization
        ) else { return }
        setBluetoothEnabled(true)
        // The state monitor is already running for a granted app, and `activate`
        // is then a no-op, so the popover asks for its own read: the row must
        // never open on a list that the last connection event did not refresh.
        bluetoothDevices.refresh()
    }

    func setPopoverVisible(_ visible: Bool) {
        guard !hasStopped else { return }
        isPopoverVisible = visible
        if !visible { batteryDetails.deactivate() }
        updateDetailsVisibility()

        guard visible else {
            clearWiFiNameResolution()
            bluetoothDevices.releaseVisibleSurface(Self.bluetoothPopoverSurface)
            return
        }
        popupPublishTask?.cancel()
        popupPublishTask = nil
        popupSnapshot = snapshot
        startWiFiNameResolutionIfNeeded()
        bluetoothDevices.prepareForPresentation()
        bluetoothDevices.holdVisibleSurface(Self.bluetoothPopoverSurface)
        activateBluetoothForPopover()
        refreshAll()
        wifiNetworks.refresh(nameAccess: popupSnapshot.wifi.nameAccess)
    }
```

```swift
    func closePopoverDetails() {
        wifiNetworks.deactivate()
        closeBluetoothDetails()
        closeBatteryDetails()
        bluetoothDevices.releaseVisibleSurface(Self.bluetoothPopoverSurface)
    }
```

- [ ] **Step 6: Claim the surface from the two Bluetooth views**

In `Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift`, extend the summary row's hooks (`:42-52`):

```swift
        .onAppear {
            controller.holdVisibleSurface(Self.summarySurfaceToken)
        }
        .onDisappear {
            controller.releaseVisibleSurface(Self.summarySurfaceToken)
            controller.releaseBatteryLevels(Self.summaryBatteryLevelsToken)
        }
```

and declare the token next to `summaryBatteryLevelsToken` (`:54`):

```swift
    private static let summarySurfaceToken = "bluetooth.summary.surface"
```

Extend the detail page's hooks (`:174-183`):

```swift
        .onAppear {
            updateBatteryLevelClaim()
            controller.activate()
            controller.holdVisibleSurface(Self.detailSurfaceToken)
        }
        .onChange(of: showsBatteryLevels) { _, _ in
            updateBatteryLevelClaim()
        }
        .onDisappear {
            controller.releaseVisibleSurface(Self.detailSurfaceToken)
            controller.releaseBatteryLevels(Self.detailBatteryLevelsToken)
        }
```

and declare:

```swift
    private static let detailSurfaceToken = "bluetooth.detail.surface"
```

- [ ] **Step 7: Run the tests**

Run: `swift test --filter BluetoothPollingLifetimeTests`
Run: `swift test --filter BluetoothPermissionTimingTests`
Run: `swift test --filter BluetoothBatteryLevelHandoffTests`
Run: `swift test --filter BluetoothSummaryLayoutTests`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift \
        Sources/StatusTrioCore/Store/SystemStatusStore.swift \
        Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift \
        Tests/StatusTrioCoreTests/BluetoothPollingLifetimeTests.swift \
        Tests/StatusTrioCoreTests/BluetoothPermissionTimingTests.swift
git commit -m "fix: poll Bluetooth only while a Bluetooth surface is visible"
```

---

### Task 4: Drive Refreshes From Connect And Disconnect Notifications

**Files:**
- Create: `Sources/StatusTrioCore/Monitoring/BluetoothConnectionEventMonitor.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift:465-478` (`schedulePeriodicRefresh` starts the monitor, `stopPeriodicRefresh` stops it), `:247-262` (`init`)
- Modify: `Sources/StatusTrioCore/App/AppEnvironment.swift:49-64` (`makeStore` wires the production monitor)
- Test: `Tests/StatusTrioCoreTests/BluetoothConnectionEventTests.swift` (Create, XCTest)

**Interfaces:**
- Consumes: `IOBluetoothDevice.register(forConnectNotifications:selector:) -> IOBluetoothUserNotification!` and `IOBluetoothDevice.register(forDisconnectNotification:selector:) -> IOBluetoothUserNotification!`, both verified in the macOS 26 SDK (`IOBluetooth.framework/Headers/objc/IOBluetoothDevice.h:136` and `:151`); `IOBluetooth` is already linked in `Package.swift:30`.
- Produces: `protocol BluetoothConnectionEventMonitoring: AnyObject` with `@discardableResult func start(handler: @escaping @Sendable () -> Void) -> Bool` and `func stop()`, plus `final class IOBluetoothConnectionEventMonitor: NSObject, BluetoothConnectionEventMonitoring, @unchecked Sendable`.
- Produces: `BluetoothDeviceController.hasConnectionEventSource: Bool`, `isMonitoringConnectionEvents: Bool`, and `init(..., connectionEvents: (any BluetoothConnectionEventMonitoring)? = nil, connectionEventDebounceInterval: Duration = .milliseconds(750), connectionEventDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) })`.

CoreBluetooth's `centralManager(_:didConnect:)` / `didDisconnectPeripheral` are not usable here: they only fire for peripherals this process connected itself, and the app never calls `CBCentralManager.connect` (the only `connect(` call site in `Sources/` is `Sources/StatusTrioCore/UI/WiFiNetworkListView.swift:54`, for Wi-Fi). `IOBluetoothDevice` connect notifications are system-wide, so they are the mechanism this task wires. If the registration is refused (Bluetooth access revoked, or no adapter), `start` returns `false` and the safety-net poll from Task 3 remains the only source.

- [ ] **Step 1: Write the failing connection-event tests**

Create `Tests/StatusTrioCoreTests/BluetoothConnectionEventTests.swift`:

```swift
import Foundation
import XCTest
@testable import StatusTrioCore

/// A device connecting or disconnecting is the event that matters, and it
/// arrives once per device: several at a time must collapse into one read.
@MainActor
final class BluetoothConnectionEventTests: XCTestCase {
    func testConnectEventsCoalesceIntoOneDebouncedRefresh() async {
        let reader = CountingBluetoothDeviceReader()
        let events = FakeBluetoothConnectionEventMonitor(isAvailable: true)
        let sleeper = ManualEventSleeper()
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: ConnectionEventStateMonitor(),
            batteryReader: ConnectionEventBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            connectionEvents: events,
            connectionEventDebounceInterval: .milliseconds(750),
            connectionEventDebounceSleep: { _ in await sleeper.sleep() }
        )

        controller.activate()
        await waitUntil { reader.readCount == 1 }
        // The event registration lives and dies with the surface that shows
        // device state, so the claim comes first.
        controller.holdVisibleSurface("bluetooth.detail")
        XCTAssertTrue(events.isRunning)
        XCTAssertTrue(controller.isMonitoringConnectionEvents)

        events.emit()
        events.emit()
        events.emit()
        await sleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertEqual(sleeper.durations.first, .milliseconds(750))
        XCTAssertEqual(reader.readCount, 1, "the debounce must hold the read until it fires")

        sleeper.releaseAll()
        await waitUntil { reader.readCount == 2 }

        controller.deactivate()
        XCTAssertFalse(events.isRunning)
    }

    /// The event source is optional: without it the safety-net poll is the only
    /// source, and holding a surface must not crash or spin.
    func testAnUnavailableEventSourceLeavesTheSafetyNetAsTheOnlySource() async {
        let reader = CountingBluetoothDeviceReader()
        let events = FakeBluetoothConnectionEventMonitor(isAvailable: false)
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: ConnectionEventStateMonitor(),
            batteryReader: ConnectionEventBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            connectionEvents: events
        )

        controller.activate()
        await waitUntil { reader.readCount == 1 }
        controller.holdVisibleSurface("bluetooth.summary")

        XCTAssertFalse(controller.isMonitoringConnectionEvents)
        XCTAssertTrue(controller.isSafetyNetPolling)

        controller.deactivate()
        XCTAssertFalse(controller.isSafetyNetPolling)
    }

    /// Without an injected source the controller must not reach for the system
    /// on its own; the app wires the IOBluetooth monitor through `makeStore`.
    func testADefaultControllerHasNoSystemEventSource() {
        let controller = BluetoothDeviceController(
            stateMonitor: ConnectionEventStateMonitor(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        XCTAssertFalse(controller.hasConnectionEventSource)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the Bluetooth controller")
    }
}

private final class CountingBluetoothDeviceReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var readCount: Int { lock.withLock { count } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock { count += 1 }
        completion(.success([
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true)
        ]))
    }
}

private final class ConnectionEventBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]) -> Void) {
        completion([:])
    }
}

@MainActor
private final class ConnectionEventStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() { onStateChange?(.allowed, .poweredOn) }
    func stop() {}
}

private final class FakeBluetoothConnectionEventMonitor: BluetoothConnectionEventMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private let isAvailable: Bool
    private var handler: (@Sendable () -> Void)?
    private var running = false

    init(isAvailable: Bool) {
        self.isAvailable = isAvailable
    }

    var isRunning: Bool { lock.withLock { running } }

    @discardableResult
    func start(handler: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock {
            self.handler = handler
            running = isAvailable
            return isAvailable
        }
    }

    func stop() {
        lock.withLock {
            handler = nil
            running = false
        }
    }

    func emit() {
        let handler = lock.withLock { self.handler }
        handler?()
    }
}
```

Add a `makeStore` wiring test to the same file:

```swift
    /// Production must hand the controller a real event source: the default is
    /// `nil` so unit tests never touch the system's Bluetooth service.
    func testAppEnvironmentWiresTheIOBluetoothEventSource() {
        let store = AppEnvironment.makeStore(
            batteryMonitor: ConnectionEventBatteryMonitor(),
            wifiMonitor: ConnectionEventWiFiMonitor(),
            volumeMonitor: ConnectionEventVolumeMonitor()
        )
        XCTAssertTrue(store.bluetoothDevices.hasConnectionEventSource)
    }
```

with these three fakes appended to the file (they mirror `EmptyBatteryMonitorForBluetoothTiming` in `Tests/StatusTrioCoreTests/BluetoothPermissionTimingTests.swift:172-207`):

```swift
@MainActor
private final class ConnectionEventBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class ConnectionEventWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() {}
}

@MainActor
private final class ConnectionEventVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter BluetoothConnectionEventTests`
Expected: compile failure — `cannot find 'BluetoothConnectionEventMonitoring' in scope`, `extra arguments at positions #6, #7, #8`.

- [ ] **Step 3: Add the IOBluetooth event monitor**

Create `Sources/StatusTrioCore/Monitoring/BluetoothConnectionEventMonitor.swift`:

```swift
import Foundation
import IOBluetooth

/// System-wide Bluetooth connect and disconnect notifications.
///
/// CoreBluetooth only reports `didConnect` for peripherals this process
/// connected itself, and the app never connects one: the paired-device database
/// belongs to macOS. `IOBluetoothDevice` connects are reported for every device
/// the system connects, which is what the summary row needs.
///
/// The callbacks are delivered on the thread that registered the notification,
/// so the implementation is nonisolated and lock-guarded, and the controller
/// hops to the main actor inside the handler it passes in.
protocol BluetoothConnectionEventMonitoring: AnyObject {
    /// Registers for connect notifications and hands back whether the system
    /// accepted the registration. A `false` result leaves the safety-net poll
    /// as the only source of device state.
    @discardableResult
    func start(handler: @escaping @Sendable () -> Void) -> Bool
    func stop()
}

final class IOBluetoothConnectionEventMonitor: NSObject, BluetoothConnectionEventMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    @discardableResult
    func start(handler: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock { self.handler = handler }
        let notification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        return lock.withLock {
            connectNotification = notification
            return notification != nil
        }
    }

    func stop() {
        let (connect, disconnects) = lock.withLock {
            () -> (IOBluetoothUserNotification?, [IOBluetoothUserNotification]) in
            let connect = connectNotification
            let disconnects = Array(disconnectNotifications.values)
            connectNotification = nil
            disconnectNotifications.removeAll()
            handler = nil
            return (connect, disconnects)
        }
        connect?.unregister()
        for notification in disconnects {
            notification.unregister()
        }
    }

    /// The connect notification is system-wide; the disconnect notification is
    /// per device, so each device that connects is watched as it arrives. The
    /// entry is overwritten on a reconnect, and every registration is released
    /// by `stop()`.
    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString ?? device.name ?? ""
        if !address.isEmpty,
           let token = device.register(
               forDisconnectNotification: self,
               selector: #selector(deviceDisconnected(_:device:))
           ) {
            lock.withLock { disconnectNotifications[address] = token }
        }
        lock.withLock { handler }?()
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString ?? ""
        lock.withLock { disconnectNotifications[address] = nil }
        lock.withLock { handler }?()
    }
}
```

- [ ] **Step 4: Wire the monitor into the controller's surface lifetime**

In `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`, add the stored properties and initializer parameters:

```swift
    /// The connect/disconnect source for the safety net. Optional so a test can
    /// build a controller that never touches the system's Bluetooth service.
    /// Teardown-owned storage: `deinit` is nonisolated and reads it directly.
    nonisolated(unsafe) private let connectionEvents: (any BluetoothConnectionEventMonitoring)?
    private let connectionEventDebounceInterval: Duration
    private let connectionEventDebounceSleep: @Sendable (Duration) async throws -> Void
    /// Invalidates a debounce that a later stop or deactivate superseded, the
    /// same way `AsyncRequestGate` guards the other asynchronous paths here.
    private var connectionEventGate = AsyncRequestGate()
    private var isConnectionEventReadScheduled = false
    /// Set from the registration result, so "monitoring" means the system
    /// accepted the registration rather than that it was merely attempted.
    private var isMonitoringConnectionEventNotifications = false

    /// Whether the controller has an event source at all.
    var hasConnectionEventSource: Bool {
        connectionEvents != nil
    }

    /// Whether connection notifications are being delivered right now.
    var isMonitoringConnectionEvents: Bool {
        isMonitoringConnectionEventNotifications
    }
```

in the initializer body:

```swift
        self.connectionEvents = connectionEvents
        self.connectionEventDebounceInterval = connectionEventDebounceInterval
        self.connectionEventDebounceSleep = connectionEventDebounceSleep
```

and in the signature, after `safetyNetSleep`:

```swift
        connectionEvents: (any BluetoothConnectionEventMonitoring)? = nil,
        connectionEventDebounceInterval: Duration = .milliseconds(750),
        connectionEventDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
```

Start and stop the monitor with the poll, in `schedulePeriodicRefresh()` / `stopPeriodicRefresh()`:

```swift
    private func schedulePeriodicRefresh() {
        guard isActive, hasVisibleSurface, availability == .available else { return }
        startConnectionEvents()
        guard periodicRefreshTask == nil else { return }
        let interval = safetyNetInterval
        let sleep = safetyNetSleep
        periodicRefreshTask = Task { @MainActor [weak self] in
            defer { self?.periodicRefreshTask = nil }
            while !Task.isCancelled {
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard let self, self.isActive, self.hasVisibleSurface, self.availability == .available else {
                    return
                }
                self.refresh()
            }
        }
    }

    private func stopPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        stopConnectionEvents()
    }

    /// Connection notifications only matter while a Bluetooth surface is on
    /// screen: nothing else displays device state, and the registration is a
    /// system resource the app should not hold for its whole lifetime.
    private func startConnectionEvents() {
        guard !isMonitoringConnectionEventNotifications, let connectionEvents else { return }
        // The handler arrives on IOBluetooth's own thread, so it hops to the
        // main actor before touching controller state.
        isMonitoringConnectionEventNotifications = connectionEvents.start { [weak self] in
            Task { @MainActor in self?.receiveConnectionEvent() }
        }
    }

    private func stopConnectionEvents() {
        _ = connectionEventGate.advance()
        isConnectionEventReadScheduled = false
        guard isMonitoringConnectionEventNotifications else { return }
        isMonitoringConnectionEventNotifications = false
        connectionEvents?.stop()
    }

    /// One read per burst of connect/disconnect notifications. macOS connects
    /// several devices at once (AirPods plus a Watch, say), and each
    /// notification would otherwise start its own profiler run.
    private func receiveConnectionEvent() {
        guard isActive, isMonitoringConnectionEventNotifications else { return }
        guard !isConnectionEventReadScheduled else { return }
        isConnectionEventReadScheduled = true
        let request = connectionEventGate.advance()
        let interval = connectionEventDebounceInterval
        let sleep = connectionEventDebounceSleep
        Task { @MainActor [weak self] in
            do {
                try await sleep(interval)
            } catch {
                guard let self, self.connectionEventGate.accepts(request) else { return }
                self.isConnectionEventReadScheduled = false
                return
            }
            guard let self, self.connectionEventGate.accepts(request) else { return }
            self.isConnectionEventReadScheduled = false
            guard self.isActive else { return }
            self.refresh()
        }
    }
```

`startConnectionEvents()` is called at the top of `schedulePeriodicRefresh()`, above its `periodicRefreshTask == nil` guard, so a surface that is already claimed re-registers after the adapter powers back on. No task handle is stored for the debounce: the gate rejects a debounce whose surface or adapter went away, which is the same shape `WiFiMonitor.scheduleRefresh()` uses at `Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift:570-591`.

- [ ] **Step 5: Wire the production monitor in `AppEnvironment.makeStore`**

In `Sources/StatusTrioCore/App/AppEnvironment.swift`, extend `makeStore` (`:49-64`):

```swift
    static func makeStore(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        connectionMonitor: (any NetworkConnectionMonitoring)? = nil,
        volumeMonitor: any VolumeMonitoring,
        refreshInterval: Duration = .seconds(5)
    ) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: batteryMonitor,
            wifiMonitor: wifiMonitor,
            connectionMonitor: connectionMonitor,
            volumeMonitor: volumeMonitor,
            refreshInterval: refreshInterval,
            bluetoothDevices: BluetoothDeviceController(
                connectionEvents: IOBluetoothConnectionEventMonitor()
            )
        )
    }
```

The initializer default stays `nil` so the existing unit tests keep building controllers that never touch the system's Bluetooth service.

- [ ] **Step 6: Run the tests**

Run: `swift test --filter BluetoothConnectionEventTests`
Run: `swift test --filter BluetoothPollingLifetimeTests`
Run: `swift test --filter SystemStatusStoreTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/BluetoothConnectionEventMonitor.swift \
        Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift \
        Sources/StatusTrioCore/App/AppEnvironment.swift \
        Tests/StatusTrioCoreTests/BluetoothConnectionEventTests.swift
git commit -m "feat: refresh Bluetooth devices from connect and disconnect events"
```

---

### Task 5: Release Observers, The Event Monitor And CoreBluetooth In `deinit`

**Files:**
- Create: `Sources/StatusTrioCore/Monitoring/SystemEventObserverBag.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift:244-245` (observer storage), `:264-266` (`deinit`), `:293-298` (`activate`), `:300-311` (`deactivate`), `:427-458` (observer registration and removal)
- Test: `Tests/StatusTrioCoreTests/BluetoothPollingLifetimeTests.swift` (XCTest, extend)

**Interfaces:**
- Consumes: the `nonisolated(unsafe)` teardown-storage pattern already used for `SystemStatusStore.wakeObserver` (`Sources/StatusTrioCore/Store/SystemStatusStore.swift:32`, `:78-85`) and for `WiFiMonitor.eventMonitor` / `pathMonitor` (`Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift:311-312`, `:373-380`).
- Produces: `final class SystemEventObserverBag: @unchecked Sendable` with `init(notificationCenter:workspaceNotificationCenter:)`, `var isEmpty: Bool`, `func install(applicationActivated:didWake:)`, `func removeAll()`.
- Produces: `BluetoothDeviceController.systemObservers: SystemEventObserverBag` (injectable as `SystemEventObserverBag?`; the default is built from the controller's own `notificationCenter` and `workspaceNotificationCenter`); `deinit` stops the event monitor, empties the bag, and hands `stateMonitor.stop()` to the main actor.

- [ ] **Step 1: Write the failing teardown tests**

Add to `BluetoothPollingLifetimeTests`:

```swift
    /// A controller that is released without `deactivate()` used to leak its
    /// NotificationCenter observers and leave CoreBluetooth running, because
    /// `CBCentralManager` retains its delegate and only `stop()` breaks that.
    func testDeinitWithoutDeactivateRemovesObserversAndStopsTheStateMonitor() async {
        let notifications = NotificationCenter()
        let observers = SystemEventObserverBag(
            notificationCenter: notifications,
            workspaceNotificationCenter: notifications
        )
        let monitor = CountingStopBluetoothStateMonitor()
        var controller: BluetoothDeviceController? = BluetoothDeviceController(
            worker: DeferredBluetoothDeviceReader(),
            stateMonitor: monitor,
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: notifications,
            workspaceNotificationCenter: notifications,
            systemObservers: observers
        )
        weak var weakController = controller
        controller?.activate()
        await waitUntil { monitor.startCount == 1 }
        XCTAssertFalse(observers.isEmpty)

        controller = nil
        XCTAssertNil(weakController)

        // `deinit` is nonisolated, so the CoreBluetooth teardown is handed to
        // the main actor instead of touching the manager off its queue.
        await waitUntil { monitor.stopCount == 1 }
        XCTAssertTrue(observers.isEmpty, "the observers outlived the controller")

        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()
        XCTAssertEqual(monitor.startCount, 1, "a removed observer must not reactivate anything")
    }

    /// The connection-event registration outlives the object unless it is
    /// released explicitly.
    func testDeinitWithoutDeactivateStopsTheConnectionEventMonitor() async {
        let events = StoppableBluetoothConnectionEventMonitor()
        var controller: BluetoothDeviceController? = BluetoothDeviceController(
            worker: DeferredBluetoothDeviceReader(),
            stateMonitor: AvailableBluetoothStateMonitor(),
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            connectionEvents: events
        )
        controller?.activate()
        controller?.holdVisibleSurface("bluetooth.detail")
        await waitUntil { events.startCount == 1 }

        controller = nil
        await waitUntil { events.stopCount == 1 }
    }

    /// The bag is the piece that makes the observer leak observable.
    func testObserverBagRemovesEveryRegistration() async {
        let notifications = NotificationCenter()
        let bag = SystemEventObserverBag(
            notificationCenter: notifications,
            workspaceNotificationCenter: notifications
        )
        let activations = CountBox()
        let wakes = CountBox()
        bag.install(
            applicationActivated: { activations.increment() },
            didWake: { wakes.increment() }
        )

        // Re-installing must not stack a second registration.
        bag.install(
            applicationActivated: { activations.increment() },
            didWake: { wakes.increment() }
        )
        XCTAssertFalse(bag.isEmpty)

        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitUntil { activations.value > 0 && wakes.value > 0 }
        XCTAssertEqual(activations.value, 1)
        XCTAssertEqual(wakes.value, 1)

        bag.removeAll()
        XCTAssertTrue(bag.isEmpty)

        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        // The block is delivered through the main queue, so give it a real
        // window to arrive before asserting that nothing was delivered.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(activations.value, 1, "a removed observer still fired")
        XCTAssertEqual(wakes.value, 1, "a removed observer still fired")
    }
```

Add these fakes at the end of the file:

```swift
@MainActor
private final class CountingStopBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
        onStateChange?(.allowed, .poweredOn)
    }

    func stop() { stopCount += 1 }
}

private final class StoppableBluetoothConnectionEventMonitor: BluetoothConnectionEventMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0

    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }

    @discardableResult
    func start(handler: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock { starts += 1 }
        return true
    }

    func stop() { lock.withLock { stops += 1 } }
}

private final class CountBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
```

The file needs `import AppKit` for `NSApplication.didBecomeActiveNotification` and `NSWorkspace.didWakeNotification`; add it next to `import Foundation`.

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter BluetoothPollingLifetimeTests`
Expected: compile failure — `cannot find 'SystemEventObserverBag' in scope`, `extra argument 'systemObservers'`.

- [ ] **Step 3: Create the observer bag**

Create `Sources/StatusTrioCore/Monitoring/SystemEventObserverBag.swift`:

```swift
import AppKit
import Foundation

/// Owns the AppKit and workspace observers a controller installs, so teardown is
/// one idempotent call. `deinit` is nonisolated, so the bag keeps its
/// registrations in lock-guarded, teardown-owned storage: it never touches
/// actor-isolated state, which is what makes it safe to release from `deinit`.
final class SystemEventObserverBag: @unchecked Sendable {
    private let lock = NSLock()
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private var registrations: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    var isEmpty: Bool {
        lock.withLock { registrations.isEmpty }
    }

    /// Installs both observers. Installing again while they are registered is a
    /// no-op, so a repeated `activate()` cannot stack duplicates that only one
    /// `removeAll()` would release.
    func install(
        applicationActivated: @escaping @Sendable () -> Void,
        didWake: @escaping @Sendable () -> Void
    ) {
        lock.withLock {
            guard registrations.isEmpty else { return }
            registrations = [
                (
                    notificationCenter,
                    notificationCenter.addObserver(
                        forName: NSApplication.didBecomeActiveNotification,
                        object: nil,
                        queue: .main
                    ) { _ in applicationActivated() }
                ),
                (
                    workspaceNotificationCenter,
                    workspaceNotificationCenter.addObserver(
                        forName: NSWorkspace.didWakeNotification,
                        object: nil,
                        queue: .main
                    ) { _ in didWake() }
                )
            ]
        }
    }

    func removeAll() {
        let removed = lock.withLock { () -> [(center: NotificationCenter, token: NSObjectProtocol)] in
            let removed = registrations
            registrations = []
            return removed
        }
        for registration in removed {
            registration.center.removeObserver(registration.token)
        }
    }
}
```

- [ ] **Step 4: Use the bag in the controller**

In `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`, delete the `applicationObserver` / `wakeObserver` properties (`:244-245`) and replace `deinit` (`:264-266`), `registerSystemObservers()` (`:427-447`) and `removeSystemObservers()` (`:449-458`) with the teardown-owned storage and the new body:

```swift
    /// The state monitor is teardown-owned storage: `deinit` is nonisolated, so
    /// it is held `nonisolated(unsafe)` for that one read. `BluetoothStateMonitoring`
    /// is `@MainActor`, and `stop()` runs on the main actor through the hop in
    /// `deinit` rather than being called off the queue CoreBluetooth was created on.
    nonisolated(unsafe) private let stateMonitor: any BluetoothStateMonitoring
    /// A `let` of a `Sendable` type is readable from a nonisolated `deinit`, so
    /// the bag needs no `nonisolated(unsafe)`.
    private let systemObservers: SystemEventObserverBag

    deinit {
        periodicRefreshTask?.cancel()
        // Releasing the registrations here is the whole point: an observer token
        // that is never removed keeps the center's block alive for the life of
        // the process.
        systemObservers.removeAll()
        connectionEvents?.stop()
        // `CBCentralManager` retains its delegate, so the state monitor is never
        // deallocated while it is running. `stop()` has to run on the main actor,
        // which is the queue the manager was created with, so the reference is
        // captured and handed over instead of `self` being used after death.
        let stateMonitor = stateMonitor
        Task { @MainActor in stateMonitor.stop() }
    }
```

`periodicRefreshTask?.cancel()` is allowed in a nonisolated `deinit`: it reads the object's own `Task` storage, which is `Sendable` and already cancelled this way at `:264-266` today. Mutating other isolated state (`isDeviceReadInFlight`, `isRefreshPending`, `isConnectionEventReadScheduled`) is not allowed there and is not needed; a pending connection-event debounce wakes, finds `self` gone, and exits.

Then replace `activate()` and `deactivate()` to use the bag, and delete `registerSystemObservers()` / `removeSystemObservers()`:

```swift
    func activate() {
        guard !isActive else { return }
        isActive = true
        systemObservers.install(
            applicationActivated: { [weak self] in
                Task { @MainActor in self?.refreshAfterSystemEvent() }
            },
            didWake: { [weak self] in
                Task { @MainActor in self?.refreshAfterSystemEvent() }
            }
        )
        stateMonitor.start()
        schedulePeriodicRefresh()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        invalidateDeviceRead()
        batteryLevelRequests.removeAll()
        updateBatteryLevelRequests()
        stopPeriodicRefresh()
        systemObservers.removeAll()
        stateMonitor.stop()
        availability = .idle
    }
```

Add the `systemObservers` parameter to `init`, after `safetyNetSleep`:

```swift
        systemObservers: SystemEventObserverBag? = nil,
```

and build the default from the centers the controller was given, so an injected
`NotificationCenter` keeps reaching the controller exactly as it does today:

```swift
        self.systemObservers = systemObservers ?? SystemEventObserverBag(
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
```

`Tests/StatusTrioCoreTests/WirelessListModelsTests.swift:272-347` posts
`NSApplication.didBecomeActiveNotification` on the center it injects and expects
the controller to react, so a bag wired to `.default` instead of the injected
center would break that test.

- [ ] **Step 5: Run the tests**

Run: `swift test --filter BluetoothPollingLifetimeTests`
Run: `swift test --filter BluetoothPermissionTimingTests`
Run: `swift test --filter WirelessListModelsTests`
Run: `swift test --filter BluetoothBatteryLevelHandoffTests`
Expected: PASS.

- [ ] **Step 6: Run the full suite and a release build**

Run: `swift test`
Run: `swift build -c release`
Expected: all tests pass; release build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/SystemEventObserverBag.swift \
        Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift \
        Tests/StatusTrioCoreTests/BluetoothPollingLifetimeTests.swift
git commit -m "fix: release Bluetooth observers and CoreBluetooth in deinit"
```

---

### Task 6: Verification, Release Notes And Preflight

**Files:**
- Modify: `release-notes/1.3.0/en.md` (append a section at the end)
- Modify: `release-notes/1.3.0/zh-Hans.md` (append the matching section at the end)

**Interfaces:**
- Consumes: every task above.
- Produces: no Swift API.

- [ ] **Step 1: Record the measurement**

Run the app from the previous build state for 60 seconds and record the process spawn count of the old behaviour, then the same after the change, so the commit message carries before and after numbers:

```bash
sudo fs_usage -w -f filesys | grep -c system_profiler
```

Alternatively, while the popover is closed, sample the process list for `system_profiler`:

```bash
for i in $(seq 1 12); do pgrep -x system_profiler >/dev/null && echo "spawn at $i"; sleep 5; done
```

Expected: no spawn at all while the popover is closed; roughly one spawn per 30 seconds while a Bluetooth surface is visible.

- [ ] **Step 2: Add the English release notes**

Append to `release-notes/1.3.0/en.md`:

```markdown
## Bluetooth stops working in the background
- The Bluetooth panel used to read the paired-device list every 15 seconds for as long as the app was running, even after the panel was closed. It now refreshes when a device connects or disconnects, and falls back to a slow check only while a Bluetooth view is on screen.
- Paired devices and battery levels now come from one system report instead of two, which halves the work each refresh does.
- The summary row and the device page are unchanged: the same names, the same levels, and the same permission behaviour — the app still asks for Bluetooth only when you open a Bluetooth view.
```

- [ ] **Step 3: Add the Chinese release notes**

Append to `release-notes/1.3.0/zh-Hans.md`:

```markdown
## 蓝牙不再在后台持续工作
- 蓝牙面板此前在 App 运行期间每 15 秒读取一次已配对设备列表，即使面板已经关闭也是如此。现在改为在设备连接或断开时刷新，仅在 Bluetooth 界面可见时保留一次慢速兜底检查。
- 已配对设备与电量现在共用同一份系统报告，每次刷新的工作量减半。
- 摘要行与设备列表的显示没有变化：同样的名称、同样的电量，权限行为也保持不变——只有在您打开 Bluetooth 界面时，App 才会请求蓝牙权限。
```

- [ ] **Step 4: Validate the release notes**

Run: `bash scripts/validate-appcast-notes.sh`
Expected: PASS — both files still start with a `# Version %VERSION% (Build %BUILD%)` / `# 版本 %VERSION%（构建 %BUILD%）` heading.

- [ ] **Step 5: Run the full acceptance sequence**

Run: `swift test`
Run: `swift build -c release`
Run: `git diff --check`
Run: `git status --short`
Expected: all tests pass, the release build succeeds, no whitespace errors, and only the files listed in this plan are modified.

- [ ] **Step 6: Run the non-publishing release preflight**

Run:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref perf/bluetooth-polling-lifetime \
  -f version=1.3.0 \
  -f build=12 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: the workflow passes without publishing. This change touches `@MainActor` types, `deinit` and SwiftUI view hooks, so the preflight is mandatory.

- [ ] **Step 7: Record the preflight**

Append the run ID and result to `docs/swift-ci-compatibility.md` if the run failed at any stage; a passing run needs no entry.

- [ ] **Step 8: Commit**

```bash
git add release-notes/1.3.0/en.md release-notes/1.3.0/zh-Hans.md
git commit -m "docs(release-notes): record the Bluetooth polling fix in 1.3.0"
```

---

## Verification

1. `swift test` — the whole suite passes, including the four Bluetooth suites this plan extends (`BluetoothPollingLifetimeTests`, `BluetoothConnectionEventTests`, `BluetoothPermissionTimingTests`, `BluetoothBatteryReaderTests`) and the pre-existing `WirelessListModelsTests`, `BluetoothBatteryControllerTests`, `BluetoothBatteryLevelHandoffTests`, `BluetoothSummaryLayoutTests`.
2. `swift build -c release` — succeeds.
3. `grep -rn "system_profiler" Sources/` — exactly four hits, the `executableURL` and `arguments` lines in the two `readSystemProfilerOutput()` methods, and no other spawn site.
4. `grep -rn "Task.sleep(for: .seconds(15))" Sources/` — no hits: the unconditional 15-second loop is gone. (This exact pattern does not match `BatteryDetailsController.swift:41`, which is a different, out-of-scope loop with an explicit tolerance.)
5. `bash scripts/validate-appcast-notes.sh` — passes with the two new release-note sections.
6. `git diff --check` and `git status --short` — no whitespace errors, only intended files touched.
7. Measurement from Task 6 Step 1 recorded in the final commit message: no `system_profiler` spawn while the popover is closed.
8. `gh workflow run release.yml --repo lingyired/status-trio --ref perf/bluetooth-polling-lifetime -f version=1.3.0 -f build=12 -f publish=false` followed by `gh run watch <run-id> --repo lingyired/status-trio --exit-status` — passes.

## Out of Scope

- Changing what the Bluetooth row displays, its wording, or its localization keys.
- Replacing `system_profiler` with `IOBluetoothDevice.nameOrAddress` or a CoreBluetooth peripheral scan: the profiler is the only source that reports the name the system currently uses, as documented at `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift:25-32`.
- Requesting Bluetooth permission from any path other than an explicit user action; `BluetoothPanelActivation.shouldActivate` (`Sources/StatusTrioCore/Models/WiFiNetworkModels.swift:440-446`) is unchanged.
- Bluetooth audio device selection, the `bluetoothAudioOptions` icon settings in `Sources/StatusTrioCore/App/AppEnvironment.swift:114-121`, and the Dock/menu bar icon rendering.
- The status poll scheduling that lives in `SystemStatusStore.start()` (`Sources/StatusTrioCore/Store/SystemStatusStore.swift:144-155`) — that is R-03's plan.
- Extracting the battery-claim token API into a shared abstraction with the new surface claims. The two sets stay separate because the summary row only claims battery levels when it reports AirPods, while the surface claim covers the whole row.

## File Ownership & Conflicts

| File | Other 2026-09-20 plans | Rule |
| --- | --- | --- |
| `Store/SystemStatusStore.swift` | R-03 (`2026-09-20-status-poll-scheduling.md`), R-02 (`2026-09-20-wifi-scan-cadence.md`) | **R-03 lands first** (per the index's matrix it restructures the poll loop and visibility gating). This plan then rebases and only edits the Bluetooth activation surface claims at `:240-257`, `:272-290`, `:307-311`. R-02 adds `closeWiFiDetails()` in the same type: land this plan before R-02, or hand-resolve. |
| `Monitoring/BluetoothDeviceController.swift` | none | Owned by this plan (R-01). |
| `Monitoring/BluetoothBatteryReader.swift` | none | Owned by this plan (R-01). |
| `App/AppEnvironment.swift` | R-03 (it constructs the store with the refresh interval) | Land after R-03; only the `makeStore` body at `:49-64` changes here. |
| `UI/BluetoothDeviceListView.swift` | none | Owned by this plan (R-01). |
| `Tests/StatusTrioCoreTests/BluetoothPermissionTimingTests.swift` | R-19 (`2026-09-20-icon-parity-and-lifecycle-tests.md` adds new test files, not this one) | No conflict; R-19's new files may assert `deinit` behaviour, so land this plan first so its assertions describe the fixed behaviour. |
| `Tests/StatusTrioCoreTests/BluetoothBatteryReaderTests.swift` | R-16 (`2026-09-20-fixed-sleep-test-hardening.md` does not list this file) | No conflict. |
| `Tests/StatusTrioCoreTests/BluetoothPollingLifetimeTests.swift`, `Tests/StatusTrioCoreTests/BluetoothConnectionEventTests.swift` | none | New files, owned by this plan. |
| `release-notes/1.3.0/en.md`, `release-notes/1.3.0/zh-Hans.md` | R-09 (`2026-09-20-update-source-fallback-policy.md`), R-13 (`2026-09-20-single-instance-and-pasteboard.md`) | Notes are append-only in this version. If two plans land together, keep both sections and re-run `bash scripts/validate-appcast-notes.sh`; only the `# Version %VERSION% (Build %BUILD%)` heading is shared. |
| `docs/swift-ci-compatibility.md` | R-18 (`2026-09-20-toolchain-method-reference-compliance.md`) | Append-only record; add this plan's failed runs, if any, at the end. |

Recommended merge order: **R-03 → R-01 (this plan) → R-02**, with R-19 free to land before or after. R-03 lands first because it rewrites `SystemStatusStore.start()` and `updateDetailsVisibility()`, which this plan must not disturb; R-02 lands last because it adds a third store method in the same region.
