# Status Poll Scheduling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the 5-second fallback poll honest and cheap: let the system coalesce it, raise its default cadence, refresh only what is on screen on most ticks while keeping the menu bar icon live, stop polling a sleeping display, and stop republishing an unchanged live volume.

**Architecture:** Keep the event-driven monitor architecture untouched. The fallback poll in `SystemStatusStore` stays the safety net behind push channels (IOPS run-loop source, `CWEventDelegate`, `NWPathMonitor`, CoreAudio property listeners); this plan changes only *when* and *how often* it runs. Battery is refreshed on every tick because its percentage and charging state are drawn into the icon; Wi-Fi and volume, which have push channels and are refreshed fully whenever the popover or the Settings window is visible, get a slower watchdog cadence while no such surface is on screen. The two notification paths that already exist for system wake are extended with the display sleep/wake notifications, and `liveVolume` gains the same equality check `publish` already applies to the snapshot.

**Tech Stack:** Swift 6.3-compatible SwiftPM package (CI toolchain Xcode 26.6 / Swift 6.3.3, macOS 15 deployment target), AppKit, SwiftUI, Combine, CoreWLAN, IOKit, CoreAudio, XCTest.

**Spec:** Derived from the 2026-09-20 code review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md (finding **R-03**).

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3. The local machine is Xcode 27 / Swift 6.4 — a local build is NOT proof that CI compiles.
- Forbidden in this repo: `isolated deinit`, enabling the `IsolatedDeinit` experimental feature, `weak let` (use `weak var`), passing actor-isolated methods directly as function values (use an explicit closure), assuming `Bundle.module` resource/lproj casing.
- The app must build with the macOS 26 SDK or newer; `scripts/build-app.sh` enforces it and `scripts/verify-platform-version.sh` asserts the binary. Do not weaken either.
- Run `swift test` and `swift build -c release` before committing Swift changes.
- If a change touches actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources, a non-publishing release preflight is mandatory: `gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false` then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`. This plan touches `@MainActor` state and `deinit`, so the preflight is mandatory.
- Any user-visible behavior change requires release notes added to the existing unreleased `release-notes/1.3.0/en.md` and `release-notes/1.3.0/zh-Hans.md`.
- Any change to menu bar icon rendering or icon settings must be mirrored in the Dock icon in the same change (SettingsStore option derivation, StatusBarController subscriptions, AppIconController subscriptions/state, `DockIconRenderKey` cache inputs, `DockIconRenderer` rendering, plus tests for both). This plan changes no icon input, and the refresh interval is deliberately absent from `SettingsStore.iconAppearancePublisher` (`Sources/StatusTrioCore/Settings/SettingsStore+IconAppearance.swift:21-42`), so no Dock mirror is required — both icons read the same `store.snapshot`, so both gain the same freshness and lose none.
- Tests are mixed: most files use Swift Testing (`import Testing`, `@Test`, `#expect`, `@MainActor` suites), some use XCTest (`XCTAssert*`, `XCTSkipUnless`). Read the test file you extend and match its framework and style. Every file this plan extends is XCTest (`@MainActor final class ...: XCTestCase`).
- Do not run the app to verify the *behaviour* of this plan. The fallback poll's cost and gating are proven by the injected sleep and the fake monitors' counters. The idle-`top` before/after measurement in Task 7 Step 4 is **required evidence, not an optional extra**: the release notes advertise the saving, so the after-change sample must be taken on this branch's own build and both numbers recorded before 1.3.0 is published.

## Review Focus

- **The menu bar icon must still change while the popover is closed.** Wi-Fi and volume are refreshed on most hidden ticks *less* eagerly, so the push path is what keeps the icon live: `testPushedWiFiAndVolumeStillUpdateTheSnapshotWhileThePopoverIsClosed` drives `wifi.send(_:)` / `volume.send(_:)` with the popover closed and asserts `store.snapshot` — the value both icons render from — takes the new values.
- **Battery must never go stale, because it is drawn.** A user on battery power sees the percentage text and the charging bolt; `testFallbackTickRefreshesBatteryEveryTickAndWiFiAndVolumeOnTheHiddenStride` asserts a battery refresh on every one of the four ticks while Wi-Fi and volume refresh once, and `testFallbackTickRefreshesWiFiAndVolumeWhileThePopoverIsOpen` asserts that opening the popover restores all three to the configured interval.
- **A skipped-display path must not be able to stop the poll forever.** The display-asleep rule only skips *work*, and the skip itself is bounded by `maximumDisplayAsleepSkips` so a *lost* display-wake notification cannot freeze the icon for the rest of the session. `testFallbackTickSkipsWhileTheDisplayIsAsleepAndRefreshesOnDisplayWake` pins zero battery refreshes while asleep plus a refresh and recovery after `screensDidWakeNotification`, and `testFallbackTickSelfHealsAfterTheDisplayAsleepSkipCap` pins that the cap runs one refresh and then resets the counter.
- **A user who chose 5 seconds must still get 5 seconds.** The adjustable range stays `5...60` with 5-second steps and 5 seconds is the lower bound, pinned by the existing `SettingsStoreTests.testRefreshIntervalDefaultsAndRange` (updated only for the new default) and by `SettingsStoreTests.testRefreshIntervalClampsRoundsAndPersists`, which asserts that 7 seconds rounds down to 5 and that a clamped value survives a reload.
- **An unchanged volume reading must not invalidate the popover body.** `@Published liveVolume` fires `objectWillChange` on every assignment, so a poll that re-reads the same scalar re-rendered every volume observer; `testUnchangedVolumeYieldDoesNotRepublishLiveVolume` counts `objectWillChange` emissions across one equal and one changed yield and requires exactly two — the changed reading's `liveVolume` and `snapshot`, with the repeat contributing nothing.

