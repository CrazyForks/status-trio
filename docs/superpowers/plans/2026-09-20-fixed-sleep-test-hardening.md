# Fixed-Sleep Test Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every test that synchronizes with a fixed `Task.sleep` by a bounded wait on the target state, make the two vacuous or near-threshold Dock assertions fail when production regresses, and take the four affected suites off process-global state so a slow or crowded CI run cannot fail them for reasons unrelated to the code under test.

**Architecture:** No production behavior change. `AppIconController` gains one injectable interval so its tests exercise the real debounce without racing it (the default stays `0.5`, so the app's timing is untouched); `MainMenuController` gains two injectable seams (the installed menu and the app's active state) so its tests stop reading and writing `NSApplication.shared`; every rewritten assertion polls with a 5 s cap and reports a named failure when the state never arrives. `BatteryMonitor` is left alone (owned by R-14) and its tests are made provenance-independent instead.

**Tech Stack:** Swift 6.3.3-compatible SwiftPM package, Swift Testing (`import Testing`, `@Test`, `#expect`, `Issue.record`) for the Swift Testing files, XCTest (`XCTAssert*`, `expectation`, `fulfillment(of:timeout:)`) for the XCTest files, Combine, AppKit.

**Spec:** Derived from the 2026-09-20 code review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3; local Xcode 27 / Swift 6.4 compiling is NOT proof. `docs/swift-ci-compatibility.md` lists the concrete failures this caused.
- Forbidden in this repo: `isolated deinit`, enabling `IsolatedDeinit`, `weak let` (use `weak var`), passing actor-isolated methods directly as function values (use an explicit closure), assuming `Bundle.module` casing.
- Run `swift test` and `swift build -c release` before committing Swift changes. A non-publishing release preflight (`gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false`, then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`) is mandatory for changes touching actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources.
- Every failed CI run must be recorded in `docs/swift-ci-compatibility.md` with run ID, failed stage, root cause, fix and verification.
- Any change to menu bar icon rendering or icon settings must be mirrored in the Dock icon in the same change, and covered by tests for both outputs.
- Tests are mixed: most use Swift Testing (`import Testing`, `@Test`, `#expect`, `@MainActor` suites), some XCTest (`XCTAssert*`, `XCTSkipUnless`). Match the file you extend.
- Every rewrite in this plan must make the suite **stricter**, never looser. For each rewritten test the task states the production regression it now catches; a step that only makes a test faster is not acceptable.
- Bounded waits use a 5 s cap, polling every 5 ms, and fail by name — the rule recorded in `docs/swift-ci-compatibility.md` lines 21-23 and 259-260 after runs `35293247382` and `35316867111`. A test that parks until the whole-run timeout turns a failure into a CI hang.
- XCTest classes cannot use Swift Testing's `@Suite(.serialized)`. Where serialization is unavailable, the plan says so and does something else instead of pretending.

## Review Focus

- A user dragging a Dock icon setting must still see the Dock icon follow the debounce: `AppIconControllerTests.visibleDockRendersStatusChanges` injects a 10 ms debounce interval and waits for `renderCount == 1` with a 5 s cap, so a crowded CI main actor no longer fails a correct build — the exact flake recorded as run `35447521372`. The production interval is unchanged at `AppIconController.snapshotDebounceInterval` (`0.5`), so the shipped timing is not part of the test's shortcut.
- A user who placed the icon in the menu bar only must never get a Dock tile: `AppIconControllerTests.hiddenDockDoesNotRenderStatusChanges` first proves the debounce chain delivers for the very same store and publish path (visible Dock, injected 10 ms interval, one render required), then hides the tile and asserts `renderCount == 0` over a bounded window, then shows the tile again and asserts a render for the same snapshot. The first phase rules out "the debounce never fired" and the last rules out "the render path is broken", so the negative assertion can no longer hold for the wrong reason.
- A user whose system icon style changes (clear/tinted, dark/light) must see the icon catch up, and must stop seeing polls after teardown: `SystemIconAppearanceMonitorTests.pollsUntilStopped` waits on reported themes with a 5 s cap and proves the run loop is still servicing timers of the same period before accepting the post-`stop()` silence, so "no report" can no longer mean "the timer never ran at all".
- A user switching the app language must see the menu bar rebuild in that language: `MainMenuControllerTests.testInstallsLocalizedMenuAndRebuildsAfterLanguageChange` polls the target titles instead of sleeping 100 ms, and the suite renders into an injected menu sink, so it can no longer read or clear the process-global `NSApplication.shared.mainMenu` that another suite may be using.
- A user plugging in the charger must see the battery update, and no read may follow teardown: `BatteryMonitorTests.testRecoverReinstallsNotificationsAndKeepsStreamAlive` and `testPowerStateNotificationRefreshesUntilStopped` capture a read-count baseline, wait up to 5 s for a read *past* that baseline, and pair it with an inverted expectation after `stop()`; the pair is what keeps the negative assertion non-vacuous while the notification center stays process-global.

## Verified defects (re-verified at review revision `13cdbbc`; do not re-derive)

| Site | Defect |
| --- | --- |
| `Tests/StatusTrioCoreTests/AppIconControllerTests.swift:142` | `try await Task.sleep(for: .milliseconds(900))` against `AppIconController.snapshotDebounceInterval = 0.5` (`Sources/StatusTrioCore/App/AppIconController.swift:26`) — only a 1.8× margin; this is the test that flaked in CI run `35447521372`. |
| `Tests/StatusTrioCoreTests/AppIconControllerTests.swift:154` | same 900 ms sleep, and `#expect(harness.log.renderCount == 0)` passes both when the Dock is suppressed and when the debounce never fired — a vacuous negative. |
| `Tests/StatusTrioCoreTests/SystemIconAppearanceMonitorTests.swift:77` | 600 ms sleep around a 50 ms injected poller (`pollingInterval: 0.05`, :68) — 12 ticks expected from a fixed wait. |
| `Tests/StatusTrioCoreTests/SystemIconAppearanceMonitorTests.swift:83` | 300 ms sleep to assert silence after `stop()` — 6 ticks expected from a fixed wait, and "silence" also holds when the timer never ran. |
| `Tests/StatusTrioCoreTests/MainMenuControllerTests.swift:26` | 100 ms sleep for a `Task { @MainActor in install() }` hop (`Sources/StatusTrioCore/UI/MainMenuController.swift:49-55`). |
| `Tests/StatusTrioCoreTests/MainMenuControllerTests.swift:48,60,64,81,84,87,90,112` | assertions against the process-global `NSApplication.shared.mainMenu`; the suite also clears it in `stop()` (`MainMenuController.swift:80`), and `start()` reads the process-global `NSApplication.shared.isActive` (:31). |
| `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift:276,282,373,382` | posts on the process-global `NotificationCenter.default` and asserts exact read counts (`readCount == 3`, `== 2`) after a 1 s `fulfillment` timeout, while other tests observe the same notification name. |
| `grep -rn "\.serialized" Tests/` | no output: nothing in the suite opts out of parallel execution, and CI does not pass `--no-parallel`. |

---

### Task 1: Make The Two Dock Debounce Tests Deterministic And Non-Vacuous

**Files:**
- Modify: `Sources/StatusTrioCore/App/AppIconController.swift`
- Modify: `Tests/StatusTrioCoreTests/AppIconControllerTests.swift`

**Interfaces:**
- Produces: `AppIconController.init(..., snapshotDebounceInterval: TimeInterval = Self.snapshotDebounceInterval, ...)` — the interval is now injected instead of read from the static constant at the call site, so a test can shrink it without changing the shipped default of `0.5`.
- Produces: `AppIconControllerHarness.init(initialPlacement:acceptsActivationPolicy:systemTheme:isDarkAppearance:notificationCenter:snapshotDebounceInterval:)`, forwarding the interval.
- Produces: one local async helper in `AppIconControllerTests`, `waitUntil(_ description:timeout:_:)`, replacing `waitForCoalescedRenders(until:timeout:)` at :416.
- Consumes: `AppIconControllerHarness` (:430) and its `publishDifferentSnapshot()` (:509), `log.renderCount` (:532), `settings` (already exposed) and `notificationCenter` initializer parameter.

- [ ] **Step 1: Write the stricter tests (expected RED: the harness has no `snapshotDebounceInterval` parameter yet)**

Rewrite the two tests and the helper in `Tests/StatusTrioCoreTests/AppIconControllerTests.swift`:

```swift
    /// The Dock tile must both follow a status change and stay quiet while it is
    /// hidden. The three phases are one test on purpose: the first proves the
    /// debounce subscription delivers for this store and publish path, the second
    /// asserts suppression, and the third proves the render path itself works, so
    /// the negative assertion cannot hold because nothing happened at all.
    @Test func hiddenDockDoesNotRenderStatusChanges() async throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            notificationCenter: NotificationCenter(),
            snapshotDebounceInterval: 0.01
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        #expect(harness.activationPolicy.isRegularApp, "phase 1 needs the Dock tile visible")

        // Phase 1: the debounce chain delivers and the tile is drawn. The reset
        // matters: start() already drew the tile once, so without it the wait
        // below could succeed on that first render instead of on the debounce.
        harness.log.reset()
        harness.publishSnapshot(percentage: 42)
        try await waitUntil("the first Dock icon render") { harness.log.renderCount == 1 }

        // Phase 2: the same chain, with the tile hidden, must not draw. The
        // percentage differs from phase 1 on purpose: `subscribeToSnapshot()`
        // drops duplicate statuses with removeDuplicates(), so re-publishing 42
        // would never reach the debounce and the negative assertion below would
        // pass for exactly the reason this test exists to rule out.
        harness.settings.appIconPlacement = .menuBar
        harness.log.reset()
        harness.publishSnapshot(percentage: 43)
        try await expectNoRender(harness, over: 0.2)

        #expect(harness.activationPolicy.isRegularApp == false)
        #expect(harness.log.renderCount == 0)

        // Phase 3: the render path is still alive, so phase 2 was suppression
        // and not a broken renderer.
        harness.settings.appIconPlacement = .dock
        #expect(harness.log.renderCount == 1)
    }

    @Test func visibleDockRendersStatusChanges() async throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            notificationCenter: NotificationCenter(),
            snapshotDebounceInterval: 0.01
        )
        defer { harness.cleanUp() }
        harness.controller.start()
        #expect(harness.activationPolicy.isRegularApp, "the Dock tile must be visible for this test")
        harness.log.reset()

        harness.publishSnapshot(percentage: 42)
        try await waitUntil("the Dock icon render") { harness.log.renderCount == 1 }

        #expect(harness.log.renderCount == 1)
    }

    /// Waits for the target state instead of sleeping a fixed interval.
    ///
    /// Every test in the run starts at once, so the main actor can stay busy for
    /// longer than a debounce or coalescing interval before the work gets to run.
    /// A fixed wait that is generous locally is not on CI.
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("\(description) did not happen within \(timeout) seconds.")
    }

    /// Waits out `duration` while letting the main actor and the run loop run,
    /// and records a failure only if a render happened.
    ///
    /// The injected debounce interval is 10 ms, so 200 ms is twenty intervals:
    /// anything the snapshot subscription was going to deliver has arrived.
    private func expectNoRender(
        _ harness: AppIconControllerHarness,
        over duration: TimeInterval
    ) async throws {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
            if harness.log.renderCount > 0 {
                Issue.record("the hidden Dock tile drew \(harness.log.renderCount) time(s); expected none")
                return
            }
        }
    }
```

Update the four existing call sites (`:191`, `:236`, `:252`, `:291`) to the new helper signature, for example `try await waitUntil("the coalesced redraw") { harness.log.renderCount == 1 }`, and delete `waitForCoalescedRenders` at :416. Add the `snapshotDebounceInterval` parameter to `AppIconControllerHarness` (:430) and store it for the controller construction:

```swift
    private let snapshotDebounceInterval: TimeInterval

    init(
        initialPlacement: AppIconPlacement = .menuBar,
        acceptsActivationPolicy: Bool = true,
        systemTheme: @escaping () -> SystemIconAppearanceTheme = { .default },
        isDarkAppearance: Bool = false,
        notificationCenter: NotificationCenter = .default,
        snapshotDebounceInterval: TimeInterval = AppIconController.snapshotDebounceInterval
    ) throws {
```

and pass `snapshotDebounceInterval: snapshotDebounceInterval` to the `AppIconController(...)` construction at :478-504. Give the harness a value-parameterized publish so the second phase can send a *different* status:

```swift
    func publishSnapshot(percentage: Int) {
        battery.send(BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        ))
    }

    func publishDifferentSnapshot() { publishSnapshot(percentage: 42) }
```

Keep `publishDifferentSnapshot()` as the wrapper (`:509`): the two rewritten tests are its only callers today (`:141`, `:153`), so either form works, but the wrapper keeps the diff to those two tests minimal.

- [ ] **Step 2: Run the tests and record the expected RED**

Run: `swift test --filter AppIconControllerTests`
Expected: compile failure — `extra argument 'snapshotDebounceInterval' in call` at the harness construction.

- [ ] **Step 3: Inject the interval in `AppIconController`**

In `Sources/StatusTrioCore/App/AppIconController.swift`, add the stored property next to `renderCoalescer` (:40) and an initializer parameter after `notificationCenter`:

```swift
    private let snapshotDebounceInterval: TimeInterval
```

```swift
        notificationCenter: NotificationCenter = .default,
        snapshotDebounceInterval: TimeInterval = Self.snapshotDebounceInterval
    ) {
```

Assign it in the initializer body (`self.snapshotDebounceInterval = snapshotDebounceInterval`) and use it in `subscribeToSnapshot()` (:148-161):

```swift
            .debounce(
                for: .seconds(snapshotDebounceInterval),
                scheduler: RunLoop.main
            )
```

The default is `Self.snapshotDebounceInterval` (`0.5`), so the app keeps the shipped timing and `AppIconController.snapshotDebounceInterval` stays the single documented value; the parameter exists so a test can shrink the window instead of racing it.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter AppIconControllerTests`
Expected: PASS, including the other Dock tests that use the new helper.

- [ ] **Step 5: Prove the rewritten assertions can fail**

Temporarily edit only the test file: change the phase-2 placement in `hiddenDockDoesNotRenderStatusChanges` from `.menuBar` to `.dock`.

Run: `swift test --filter AppIconControllerTests/hiddenDockDoesNotRenderStatusChanges`
Expected: FAIL with `the hidden Dock tile drew 1 time(s); expected none`. Revert the edit.

Temporarily change the phase-1 expectation in the same test to `harness.log.renderCount == 2`.

Run: `swift test --filter AppIconControllerTests/hiddenDockDoesNotRenderStatusChanges`
Expected: FAIL with `the first Dock icon render did not happen within 5.0 seconds`. Revert the edit.

Then temporarily delete the `guard isDockTileVisible else { return }` line at the top of `renderLatestDockIcon()` (:214) to prove the negative assertion catches a real production regression.

Run: `swift test --filter AppIconControllerTests/hiddenDockDoesNotRenderStatusChanges`
Expected: FAIL with `the hidden Dock tile drew 1 time(s); expected none`. Restore the guard; `Sources/StatusTrioCore/App/AppIconController.swift` must differ from `HEAD` only by the injected interval before the commit.

These mutation checks are what proves the phases are real; do not commit any of them.

- [ ] **Step 6: Commit**

```bash
swift build
git add Sources/StatusTrioCore/App/AppIconController.swift Tests/StatusTrioCoreTests/AppIconControllerTests.swift
git commit -m "test(dock): exercise the icon debounce instead of sleeping 900 ms

The two Dock tests synchronized with a fixed 900 ms sleep against a 0.5 s
debounce; one of them flaked in CI run 35447521372 and the other asserted
renderCount == 0 in a way that also passed when the debounce never fired.

AppIconController takes the debounce interval as an initializer parameter
(defaulting to the shipped 0.5 s). The tests inject 10 ms, prove the debounce
chain delivers while the tile is visible, assert suppression while it is
hidden, and prove the render path still works afterwards."
```

---

### Task 2: Replace The Appearance-Monitor Sleeps With A Bounded Wait And A Peer-Timer Proof

**Files:**
- Modify: `Tests/StatusTrioCoreTests/SystemIconAppearanceMonitorTests.swift`

**Interfaces:**
- Consumes: `SystemIconAppearanceMonitor(readTheme:notificationCenter:pollingInterval:)` and `onChange` (`Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift:21-43`).
- Produces: one local helper `waitUntil(_ description:timeout:_:)` in this file, using `Issue.record` (Swift Testing).

- [ ] **Step 1: Rewrite `pollsUntilStopped` (expected RED: none — the production behavior is correct; Step 4 proves the test has teeth)**

Replace the body of `pollsUntilStopped` (:58-85):

```swift
    @Test func pollsUntilStopped() async throws {
        let center = NotificationCenter()
        var theme = SystemIconAppearanceTheme.default
        let readTheme = { theme }
        let monitor = SystemIconAppearanceMonitor(
            readTheme: readTheme,
            notificationCenter: center,
            pollingInterval: 0.05
        )
        var reported: [SystemIconAppearanceTheme] = []
        monitor.onChange = { reported.append($0) }
        monitor.start()

        let clearTheme = SystemIconAppearanceTheme(style: .clear, appearance: .dark)
        theme = clearTheme
        try await waitUntil("the first polled theme") { reported == [clearTheme] }

        // A second distinct value proves polling continues rather than having
        // reported once and stopped.
        let tintedTheme = SystemIconAppearanceTheme(style: .tinted, appearance: .light)
        theme = tintedTheme
        try await waitUntil("the second polled theme") { reported == [clearTheme, tintedTheme] }

        monitor.stop()
        theme = SystemIconAppearanceTheme(style: .defaultStyle, appearance: .light)

        // A peer monitor with the same period runs on the same run loop. Every
        // time it reports, a 50 ms timer demonstrably ticked; a stopped monitor
        // whose timer was never invalidated would have ticked in the same window
        // and reported the new theme. Waiting for two of its reports covers at
        // least two full periods, so the window cannot be shorter than one tick.
        let peer = SystemIconAppearanceMonitor(
            readTheme: readTheme,
            notificationCenter: center,
            pollingInterval: 0.05
        )
        var peerReported: [SystemIconAppearanceTheme] = []
        peer.onChange = { peerReported.append($0) }
        peer.start()
        defer { peer.stop() }
        try await waitUntil("the peer monitor's first tick") { peerReported.count >= 1 }
        theme = SystemIconAppearanceTheme(style: .bold, appearance: .dark)
        try await waitUntil("the peer monitor's second tick") { peerReported.count >= 2 }

        #expect(
            reported == [clearTheme, tintedTheme],
            "a stopped monitor must not report, even with its timer peer still ticking"
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("\(description) did not happen within \(timeout) seconds.")
    }
```

`SystemIconAppearanceTheme(style:appearance:)` is the value type used by the rest of this file (`:34`, `:53`, `:79`); `.bold` is used only here as a fourth distinct pair and may be replaced by any `.defaultStyle`/`.tinted` combination that is not equal to the two earlier values.

- [ ] **Step 3: Run the test**

Run: `swift test --filter SystemIconAppearanceMonitorTests`
Expected: PASS. The three other tests in the file (`reportsOnlyRealThemeChanges`, `reReadsWhenTheAppBecomesActive`, `stopsReportingAfterStop`) are unchanged.

- [ ] **Step 4: Prove the post-`stop()` assertion has teeth**

Temporarily comment out `pollTimer?.invalidate()` and `pollTimer = nil` in `stop()` (`Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift:47-52`).

Run: `swift test --filter SystemIconAppearanceMonitorTests`
Expected: FAIL with `a stopped monitor must not report, even with its timer peer still ticking`. Revert the edit — the production file must be byte-identical to `HEAD` before the commit, because it is owned by R-05 (`2026-09-20-appearance-poll-tolerance.md`).

- [ ] **Step 5: Commit**

```bash
git add Tests/StatusTrioCoreTests/SystemIconAppearanceMonitorTests.swift
git commit -m "test(appearance): bound the poll waits and prove the stopped timer is silent

The test slept 600 ms for a 50 ms poller and 300 ms to assert silence after
stop(), so it both flaked under load and could pass when the timer never ran.
It now waits on the reported themes with a 5 s cap, proves polling continues
with a second distinct theme, and uses a peer monitor with the same period to
prove the run loop is still ticking before accepting the silence."
```

---

### Task 3: Take The Menu Controller Tests Off The Process-Global Menu

**Files:**
- Modify: `Sources/StatusTrioCore/UI/MainMenuController.swift`
- Modify: `Tests/StatusTrioCoreTests/MainMenuControllerTests.swift`

**Interfaces:**
- Produces: `@MainActor protocol MainMenuInstalling: AnyObject { var installedMainMenu: NSMenu? { get set } }` with `extension NSApplication: MainMenuInstalling`.
- Produces: `MainMenuController.init(activationPolicy:localization:notificationCenter:mainMenuInstaller:isApplicationActive:openSettings:)`, where the two new parameters default to `NSApplication.shared` and `{ NSApplication.shared.isActive }`.
- Consumes: the existing `AppActivationPolicy`, `Localization` and `NotificationCenter` injections used by `makeStartedController` (`Tests/StatusTrioCoreTests/MainMenuControllerTests.swift:92-108`).

- [ ] **Step 1: Write the injected-menu tests (expected RED: the new parameters do not exist)**

Add to `MainMenuControllerTests`:

```swift
    private func makeSpyInstaller() -> MainMenuInstallerSpy { MainMenuInstallerSpy() }
```

and change `makeStartedController` to render into the spy and to take the active state from the test:

```swift
    private func makeStartedController(
        _ environment: (localization: Localization, cleanUp: () -> Void),
        installer: MainMenuInstallerSpy = MainMenuInstallerSpy(),
        isApplicationActive: @escaping () -> Bool = { false },
        openSettings: @escaping () -> Void = {}
    ) -> (controller: MainMenuController, policy: AppActivationPolicy, installer: MainMenuInstallerSpy) {
        let notificationCenter = NotificationCenter()
        let policy = AppActivationPolicy(application: MainMenuActivationSpy())
        policy.enterTemporaryRegularMode()
        let controller = MainMenuController(
            activationPolicy: policy,
            localization: environment.localization,
            notificationCenter: notificationCenter,
            mainMenuInstaller: installer,
            isApplicationActive: isApplicationActive,
            openSettings: openSettings
        )
        controller.start()
        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        return (controller, policy, installer)
    }
```

Add the spy and rewrite `appMenuTitles()` to read it:

```swift
@MainActor
private final class MainMenuInstallerSpy: MainMenuInstalling {
    private(set) var installCount = 0

    var installedMainMenu: NSMenu? {
        didSet { installCount += 1 }
    }
}
```

```swift
    private func appMenuTitles(_ installer: MainMenuInstallerSpy) throws -> [String] {
        let appMenu = try XCTUnwrap(installer.installedMainMenu?.items.first?.submenu)
        return appMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
    }
```

Update the four tests to pass the installer through (`testInstallsLocalizedMenuAndRebuildsAfterLanguageChange`, `testSettingsMenuItemInvokesTheHandler`, `testStopRemovesTheMenu`, `testInstallsTheMenuOnlyWhileTheAppIsRegularAndActive`) and to assert on `installer.installedMainMenu` instead of `NSApplication.shared.mainMenu`. For the last one, drive the transitions from a test-owned `var isActive = false` passed as `isApplicationActive: { isActive }`, so the baseline and the notification-driven changes both come from the test rather than from the process:

- [ ] **Step 2: Run the tests and record the expected RED**

Run: `swift test --filter MainMenuControllerTests`
Expected: compile failure — `extra argument 'mainMenuInstaller' in call` and `cannot find 'MainMenuInstalling' in scope`.

- [ ] **Step 3: Add the two seams to `MainMenuController`**

```swift
@MainActor
protocol MainMenuInstalling: AnyObject {
    var installedMainMenu: NSMenu? { get set }
}

extension NSApplication: MainMenuInstalling {
    var installedMainMenu: NSMenu? {
        get { mainMenu }
        set { mainMenu = newValue }
    }
}
```

In the controller, replace the two `NSApplication.shared.mainMenu` assignments (`:71`, `:80`) and the `isActive` read (`:31`):

```swift
    private let mainMenuInstaller: any MainMenuInstalling
    private let isApplicationActive: () -> Bool

    init(
        activationPolicy: AppActivationPolicy,
        localization: Localization,
        notificationCenter: NotificationCenter = .default,
        mainMenuInstaller: any MainMenuInstalling = NSApplication.shared,
        isApplicationActive: @escaping () -> Bool = { NSApplication.shared.isActive },
        openSettings: @escaping () -> Void
    ) {
```

`install()` becomes `mainMenuInstaller.installedMainMenu = AppMainMenu.make(...)`, `setInstalled(false)` becomes `mainMenuInstaller.installedMainMenu = nil`, and `start()` becomes `isAppActive = isApplicationActive()`. The `= NSApplication.shared` / `{ NSApplication.shared.isActive }` defaults are what `AppEnvironment.swift:126` relies on; they must stay, because the app's real wiring is only exercised by the app itself.

- [ ] **Step 4: Replace the 100 ms sleep with a bounded wait on the target titles**

```swift
    func testInstallsLocalizedMenuAndRebuildsAfterLanguageChange() async throws {
        let environment = try makeEnvironment()
        defer { environment.cleanUp() }
        let harness = makeStartedController(environment)
        defer { harness.controller.stop() }

        XCTAssertEqual(
            try appMenuTitles(harness.installer),
            [
                "About \(AppMetadata.name)",
                "Settings…",
                "Hide \(AppMetadata.name)",
                "Hide Others",
                "Show All",
                "Quit Status Trio"
            ]
        )

        environment.localization.setPreference(.language(.simplifiedChinese))

        let expectedChinese = [
            "关于 \(AppMetadata.name)",
            "设置…",
            "隐藏 \(AppMetadata.name)",
            "隐藏其他",
            "显示全部",
            "退出 Status Trio"
        ]
        try await waitUntilMenuTitles(expectedChinese, installer: harness.installer)

        XCTAssertEqual(try appMenuTitles(harness.installer), expectedChinese)
    }

    /// The rebuild runs on the next main-actor turn (`MainMenuController.start()`
    /// hops through `Task { @MainActor in install() }`), so wait for the target
    /// state with a 5 s cap instead of sleeping a fixed 100 ms.
    private func waitUntilMenuTitles(
        _ expected: [String],
        installer: MainMenuInstallerSpy,
        timeout: TimeInterval = 5
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? appMenuTitles(installer)) == expected { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The menu did not rebuild within \(timeout) seconds; last titles: \((try? appMenuTitles(installer)) ?? [])")
    }
```

- [ ] **Step 5: Run the tests and confirm no global menu access remains**

Run: `swift test --filter MainMenuControllerTests`
Expected: PASS.

Run: `grep -n "NSApplication.shared.mainMenu" Tests/StatusTrioCoreTests/MainMenuControllerTests.swift`
Expected: no output. If any line remains, the suite can still clobber the menu other suites see; convert it to the installer first.

- [ ] **Step 6: Commit**

```bash
swift build
git add Sources/StatusTrioCore/UI/MainMenuController.swift Tests/StatusTrioCoreTests/MainMenuControllerTests.swift
git commit -m "test(menu): inject the installed menu and the active state

MainMenuControllerTests asserted against NSApplication.shared.mainMenu while
clearing it on stop(), and start() read the process-global isActive, so any
concurrent suite could change what these tests observe. The controller now
takes the installer and the active-state probe as injectable dependencies
(defaulting to NSApplication.shared for the app), and the language-rebuild
test waits for the target titles instead of sleeping 100 ms."
```

---

### Task 4: Make The Battery Notification Tests Independent Of Other Posters

**Files:**
- Modify: `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift`

**Interfaces:**
- Consumes: `BatteryMonitor(reader:lowPowerModeProvider:iopsRunLoopSourceFactory:)` (`Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift:101-118`), which registers its low-power observer on `NotificationCenter.default` (`:178`).
- Produces: no new API. `FakeBatteryReader` (:482) and its `onReadCount` hook (:485) already provide the baseline-relative probe.

- [ ] **Step 1: Rewrite `testRecoverReinstallsNotificationsAndKeepsStreamAlive` (:243) to be baseline-relative**

Replace the exact-count coupling (`reader.onReadCount = { if count == 3 { ... } }` at :271, `timeout: 1` at :280, `XCTAssertEqual(reader.readCount, 3)` at :282):

```swift
        let readsBeforeNotification = reader.readCount
        let lowPowerStateRead = expectation(description: "low power state read")
        var hasFulfilled = false
        reader.onReadCount = { _ in
            guard !hasFulfilled, reader.readCount > readsBeforeNotification else { return }
            hasFulfilled = true
            lowPowerStateRead.fulfill()
        }
        NotificationCenter.default.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        await fulfillment(of: [lowPowerStateRead], timeout: 5)

        XCTAssertGreaterThan(
            reader.readCount,
            readsBeforeNotification,
            "a power-state notification must trigger a read even after recover()"
        )
        monitor.stop()
```

`NotificationCenter.default` is process-global and `BatteryMonitor` hard-codes it, so a read count is not exclusively ours: capturing the baseline immediately before the post and waiting for the first read past it asserts the behavior without depending on how many reads another test's notification caused. The 5 s timeout replaces the 1 s one for the reason recorded in `docs/swift-ci-compatibility.md` lines 21-23.

- [ ] **Step 2: Rewrite `testPowerStateNotificationRefreshesUntilStopped` (:351) the same way, with a paired negative**

Replace :360-382:

```swift
        XCTAssertEqual(reader.readCount, 1)

        let readsBeforeNotification = reader.readCount
        let powerStateRead = expectation(description: "power state read")
        var hasFulfilled = false
        reader.onReadCount = { _ in
            guard !hasFulfilled, reader.readCount > readsBeforeNotification else { return }
            hasFulfilled = true
            powerStateRead.fulfill()
        }
        NotificationCenter.default.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        await fulfillment(of: [powerStateRead], timeout: 5)
        XCTAssertGreaterThan(reader.readCount, readsBeforeNotification)

        monitor.stop()
        let readsAtStop = reader.readCount
        let noReadAfterStop = expectation(description: "no read after stop")
        noReadAfterStop.isInverted = true
        reader.onReadCount = { _ in
            guard reader.readCount > readsAtStop else { return }
            noReadAfterStop.fulfill()
        }
        NotificationCenter.default.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        await drainMainActorTasks()
        await fulfillment(of: [noReadAfterStop], timeout: 0.5)

        XCTAssertEqual(reader.readCount, readsAtStop)
```

The inverted expectation follows the existing idiom at `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift:843-859`, and it is only meaningful because the same probe just proved it can fire: the positive half fulfills on the first read past the baseline, the negative half asserts none follows the stop.

- [ ] **Step 3: Run the rewritten tests**

Run: `swift test --filter BatteryMonitorTests/testRecoverReinstallsNotificationsAndKeepsStreamAlive`
Run: `swift test --filter BatteryMonitorTests/testPowerStateNotificationRefreshesUntilStopped`
Expected: both PASS.

- [ ] **Step 4: Prove the negative half has teeth**

Temporarily move the second `NotificationCenter.default.post` in `testPowerStateNotificationRefreshesUntilStopped` to *before* `monitor.stop()` and keep the inverted expectation where it is.

Run: `swift test --filter BatteryMonitorTests/testPowerStateNotificationRefreshesUntilStopped`
Expected: FAIL on `noReadAfterStop` (it fulfills, and an inverted expectation that fulfills fails). Revert the edit.

- [ ] **Step 5: Commit**

```bash
swift build
git add Tests/StatusTrioCoreTests/BatteryMonitorTests.swift
git commit -m "test(battery): assert the power-state notification without exact read counts

Both tests posted .NSProcessInfoPowerStateDidChange on the shared
NotificationCenter.default and then asserted exact read counts, so any
concurrent poster changed the number they expected. They now capture a
baseline, wait up to 5 s for the first read past it, and pair that positive
with an inverted no-read-after-stop expectation."
```

---

### Task 5: Full Verification, Preflight And CI Record

**Files:**
- Modify: `docs/swift-ci-compatibility.md` (only if the preflight fails)

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: acceptance evidence on the CI toolchain.

- [ ] **Step 1: Run the full suite**

Run: `swift test`
Expected: PASS with no test taking longer than the 5 s cap; a name in a failure message (`... did not happen within 5.0 seconds`) identifies which wait timed out.

- [ ] **Step 2: Run the release build**

Run: `swift build -c release`
Expected: PASS.

- [ ] **Step 3: Confirm the sleeps that were synchronization are gone**

Run: `grep -rn "Task.sleep" Tests/StatusTrioCoreTests/AppIconControllerTests.swift Tests/StatusTrioCoreTests/SystemIconAppearanceMonitorTests.swift Tests/StatusTrioCoreTests/MainMenuControllerTests.swift Tests/StatusTrioCoreTests/BatteryMonitorTests.swift`
Expected: only the 5 ms poll inside each `waitUntil` helper. Any remaining `Task.sleep(for: .milliseconds(` with a value of 100 or more is a missed synchronization.

- [ ] **Step 4: Run the non-publishing preflight**

```bash
git push -u origin test/fixed-sleep-test-hardening

gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref test/fixed-sleep-test-hardening \
  -f version=1.3.0 \
  -f build=14 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

`build=14` keeps the build number above the published appcast (9) and above the `build=13` this plan's sibling uses. Expected: `Run tests`, the release build, packaging and artifact upload succeed, and nothing is published.

- [ ] **Step 5: Record the run**

If the preflight fails, append a row to the failure table in `docs/swift-ci-compatibility.md` in the format required by its "失败记录规则" section (lines 44-54): run ID, failed stage, root cause, fix, follow-up verification. If it passes, add a short subsection next to the other preflight records (for example the `issue #48` entry at lines 275-284) stating the run ID, the test counts, that the branch changes no production behavior except three injectable seams (`snapshotDebounceInterval`, `mainMenuInstaller`, `isApplicationActive`, all defaulted to the shipped behavior), and that no release was published.

- [ ] **Step 6: Commit the record**

```bash
git add docs/swift-ci-compatibility.md
git commit -m "docs: record the fixed-sleep hardening preflight

Non-publishing preflight on test/fixed-sleep-test-hardening: the four
hardened suites and the full test run pass on macos-26 / Xcode 26.6 /
Swift 6.3.3, with no release published."
```

---

## Verification

- `swift test` passes, and each hardened test fails with a named message when its behavior is broken (Steps 5, 4 and 4 of Tasks 1, 2 and 4 record the exact mutations and the exact expected failures).
- `swift build -c release` passes.
- `grep -rn "Task.sleep" Tests/StatusTrioCoreTests/{AppIconControllerTests,SystemIconAppearanceMonitorTests,MainMenuControllerTests,BatteryMonitorTests}.swift` finds only 5 ms polls inside wait helpers.
- `grep -n "NSApplication.shared.mainMenu" Tests/StatusTrioCoreTests/MainMenuControllerTests.swift` finds nothing.
- `grep -c "reader.readCount, [0-9]" Tests/StatusTrioCoreTests/BatteryMonitorTests.swift` returns `0` for the two rewritten tests.
- The non-publishing preflight on `test/fixed-sleep-test-hardening` passes, and `docs/swift-ci-compatibility.md` records the run ID and outcome.

## Out of Scope

- `Monitoring/BatteryMonitor.swift` itself. Injecting its notification center is the cleaner long-term fix, but that file belongs to R-14 (`2026-09-20-battery-callback-teardown-investigation.md`) and the review index fixes the order (R-16 first, then R-14). If R-14 lands the injection, these two tests can switch to a private center; nothing here blocks that.
- `App/SystemIconAppearanceMonitor.swift`. Its timer change (interval tolerance) belongs to R-05 (`2026-09-20-appearance-poll-tolerance.md`); the mutation check in Task 2 is reverted before the commit and the file must be byte-identical to `HEAD`.
- The remaining `Task.sleep` uses in `BluetoothBatteryLevelHandoffTests`, `BatteryDetailsLayoutTests`, `BluetoothSummaryLayoutTests`, `BatteryDetailsTests`, `BluetoothPairedDeviceListTests`, `BluetoothBatteryControllerTests`, `SystemStatusStoreTests` and `WiFiClassifierTests`: they are either bounded poll bodies, injected-clock plumbing (`ManualEventSleeper.sleep` at `ManualEventSleeper.swift:39`, `ManualSleeper` at `SystemStatusStoreTests.swift:1032`, `WiFiClassifierTests.swift:1265,1269`), or sub-50 ms yields inside a probe. This plan only rewrites sleeps that are used as synchronization for a production interval.
- Adding `@Suite(.serialized)` anywhere: the four suites here are XCTest or take an injected center, and serialization only orders Swift Testing suites against each other, so it would not have fixed the cross-framework interference seen in run `35447521372`.
- Snapshot/golden-file testing; the repo deliberately avoids it.
- Release notes: no user-visible change.

## File Ownership & Conflicts

Owned by this plan:

| File | Change |
| --- | --- |
| `Tests/StatusTrioCoreTests/AppIconControllerTests.swift` | two tests + one wait helper |
| `Sources/StatusTrioCore/App/AppIconController.swift` | injectable `snapshotDebounceInterval` (default `0.5`) |
| `Tests/StatusTrioCoreTests/SystemIconAppearanceMonitorTests.swift` | one test + one wait helper |
| `Tests/StatusTrioCoreTests/MainMenuControllerTests.swift` | four tests, helper, spy |
| `Sources/StatusTrioCore/UI/MainMenuController.swift` | `MainMenuInstalling` + two injected dependencies |
| `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift` | two tests |
| `docs/swift-ci-compatibility.md` | one record entry |

Conflicts and sequencing:

- `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift` is shared with R-14, and `Tests/StatusTrioCoreTests/SystemIconAppearanceMonitorTests.swift` is shared with R-05. The review index (section 3.1) fixes the order: **this plan lands first** in both cases. Do not start R-05 or R-14 until this branch is merged.
- This plan takes ownership of `Sources/StatusTrioCore/App/AppIconController.swift` (R-16) and `Sources/StatusTrioCore/UI/MainMenuController.swift`, which the review index does not assign to any plan. All three additions are injectable seams defaulted to the shipped behavior: no debounce interval change, no render decision, and no user-visible menu behavior change. `docs/superpowers/plans/2026-09-20-icon-parity-and-lifecycle-tests.md` (R-19) must rebase on this branch, because it may want lifetime seams in `AppIconController` and in `SystemIconAppearanceMonitor`, which `AppIconController` owns; sequence R-19 after this plan.
- `docs/superpowers/plans/2026-09-20-toolchain-method-reference-compliance.md` (R-18) lands first on `Sources/StatusTrioCore/UI/StatusBarController.swift`, which this plan does not touch.
- `docs/swift-ci-compatibility.md` is also written by `2026-09-20-toolchain-method-reference-compliance.md` and by every plan whose preflight fails. Merge entries as separate subsections; do not renumber the existing table.
- This plan does not touch `Sources/StatusTrioCore/UI/StatusBarController.swift`; its ownership belongs to R-18 and R-07.