---

### Task 1: Tolerance On The Fallback Sleep

**Files:**
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift` (new static helper next to `popupDebounceInterval` at lines 7-8; the `sleep` default argument at lines 48-50)
- Test: `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift` (new test after `testChangingRefreshIntervalAffectsNextSleepCycle`, lines 737-758)

**Interfaces:**
- Produces: `static func refreshSleepTolerance(for interval: Duration) -> Duration` on `SystemStatusStore`.
- Consumes: nothing.

- [ ] **Step 1: Write the failing tolerance test**

Add to `SystemStatusStoreTests`:

```swift
func testFallbackSleepToleranceCoversTheAdjustableRange() {
    // A fifth of the interval. The fallback poll is a safety net behind the
    // push channels, so macOS may slide it onto another timer, but the sampling
    // cadence has to survive that.
    XCTAssertEqual(SystemStatusStore.refreshSleepTolerance(for: .seconds(5)), .seconds(1))
    XCTAssertEqual(SystemStatusStore.refreshSleepTolerance(for: .seconds(10)), .seconds(2))
    XCTAssertEqual(SystemStatusStore.refreshSleepTolerance(for: .seconds(15)), .seconds(3))
    XCTAssertEqual(SystemStatusStore.refreshSleepTolerance(for: .seconds(30)), .seconds(6))
    XCTAssertEqual(SystemStatusStore.refreshSleepTolerance(for: .seconds(60)), .seconds(12))
    XCTAssertEqual(SystemStatusStore.refreshSleepTolerance(for: .seconds(1)), .milliseconds(200))
}
```

- [ ] **Step 2: Run the test and verify RED**

Run: `swift test --filter SystemStatusStoreTests/testFallbackSleepToleranceCoversTheAdjustableRange`
Expected: compile failure — `type 'SystemStatusStore' has no member 'refreshSleepTolerance'`.

- [ ] **Step 3: Add the helper and use it in the default sleep**

Next to `static let popupDebounceInterval` in `SystemStatusStore`:

```swift
    /// Tolerance for the fallback poll. Without one, macOS must wake the CPU on
    /// an exact schedule to satisfy the timer, which is exactly what an idle
    /// menu bar app should not ask for; a fifth of the interval still samples
    /// often enough for a value that the push channels did not report.
    static func refreshSleepTolerance(for interval: Duration) -> Duration {
        interval / 5
    }
```

Replace the `sleep` default argument:

```swift
        sleep: @escaping @Sendable (Duration) async throws -> Void = { interval in
            try await Task.sleep(
                for: interval,
                tolerance: SystemStatusStore.refreshSleepTolerance(for: interval)
            )
        },
```

The injected-closure signature is unchanged on purpose: every existing test that passes `sleep: { _ in await sleeper.sleep() }` keeps compiling, and only the production default gains the tolerance.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter SystemStatusStoreTests`
Expected: PASS, including `testChangingRefreshIntervalAffectsNextSleepCycle` and `testPeriodicRefreshUsesInjectedSleep`, which prove the injected closure still receives the interval.

- [ ] **Step 5: Commit**

Run: `git add Sources/StatusTrioCore/Store/SystemStatusStore.swift Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift && git commit -m "perf(store): let the fallback poll sleep be coalesced"`

---

### Task 2: Raise The Default Refresh Interval To 15 Seconds

**Files:**
- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift` (line 46 `defaultRefreshIntervalSeconds`; line 45 range stays `5...60`; `clampedRefreshInterval` at lines 635-639 stays as it is)
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift` (line 46 `refreshInterval: Duration = .seconds(5)`)
- Modify: `Sources/StatusTrioCore/App/AppEnvironment.swift` (line 55 `refreshInterval: Duration = .seconds(5)` in `makeStore`, lines 50-64)
- Test: `Tests/StatusTrioCoreTests/SettingsStoreTests.swift` (`testRefreshIntervalDefaultsAndRange`, lines 36-42)
- Test: `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift` (new test after `testFallbackSleepToleranceCoversTheAdjustableRange`)

**Interfaces:**
- Consumes: `SystemStatusStore.refreshSleepTolerance(for:)` from Task 1 (same file, no call-site change).
- Produces: `SettingsStore.defaultRefreshIntervalSeconds == 15`, `SystemStatusStore.init(refreshInterval: Duration = .seconds(15))`, and `AppEnvironment.makeStore(..., refreshInterval: Duration = .seconds(15))`.

- [ ] **Step 1: Write the failing default-interval tests**

Update the existing default test in `SettingsStoreTests`:

```swift
    func testRefreshIntervalDefaultsAndRange() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(SettingsStore.refreshIntervalRange, 5...60)
        XCTAssertEqual(store.refreshIntervalSeconds, 15, accuracy: 0.001)
        XCTAssertEqual(store.refreshInterval, .seconds(15))
    }
```

Add to `SystemStatusStoreTests`, which leaves `refreshInterval` at its default and therefore observes the production default through the injected sleeper:

```swift
    func testFallbackPollDefaultsToFifteenSeconds() async {
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            sleep: { duration in await sleeper.sleep(duration) }
        )

        store.start()
        await sleeper.waitForCallCount(1)

        XCTAssertEqual(sleeper.durations.first, .seconds(15))
        store.stop()
        sleeper.releaseAll()
    }
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter SettingsStoreTests/testRefreshIntervalDefaultsAndRange`
Expected: `XCTAssertEqual failed: ("5.0") is not equal to ("15.0")`.
Run: `swift test --filter SystemStatusStoreTests/testFallbackPollDefaultsToFifteenSeconds`
Expected: `XCTAssertEqual failed: ("5.0") is not equal to ("15.0")` — the `ManualSleeper` records the store's old default of 5 seconds.

- [ ] **Step 3: Change all three defaults**

In `SettingsStore`:

```swift
    static let refreshIntervalRange: ClosedRange<Double> = 5...60
    /// The fallback poll sits behind push channels, so its steady-state cadence
    /// is a watchdog rather than the primary update path. 15 seconds keeps the
    /// icon honest without waking the CPU every 5; 5 stays available in
    /// `refreshIntervalRange` for anyone who wants the old cadence.
    static let defaultRefreshIntervalSeconds: Double = 15
    static let refreshIntervalDefaultsKey = "statusRefreshIntervalSeconds"
```

In `SystemStatusStore.init`:

```swift
        refreshInterval: Duration = .seconds(15),
```

In `AppEnvironment.makeStore` (line 55), the third copy of the same default, so a test store built through the factory is not left on the old cadence:

```swift
        refreshInterval: Duration = .seconds(15)
```

Only fresh installs move: `SettingsStore.init` reads the stored `statusRefreshIntervalSeconds` first (lines 490, 568-570), so an existing user's saved value keeps winning, and `AppEnvironment.live()` already passes `settings.refreshInterval` (lines 68-73).

- [ ] **Step 4: Run the tests**

Run: `swift test --filter SettingsStoreTests`
Run: `swift test --filter SystemStatusStoreTests`
Expected: PASS, including `testMakeStoreUsesInjectedMonitors` (line 602) and `testMakeStoreUsesInjectedConnectionMonitor` (line 575), which build a store through `AppEnvironment.makeStore` and therefore exercise the new factory default. The factory takes no injectable sleeper, so its default is pinned by those two tests still passing plus the `SystemStatusStore` default they now inherit.

- [ ] **Step 5: Commit**

Run: `git add Sources/StatusTrioCore/Settings/SettingsStore.swift Sources/StatusTrioCore/Store/SystemStatusStore.swift Sources/StatusTrioCore/App/AppEnvironment.swift Tests/StatusTrioCoreTests/SettingsStoreTests.swift Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift && git commit -m "perf(settings): default the status refresh interval to 15 seconds"`

---

### Task 3: Refresh Battery Every Tick, Wi-Fi And Volume On A Hidden Watchdog

**Files:**
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift` (static constants at lines 7-8; new private state next to `refreshTask` at line 29; refresh loop at lines 144-155; `refreshAll()` at lines 321-326)
- Test: `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift` (update `testPeriodicRefreshUsesInjectedSleep` at lines 710-735 and `testStopPreventsFurtherPeriodicRefresh` at lines 760-786; new tests after them)

**Interfaces:**
- Produces: `static let hiddenFallbackTickStride: Int = 4` on `SystemStatusStore`.
- Produces: `private func fallbackRefreshTick()` — the periodic tick; `func refreshAll()` keeps its meaning as the unconditional full refresh used by popover opening, Settings opening and wake recovery.
- Consumes: `isPopoverVisible` (line 36), `isSettingsVisible` (line 37), and the per-monitor detail gating in `updateDetailsVisibility()` (lines 335-339).

- [ ] **Step 1: Write the failing tick-scheduling tests**

Update `testPeriodicRefreshUsesInjectedSleep` so it keeps pinning the injected sleep and now pins the hidden rule:

```swift
    func testPeriodicRefreshUsesInjectedSleep() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        await sleeper.waitForCallCount(1)
        sleeper.releaseNext()
        await sleeper.waitForCallCount(2)

        // The popover and the Settings window are both closed, so the battery —
        // which is drawn into the icon — is refreshed and the two detail-level
        // monitors wait for the watchdog tick.
        XCTAssertEqual(battery.refreshCount, 1)
        XCTAssertEqual(wifi.refreshCount, 0)
        XCTAssertEqual(volume.refreshCount, 0)

        store.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(2)
    }
```

Update `testStopPreventsFurtherPeriodicRefresh` so all three monitors refresh on the tick it counts, keeping the original "stop ends the poll" meaning:

```swift
    func testStopPreventsFurtherPeriodicRefresh() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        // Opening the popover refreshes everything, and the tick that follows
        // refreshes everything again while it stays open.
        store.setPopoverVisible(true)
        await sleeper.waitForCallCount(1)
        sleeper.releaseNext()
        await sleeper.waitForCallCount(2)

        store.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(2)
        store.refreshAll()

        XCTAssertEqual(battery.refreshCount, 2)
        XCTAssertEqual(wifi.refreshCount, 2)
        XCTAssertEqual(volume.refreshCount, 2)
    }
```

Add the two new scheduling tests:

```swift
    func testFallbackTickRefreshesBatteryEveryTickAndWiFiAndVolumeOnTheHiddenStride() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        for tick in 1...SystemStatusStore.hiddenFallbackTickStride {
            await sleeper.waitForCallCount(tick)
            sleeper.releaseNext()
            await sleeper.waitForCompletionCount(tick)
        }
        await sleeper.waitForCallCount(SystemStatusStore.hiddenFallbackTickStride + 1)

        XCTAssertEqual(battery.refreshCount, SystemStatusStore.hiddenFallbackTickStride)
        XCTAssertEqual(wifi.refreshCount, 1, "one watchdog refresh against a missed CoreWLAN event")
        XCTAssertEqual(volume.refreshCount, 1, "one watchdog refresh against a missed CoreAudio event")

        store.stop()
        sleeper.releaseAll()
    }

    func testFallbackTickRefreshesWiFiAndVolumeWhileThePopoverIsOpen() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        store.setPopoverVisible(true)
        await sleeper.waitForCallCount(1)
        sleeper.releaseNext()
        await sleeper.waitForCompletionCount(1)
        await sleeper.waitForCallCount(2)

        XCTAssertEqual(battery.refreshCount, 2)
        XCTAssertEqual(wifi.refreshCount, 2)
        XCTAssertEqual(volume.refreshCount, 2)

        store.stop()
        sleeper.releaseAll()
    }
```

Add the test that proves the menu bar icon keeps its inputs while the popover is closed:

```swift
    func testPushedWiFiAndVolumeStillUpdateTheSnapshotWhileThePopoverIsClosed() async {
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        XCTAssertFalse(store.isPopoverVisible)

        wifi.send(WiFiStatus(state: .connected, rssi: -42))
        volume.send(VolumeStatus(scalar: 0.8, isMuted: false, deviceName: "Studio Display"))
        await waitUntil {
            store.snapshot.wifi.rssi == -42 && store.snapshot.volume.scalar == 0.8
        }

        XCTAssertEqual(store.snapshot.wifi.state, .connected)
        XCTAssertEqual(store.snapshot.volume.scalar, 0.8)
        store.stop()
        sleeper.releaseAll()
    }
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter SystemStatusStoreTests`
Expected: compile failure — `type 'SystemStatusStore' has no member 'hiddenFallbackTickStride'`, so the whole file fails and no test in it runs.

Then add only the constant (`static let hiddenFallbackTickStride = 4`, with the doc comment from Step 3) and run again:
Run: `swift test --filter SystemStatusStoreTests/testFallbackTickRefreshesBatteryEveryTickAndWiFiAndVolumeOnTheHiddenStride`
Expected: `XCTAssertEqual failed: ("4.0") is not equal to ("1.0")` for `wifi.refreshCount` — the tick still calls `refreshAll()`, so every tick refreshes all three monitors.
Run: `swift test --filter SystemStatusStoreTests/testPeriodicRefreshUsesInjectedSleep`
Expected: `XCTAssertEqual failed: ("1.0") is not equal to ("0.0")` for `wifi.refreshCount`.

- [ ] **Step 3: Split the tick out of `refreshAll()`**

Add the stride constant next to `popupDebounceInterval` and the counter next to `refreshTask`:

```swift
    static let popupDebounceInterval: Duration = .milliseconds(500)

    /// The fallback poll refreshes the battery on every tick: its percentage and
    /// charging state are drawn into the menu bar icon and cannot go stale.
    /// Wi-Fi and volume have push channels (CoreWLAN events, the network path
    /// monitor, CoreAudio property listeners) and are drawn into the same icon,
    /// so while no surface that shows their details is on screen they are
    /// refreshed every fourth tick as a watchdog against a missed event. Four
    /// ticks are 60 seconds at the default interval, 20 at the 5-second minimum
    /// and 240 at the 60-second maximum, next to a push path that has already
    /// reported every change it saw.
    static let hiddenFallbackTickStride = 4
```

```swift
    private var refreshTask: Task<Void, Never>?
    private var fallbackTickCount = 0
```

Point the loop at the new tick:

```swift
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let sleep = self?.sleep, let interval = self?.refreshInterval else { return }
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.fallbackRefreshTick()
            }
        }
```

Add the tick below `refreshAll()`:

```swift
    /// One fallback tick. `refreshAll()` remains the unconditional refresh for
    /// popover opening, Settings opening and wake recovery; this one is the
    /// steady-state poll and only pays for what the menu bar icon and the Dock
    /// icon are currently drawing.
    private func fallbackRefreshTick() {
        guard !hasStopped else { return }
        fallbackTickCount &+= 1
        batteryMonitor.refresh()

        let showsStatusUI = isPopoverVisible || isSettingsVisible
        guard showsStatusUI || fallbackTickCount % Self.hiddenFallbackTickStride == 0 else { return }
        wifiMonitor.refresh()
        volumeMonitor.refresh()
    }
```

`refreshAll()` (lines 321-326) is unchanged: it stays `batteryMonitor.refresh(); wifiMonitor.refresh(); volumeMonitor.refresh()`.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter SystemStatusStoreTests`
Expected: PASS. `connectionMonitor` is deliberately absent from both paths: `NetworkConnectionMonitoring` has no `refresh()` (`Sources/StatusTrioCore/Monitoring/MonitorProtocols.swift:29-35`), it is push-only through `NWPathMonitor` and is reconciled by `recover()` on wake.

- [ ] **Step 5: Commit**

Run: `git add Sources/StatusTrioCore/Store/SystemStatusStore.swift Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift && git commit -m "perf(store): poll Wi-Fi and volume on a hidden watchdog tick"`

---

### Task 4: Skip The Tick While The Display Is Asleep

**Files:**
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift` (observer storage at line 32; `deinit` at lines 78-85; `start()` observers at lines 93-103; `stop()` teardown at lines 162-166; the `fallbackRefreshTick()` guard added by Task 3)
- Test: `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift` (new tests after the Task 3 tests; update the spy counts in `testWakeNotificationAfterStopDoesNotRefresh`, lines 836-868)

**Interfaces:**
- Consumes: `fallbackRefreshTick()` from Task 3, `recoverAll()` (lines 328-333) and `refreshAll()` (lines 321-326).
- Produces: `@Published private(set) var isDisplayAsleep: Bool` (declared next to `isPopoverVisible` at line 36, exposed for the same reason: the tests drive it), plus two `nonisolated(unsafe)` observer tokens removed by `deinit` and `stop()`.

- [ ] **Step 1: Write the failing display-sleep tests**

```swift
    func testFallbackTickSkipsWhileTheDisplayIsAsleepAndRefreshesOnDisplayWake() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let displayCenter = NotificationCenter()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() },
            wakeNotificationCenter: displayCenter
        )

        store.start()
        displayCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        // The observer hops through the main actor, so wait for the flag before
        // releasing the tick that must be skipped.
        await waitUntil { store.isDisplayAsleep }

        await sleeper.waitForCallCount(1)
        sleeper.releaseNext()
        await sleeper.waitForCompletionCount(1)
        await sleeper.waitForCallCount(2)

        XCTAssertEqual(battery.refreshCount, 0, "a sleeping display has no menu bar to keep fresh")
        XCTAssertEqual(wifi.refreshCount, 0)
        XCTAssertEqual(volume.refreshCount, 0)

        displayCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        await waitUntil { battery.refreshCount == 1 }

        XCTAssertFalse(store.isDisplayAsleep)
        XCTAssertEqual(wifi.refreshCount, 1)
        XCTAssertEqual(volume.refreshCount, 1)
        XCTAssertEqual(battery.recoverCount, 1, "the display wake resynchronizes the monitors")

        store.stop()
        sleeper.releaseAll()
    }
```

Update the existing spy test so it pins both observer registrations and their removal:

```swift
        store.start()
        XCTAssertEqual(wakeCenter.addCount, 3)
        store.stop()
        XCTAssertEqual(wakeCenter.removeCount, 3)
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter SystemStatusStoreTests`
Expected: compile failure — `value of type 'SystemStatusStore' has no member 'isDisplayAsleep'`, so the whole file fails and no test in it runs.

Then add only the `isDisplayAsleep` property and the two observers (Step 3, without the `fallbackRefreshTick()` guard) and run again:
Run: `swift test --filter SystemStatusStoreTests/testFallbackTickSkipsWhileTheDisplayIsAsleepAndRefreshesOnDisplayWake`
Expected: `XCTAssertEqual failed: ("1.0") is not equal to ("0.0")` for `battery.refreshCount` — the flag is set, but the tick ignores it.
Run: `swift test --filter SystemStatusStoreTests/testWakeNotificationAfterStopDoesNotRefresh`
Expected: `XCTAssertEqual failed: ("1.0") is not equal to ("3.0")` for `wakeCenter.addCount`.

- [ ] **Step 3: Add the display state, the two observers, and the tick guard**

State, next to `isPopoverVisible` so the tests can wait on it the same way:

```swift
    @Published private(set) var isPopoverVisible = false
    /// True while the display is asleep. The fallback poll skips its work then,
    /// because no menu bar or Dock tile is on screen to keep fresh.
    @Published private(set) var isDisplayAsleep = false
    private var isSettingsVisible = false
```

Observer storage, next to `wakeObserver`:

```swift
    nonisolated(unsafe) private var wakeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var displaySleepObserver: NSObjectProtocol?
    nonisolated(unsafe) private var displayWakeObserver: NSObjectProtocol?
```

Register them in `start()` after the existing wake observer, using the same `queue: .main` plus `Task { @MainActor ... }` shape it already uses:

```swift
        displaySleepObserver = wakeNotificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isDisplayAsleep = true
            }
        }

        displayWakeObserver = wakeNotificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isDisplayAsleep = false
                self.recoverAll()
                self.refreshAll()
            }
        }
```

The system-wake observer at lines 93-103 keeps its own shape and stays the path that recovers from a full sleep; the display-wake path mirrors its `recover()`-then-`refresh()` order because a lid that closed while the display slept can have invalidated the CoreWLAN connection.

Skip the work in the tick:

```swift
    private func fallbackRefreshTick() {
        guard !hasStopped else { return }
        // Asleep skips this tick's work, but the skip is bounded on purpose: the
        // flag is cleared by two wake notifications, and a display-only sleep
        // whose wake notification is lost would otherwise stop battery refreshes
        // for the whole session, freezing the battery percentage drawn into the
        // menu bar icon. `maximumDisplayAsleepSkips` runs a tick anyway once per
        // cap, so the worst case is one extra refresh per five minutes.
        if isDisplayAsleep {
            displayAsleepSkipCount &+= 1
            guard displayAsleepSkipCount >= Self.maximumDisplayAsleepSkips else { return }
        }
        displayAsleepSkipCount = 0
        fallbackTickCount &+= 1
        batteryMonitor.refresh()
        ...
    }
```

Remove both observers in `deinit` and `stop()` following the existing `wakeObserver` pattern (lines 78-85 and 162-166):

```swift
    deinit {
        if let wakeObserver {
            wakeNotificationCenter.removeObserver(wakeObserver)
        }
        if let displaySleepObserver {
            wakeNotificationCenter.removeObserver(displaySleepObserver)
        }
        if let displayWakeObserver {
            wakeNotificationCenter.removeObserver(displayWakeObserver)
        }
        monitorTasks.forEach { $0.cancel() }
        refreshTask?.cancel()
        popupPublishTask?.cancel()
    }
```

```swift
        if let wakeObserver {
            wakeNotificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let displaySleepObserver {
            wakeNotificationCenter.removeObserver(displaySleepObserver)
            self.displaySleepObserver = nil
        }
        if let displayWakeObserver {
            wakeNotificationCenter.removeObserver(displayWakeObserver)
            self.displayWakeObserver = nil
        }
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter SystemStatusStoreTests`
Expected: PASS, including the unchanged `testWakeNotificationRefreshesAllMonitorsExactlyOnce`, which posts only `didWakeNotification` and therefore still sees exactly one recovery and one refresh per monitor.

- [ ] **Step 5: Commit**

Run: `git add Sources/StatusTrioCore/Store/SystemStatusStore.swift Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift && git commit -m "perf(store): skip the fallback poll while the display is asleep"`

---

### Task 5: Stop Republishing An Unchanged Live Volume

**Files:**
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift` (`applyVolume(_:)` at lines 354-357; `publish(_:)` at lines 359-364 stays as the snapshot's own gate)
- Test: `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift` (new test after `testSetVolumePreservesCurrentOutputDevice`, lines 403-434)

**Interfaces:**
- Consumes: `store.objectWillChange` (`ObservableObject`), `liveVolume` (line 13), `publish(_:)` (lines 359-364).
- Produces: no new API; `applyVolume(_:)` writes `liveVolume` only when the value differs.

- [ ] **Step 1: Write the failing change-count test**

```swift
    func testUnchangedVolumeYieldDoesNotRepublishLiveVolume() async {
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: FakeBatteryMonitor(),
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in await sleeper.sleep() }
        )

        store.start()
        let unchanged = VolumeStatus(scalar: 0.4, isMuted: false, deviceName: "Speaker")
        volume.send(unchanged)
        await waitUntil { store.liveVolume == unchanged }

        var changeCount = 0
        let cancellable = store.objectWillChange.sink { _ in changeCount += 1 }

        // A fallback poll that re-reads the same scalar, followed by a real
        // change. The stream is FIFO, so observing the second value proves the
        // first one was applied. The changed reading publishes twice — once for
        // `liveVolume` and once for `snapshot` — and the repeated reading must
        // publish nothing at all, so the total is exactly two.
        volume.send(unchanged)
        volume.send(VolumeStatus(scalar: 0.7, isMuted: false, deviceName: "Speaker"))
        await waitUntil { store.liveVolume.scalar == 0.7 }

        XCTAssertEqual(store.snapshot.volume.scalar, 0.7)
        XCTAssertEqual(changeCount, 2)

        cancellable.cancel()
        store.stop()
        sleeper.releaseAll()
    }
```

- [ ] **Step 2: Run the test and verify RED**

Run: `swift test --filter SystemStatusStoreTests/testUnchangedVolumeYieldDoesNotRepublishLiveVolume`
Expected: `XCTAssertEqual failed: ("3") is not equal to ("2")` — the equal yield assigns `liveVolume` and `@Published` publishes `objectWillChange` even though the value is identical, so the equal reading adds one emission it should not.

- [ ] **Step 3: Gate the assignment**

```swift
    private func applyVolume(_ value: VolumeStatus) {
        // `liveVolume` drives the popover's volume section through
        // `objectWillChange`, and `publish` only dedupes the snapshot. Writing an
        // unchanged reading here re-rendered every volume observer on every
        // fallback tick, which the equality below stops.
        if value != liveVolume {
            liveVolume = value
        }
        publish(snapshot.replacingVolume(value))
    }
```

`publish(_:)` stays unconditional so a snapshot that differs from `liveVolume` (for example after `setVolume(_:)` wrote both) is still deduped by `lastPublishedSnapshot`.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter SystemStatusStoreTests`
Expected: PASS, including `testSetVolumeUpdatesVisibleVolumeImmediately` and `testLiveVolumeUsesSnapshotWhilePopupSnapshotIsDebounced`, which prove a real change still reaches `liveVolume`, the snapshot and the popup snapshot.

- [ ] **Step 5: Commit**

Run: `git add Sources/StatusTrioCore/Store/SystemStatusStore.swift Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift && git commit -m "fix(store): stop republishing an unchanged live volume"`

---

### Task 6: Release Notes

**Files:**
- Modify: `release-notes/1.3.0/en.md` (append one section after the existing `## Panel opens over full-screen apps` section)
- Modify: `release-notes/1.3.0/zh-Hans.md` (append the matching section)

**Interfaces:**
- Consumes: the behavior from Tasks 1-5.
- Produces: no code. `bash scripts/validate-appcast-notes.sh` reads both files.

- [ ] **Step 1: Prove the notes do not mention the new behaviour yet**

Run: `grep -c "15 seconds" release-notes/1.3.0/en.md; grep -c "15 秒" release-notes/1.3.0/zh-Hans.md`
Expected: `0` and `0`.

- [ ] **Step 2: Add the English section**

```markdown
## Cheaper background refresh
- The fallback refresh — the timer that catches a change the system did not push to the app — now runs every 15 seconds instead of every 5, and macOS may slide that timer so it fires alongside other work. The icon still updates the moment the system reports a change.
- The battery is checked on every fallback tick. Wi-Fi and volume are checked on a slower watchdog while the panel and the Settings window are both closed, and go back to your configured interval as soon as either one is on screen.
- The refresh interval slider still goes down to 5 seconds for anyone who wants the old cadence.
- The volume row no longer redraws the panel when the volume reading has not changed.
```

- [ ] **Step 3: Add the Chinese section**

```markdown
## 更省电的后台刷新
- 兜底刷新（用于捕捉系统没有推送给 App 的变化）由每 5 秒改为每 15 秒一次，macOS 也可以把它与其他任务合并触发。系统推送变化时，图标仍会立即更新。
- 每次兜底刷新仍会检查电池。面板与设置窗口都关闭时，Wi-Fi 与音量改用较慢的看门狗节奏；只要任一界面出现在屏幕上，就恢复为你设定的间隔。
- 刷新间隔滑块仍可调到 5 秒，保留原有节奏。
- 音量读数没有变化时，音量行不再重新渲染面板。
```

- [ ] **Step 4: Re-run the checks**

Run: `grep -c "15 seconds" release-notes/1.3.0/en.md; grep -c "15 秒" release-notes/1.3.0/zh-Hans.md`
Expected: `1` and `1`.
Run: `bash scripts/validate-appcast-notes.sh`
Expected: PASS — both files keep their `# Version %VERSION% (Build %BUILD%)` / `# 版本 %VERSION%（构建 %BUILD%）` heading.

- [ ] **Step 5: Commit**

Run: `git add release-notes/1.3.0/en.md release-notes/1.3.0/zh-Hans.md && git commit -m "docs(release-notes): note the cheaper fallback refresh"`

---

### Task 7: Full Verification

**Files:**
- No production files.

**Interfaces:**
- Consumes: every task above.
- Produces: no code.

- [ ] **Step 1: Run the full suite**

Run: `swift test`
Expected: every test passes; the count is the pre-change count plus the seven tests added here.

- [ ] **Step 2: Run the release build**

Run: `swift build -c release`
Expected: successful build.

- [ ] **Step 3: Run the non-publishing release preflight**

Run:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref <branch> \
  -f version=1.3.0 \
  -f build=12 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: the workflow passes without publishing. This plan changes `@MainActor` state and `deinit`, so this step is mandatory; record the run ID in the commit message or the PR body. If the run fails, append the run ID, failed stage, root cause and fix to `docs/swift-ci-compatibility.md`.

- [ ] **Step 4: Measure the idle cost (required — do this before 1.3.0 is published)**

This is a release requirement, not an optional extra: the release notes already advertise the saving, so an after-change sample must exist before users receive 1.3.0, and both numbers go in the PR body.

The pre-change baseline on record was taken from the **installed 1.2.1 / build 10** bundle, which is a different build from this branch. Use it as context only; it is not a like-for-like comparison.

Build a dev bundle from this branch and launch it. `scripts/build-worktree.sh` derives a bundle id (`com.lingsmbp.StatusTrio.dev.<branch>`) and app name from the branch, so it does not overwrite or collide with the installed app — never install a preflight artifact into `/Applications`.

```bash
# Quit the installed app first: the dev bundle keeps the same executable name
# (`StatusTrio`) and only differs by bundle id, so both can run at once and a
# two-PID expansion makes `top -pid` fail with "invalid option or syntax".
osascript -e 'tell application id "com.lingsmbp.StatusTrio" to quit'
bash scripts/build-worktree.sh release no-open
open dist/StatusTrio.app
top -l 20 -s 1 -pid "$(pgrep -x StatusTrio)" | tail -5
```

Expected: the average CPU, RSS and idle-wakeup numbers are recorded for the after-change sample (and the on-record pre-change numbers are cited alongside them, with their build identity). The change moves the per-tick IOKit, CoreWLAN/`SCDynamicStore` and CoreAudio work from every 5 seconds to every fourth fallback tick while no detail surface is visible; put both numbers in the PR body rather than asserting a target. Quit the dev build when the sample is done.

- [ ] **Step 5: Review the diff**

Run: `git diff --check; git status --short`
Expected: no whitespace errors, and only `SystemStatusStore.swift`, `SettingsStore.swift`, `AppEnvironment.swift`, the two release-note files, and the two test files modified.

## Verification

- `swift test` passes, with the new tests: `testFallbackSleepToleranceCoversTheAdjustableRange`, `testFallbackPollDefaultsToFifteenSeconds`, `testFallbackTickRefreshesBatteryEveryTickAndWiFiAndVolumeOnTheHiddenStride`, `testFallbackTickRefreshesWiFiAndVolumeWhileThePopoverIsOpen`, `testPushedWiFiAndVolumeStillUpdateTheSnapshotWhileThePopoverIsClosed`, `testFallbackTickSkipsWhileTheDisplayIsAsleepAndRefreshesOnDisplayWake`, `testFallbackTickSelfHealsAfterTheDisplayAsleepSkipCap`, `testUnchangedVolumeYieldDoesNotRepublishLiveVolume`.
- `swift build -c release` passes.
- The three interval defaults move together (`SettingsStore.defaultRefreshIntervalSeconds`, `SystemStatusStore.init`, `AppEnvironment.makeStore`), and the two `testMakeStore*` tests that build a store through the factory still pass.
- The updated expectations in `testPeriodicRefreshUsesInjectedSleep`, `testStopPreventsFurtherPeriodicRefresh`, `testWakeNotificationAfterStopDoesNotRefresh`, `testRefreshIntervalDefaultsAndRange` still pin the behaviour they were written for; none of them loses an assertion.
- A non-publishing release preflight passes on the CI toolchain.
- `bash scripts/validate-appcast-notes.sh` passes after the release-note edits.
- Idle CPU is re-measured on this branch's own dev bundle before 1.3.0 is published, with both the before and after numbers recorded in the PR body — the release notes advertise the saving, so this is required evidence, not an optional extra.

## Out of Scope

- **`appIconPlacement` gating the poll.** Every placement renders the same three values into an icon the user can see — `.menuBar` into the menu bar, `.dock`/`.both` into the Dock tile — and both read `store.snapshot`, so hiding the menu bar item cannot justify a staler poll. The store has no placement input today and this plan does not add one.
- **Disabled popover sections gating the poll.** `enabledPopupSections` decides what the *popover body* shows. The same values are drawn into the icon, and this plan already skips the detail-level work while no detail surface is visible, which is the part a disabled section could have saved.
- **Pausing the timer itself while the display is asleep.** That needs a cancel/resume handshake plus a fallback for a missed notification; skipping the work removes the IOKit, CoreWLAN, `SCDynamicStore` and CoreAudio calls, which is where the cost is. The wake-up itself remains.
- **Tolerances for the monitors' own debounce sleeps** (`WiFiMonitor.refreshDebounceInterval`, `VolumeMonitor.refreshDebounceInterval`, `IconRenderCoalescer`) — those are 150 ms and 50 ms coalescers inside a burst, not idle timers.
- **The 2-second icon appearance poll** (`SystemIconAppearanceMonitor`) — separate finding, `docs/superpowers/plans/2026-09-20-appearance-poll-tolerance.md`.
- **Rewording `settings.refreshInterval.description`** ("How often Status Trio checks for changes. Faster updates use more CPU."). The sentence stays accurate for a fallback poll, and a wording change would have to ship in all 12 `.lproj` files, which this plan does not own.
- **Raising the upper bound of `refreshIntervalRange`.** The finding asks for a higher default, not a new maximum; `5...60` is what the slider renders and what `clampedRefreshInterval` pins.

## File Ownership & Conflicts

- `Sources/StatusTrioCore/Store/SystemStatusStore.swift` is also owned by **`2026-09-20-bluetooth-polling-and-lifetime.md`** (R-01: Bluetooth activation/deactivation rules and `deinit` observer leaks). The review index's §3.1 rule is explicit: **this plan lands first**, R-01 rebases and only changes the Bluetooth rules. Do not run the two in parallel.
- `Sources/StatusTrioCore/App/AppEnvironment.swift` is this plan's in Task 2 (`makeStore`'s interval default). R-01's plan records the same assignment, and it also expects **`2026-09-20-wifi-scan-cadence.md`** (R-02) to add a store method to `SystemStatusStore.swift`; if that plan does, land this plan first and let R-01 and R-02 rebase in that order.
- `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift` is touched by this plan and by R-01's Bluetooth activation tests. Land this plan first for the same reason.
- `release-notes/1.3.0/en.md` and `release-notes/1.3.0/zh-Hans.md` are also touched by **`2026-09-20-update-source-fallback-policy.md`** (R-09) and **`2026-09-20-single-instance-and-pasteboard.md`** (R-13). All three only append sections; merge them in any order, but resolve conflicts by keeping every section rather than by taking one side, then re-run `bash scripts/validate-appcast-notes.sh`.
- `Sources/StatusTrioCore/Settings/SettingsStore.swift` and `Tests/StatusTrioCoreTests/SettingsStoreTests.swift` have no other owner in the 2026-09-20 set; no sequencing needed.
- Recommended merge order for the files this plan shares: **R-03 (this plan) → R-01 (Bluetooth) → R-02 (Wi-Fi cadence, if it adds a store method)**, with the release-note-only plans merged at any point.
- This plan does not touch `UI/StatusBarController.swift`, so it has no interaction with **`2026-09-20-toolchain-method-reference-compliance.md`** (R-18).
