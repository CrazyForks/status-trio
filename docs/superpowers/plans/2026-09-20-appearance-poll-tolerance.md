# Appearance Poll Tolerance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `SystemIconAppearanceMonitor` from waking the main run loop 43,200 times a day on a precise 2 s timer: give every armed poll a tolerance the system may coalesce, back the interval off while nothing changes, and keep "a real icon-appearance change is noticed within a bounded time" true and tested against an injected timer instead of a wall-clock sleep.

**Architecture:** Replace `Timer.scheduledTimer(withTimeInterval:repeats:true)` with a one-shot timer that the monitor re-arms, created through an injectable `PollTimerFactory` so tests advance time by firing the armed poll by hand. Each arm carries a tolerance of half its interval; a poll that finds no change doubles the next interval up to `maximumPollingInterval`, while the two existing signals — the `NSWorkspaceIconAppearanceConfigurationDidChangeNotification` observer and `NSApplication.didBecomeActiveNotification` (lines 36-37) — still refresh immediately and reset the cadence to the base interval, so the poll stays the safety net the existing comment (lines 39-41) says it is.

**Tech Stack:** Swift 6-compatible SwiftPM package (`swift-tools-version: 6.0`), AppKit, Foundation `Timer`, Swift Testing (`import Testing`).

**Spec:** Derived from the 2026-09-20 code review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3 (`.github/workflows/release.yml:36`, `.github/workflows/release.yml:39`). The local machine is Xcode 27 / Swift 6.4 — a local build is NOT proof that CI compiles.
- Forbidden in this repo: `isolated deinit`, `weak let`, passing actor-isolated methods directly as function values (use an explicit closure), assuming `Bundle.module` resource/lproj casing. The default `PollTimerFactory` argument in this plan must therefore be written as an explicit closure, never as a bare `SystemIconAppearanceMonitor.makeRunLoopPollTimer` reference.
- The app must build with the macOS 26 SDK or newer; `scripts/build-app.sh` enforces it (`scripts/build-app.sh:65-68`). Do not weaken the SDK guard or `scripts/verify-platform-version.sh`.
- Run `swift test` and `swift build -c release` before committing Swift changes.
- A non-publishing release preflight (`gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false`) is mandatory when a change touches actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources. This plan edits a `@MainActor` class and the timer that calls into it, so the preflight is required before the plan is done.
- Any change to menu bar icon rendering or icon settings MUST be mirrored in the Dock icon in the same change (SettingsStore option derivation, StatusBarController subscriptions, AppIconController subscriptions/state, `DockIconRenderKey` cache inputs, `DockIconRenderer` rendering, and tests covering both menu bar and Dock output). This repo treats that as a hard rule. The monitor feeds the Dock icon's background style only; this plan changes *when* it re-reads, never *what* it reads or what either surface draws, so the rule is covered by the unchanged `SystemIconAppearanceThemeTests` / `DockIconBackgroundResolverTests` suites plus the existing `AppIconControllerTests.reRendersWhenTheSystemIconStyleChanges`.
- Tests are mixed: most use Swift Testing (`import Testing`, `@Test`, `#expect`), some XCTest. Match the file you extend. This plan creates one Swift Testing file and modifies no existing test file.

## Review Focus

- A user changes the macOS "icon & widget style" in System Settings while Status Trio is in the background and the documented notification never arrives: the Dock icon must still catch up, and the plan must be able to say how late it may be. Pinned by `SystemIconAppearanceBackoffTests.aRealChangeIsNoticedWithinTheMaximumNoticeDelay`, which asserts the armed interval against the injected timer instead of sleeping.
- The style change arrives in two stages because the preference is written before the WindowServer configuration updates (the existing comment at `Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift:39-41`): after a reported change the monitor has to go back to the fast cadence instead of staying backed off. Pinned by `SystemIconAppearancePollingTests.aReportedChangeRearmsTheBaseInterval`.
- The user switches back to Status Trio (opens Settings or the menu bar menu) right after changing the style: the appearance must be re-read at once, not up to 10 s later. Pinned by `SystemIconAppearancePollingTests.becomingActiveRearmsTheBaseInterval`.
- A menu bar app that is expected to sit at ~0 % CPU must not hold a precisely-timed wakeup for a cached preferences read. Pinned by `SystemIconAppearancePollingTests.firstPollIsArmedWithAToleranceAndTheBaseInterval`.
- After teardown the monitor must not resurrect itself: a timer callback that is already in flight when `stop()` runs must not report or re-arm, and a second `stop()` — which the lifecycle plan's `deinit` performs after `AppIconController.stop()` — must be a no-op. Pinned by `SystemIconAppearancePollingTests.stopCancelsTheArmedPoll` and `SystemIconAppearancePollingTests.stoppingTwiceIsSafe`.

---

### Task 1: Arm The Poll Through An Injectable, Tolerated Timer

**Files:**
- Modify: `Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift` (lines 4-57: class constants, `init`, `start()`, `stop()`, `refresh()`)
- Test: `Tests/StatusTrioCoreTests/SystemIconAppearancePollingTests.swift` (create)

**Interfaces:**
- Produces: `SystemIconAppearanceMonitor.defaultPollingInterval: TimeInterval` (2), `SystemIconAppearanceMonitor.pollToleranceFraction: Double` (0.5), `SystemIconAppearanceMonitor.maximumPollingInterval: TimeInterval` (10), `SystemIconAppearanceMonitor.maximumNoticeDelay: TimeInterval`.
- Produces: `SystemIconAppearanceMonitor.PollTimerFactory = @MainActor (TimeInterval, TimeInterval, @escaping @MainActor () -> Void) -> Timer`.
- Produces: `SystemIconAppearanceMonitor.makeRunLoopPollTimer(interval:tolerance:action:) -> Timer`.
- Produces: `init(readTheme:notificationCenter:pollingInterval:makePollTimer:)`.
- Produces: `@discardableResult func refresh() -> Bool`.
- Keeps: `didChangeNotificationName`, `onChange`, `start()`, `stop()`, the 2 s default interval and both notification observers (`Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift:36-37`).
- Guarantees: `stop()` stays idempotent and safe to call on a never-started monitor — the lifecycle plan's `deinit` (R-19, which rebases on this plan) forwards to it after `AppIconController.stop()` may already have called it (`Sources/StatusTrioCore/App/AppIconController.swift:119`).
- Consumes: nothing.

- [ ] **Step 1: Write the failing timer tests**

Create `Tests/StatusTrioCoreTests/SystemIconAppearancePollingTests.swift`:

```swift
import AppKit
import Foundation
import Testing
@testable import StatusTrioCore

/// A poll timer the test arms and fires by hand, so nothing here waits on the
/// wall clock.
@MainActor
final class ManualPollTimerFactory {
    struct Arm: Equatable {
        let interval: TimeInterval
        let tolerance: TimeInterval
    }

    private(set) var arms: [Arm] = []
    private var pending: (@MainActor () -> Void)?

    var nextInterval: TimeInterval? { arms.last?.interval }
    var nextTolerance: TimeInterval? { arms.last?.tolerance }

    func makeTimer(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> Timer {
        arms.append(Arm(interval: interval, tolerance: tolerance))
        pending = action
        // A real but unscheduled timer: the monitor only invalidates it, and an
        // unscheduled timer never fires on its own.
        return Timer(timeInterval: interval, repeats: false) { _ in }
    }

    /// Runs the poll the monitor armed last, the way the run loop would.
    func fire() {
        let action = pending
        pending = nil
        action?()
    }
}

@MainActor
struct SystemIconAppearancePollingTests {
    @Test func firstPollIsArmedWithAToleranceAndTheBaseInterval() {
        let timers = ManualPollTimerFactory()
        let harness = PollingHarness(timers: timers)

        harness.monitor.start()

        #expect(timers.arms == [.init(
            interval: SystemIconAppearanceMonitor.defaultPollingInterval,
            tolerance: SystemIconAppearanceMonitor.defaultPollingInterval
                * SystemIconAppearanceMonitor.pollToleranceFraction
        )])
        #expect(
            (timers.nextTolerance ?? 0) > 0,
            "A zero tolerance is a precisely-timed wakeup, which is the whole finding."
        )
    }

    @Test func everyPollRearmsTheTimer() {
        let timers = ManualPollTimerFactory()
        let harness = PollingHarness(timers: timers)
        harness.monitor.start()

        timers.fire()
        timers.fire()

        #expect(timers.arms.count == 3)
        #expect(timers.nextTolerance == timers.nextInterval.map { $0 * 0.5 })
    }

    @Test func stopCancelsTheArmedPoll() {
        let timers = ManualPollTimerFactory()
        let harness = PollingHarness(timers: timers)
        harness.monitor.start()
        timers.fire()
        let armsAfterFirstPoll = timers.arms.count

        harness.monitor.stop()
        harness.theme = SystemIconAppearanceTheme(style: .clear, appearance: .dark)
        timers.fire()

        #expect(timers.arms.count == armsAfterFirstPoll)
        #expect(harness.reported.isEmpty)
    }

    @Test func restartingArmsTheBaseIntervalAgain() {
        let timers = ManualPollTimerFactory()
        let harness = PollingHarness(timers: timers)
        harness.monitor.start()
        timers.fire()

        harness.monitor.stop()
        harness.monitor.start()

        #expect(timers.arms.count == 3)
        #expect(timers.nextInterval == SystemIconAppearanceMonitor.defaultPollingInterval)
    }

    /// The lifecycle plan adds a `deinit` that forwards to `stop()` (R-19), and
    /// `AppIconController.stop()` already calls `stop()` first
    /// (`Sources/StatusTrioCore/App/AppIconController.swift:119`), so the second
    /// call has to be a no-op rather than a crash or a fresh poll.
    @Test func stoppingTwiceIsSafe() {
        let timers = ManualPollTimerFactory()
        let harness = PollingHarness(timers: timers)

        harness.monitor.stop()

        harness.monitor.start()
        timers.fire()
        let armsAfterFirstPoll = timers.arms.count

        harness.monitor.stop()
        harness.monitor.stop()

        #expect(timers.arms.count == armsAfterFirstPoll)
        #expect(harness.reported.isEmpty)
    }

    /// The change notification is the primary signal (`Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift:36`),
    /// so a change it reports has to put the poll back on the fast cadence: the
    /// WindowServer configuration can land after the preference write.
    @Test func aReportedChangeRearmsTheBaseInterval() {
        let timers = ManualPollTimerFactory()
        let harness = PollingHarness(timers: timers)
        harness.monitor.start()
        timers.fire()

        let clearTheme = SystemIconAppearanceTheme(style: .clear, appearance: .dark)
        harness.theme = clearTheme
        harness.center.post(
            name: SystemIconAppearanceMonitor.didChangeNotificationName,
            object: nil
        )

        #expect(harness.reported == [clearTheme])
        #expect(timers.nextInterval == SystemIconAppearanceMonitor.defaultPollingInterval)
    }

    /// `NSApplication.didBecomeActiveNotification` is the other primary signal
    /// (`Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift:37`): a user
    /// coming back to the app must not wait for the safety net.
    @Test func becomingActiveRearmsTheBaseInterval() {
        let timers = ManualPollTimerFactory()
        let harness = PollingHarness(timers: timers)
        harness.monitor.start()
        timers.fire()

        let darkTheme = SystemIconAppearanceTheme(style: .defaultStyle, appearance: .dark)
        harness.theme = darkTheme
        harness.center.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        #expect(harness.reported == [darkTheme])
        #expect(timers.nextInterval == SystemIconAppearanceMonitor.defaultPollingInterval)
    }
}

/// Keeps the monitor, its clock and its reports alive for one test.
@MainActor
private final class PollingHarness {
    let timers: ManualPollTimerFactory
    let center = NotificationCenter()
    var theme = SystemIconAppearanceTheme.default
    var reported: [SystemIconAppearanceTheme] = []
    let monitor: SystemIconAppearanceMonitor

    init(timers: ManualPollTimerFactory) {
        self.timers = timers
        monitor = SystemIconAppearanceMonitor(
            readTheme: { [weak self] in self?.theme ?? .default },
            notificationCenter: center,
            pollingInterval: SystemIconAppearanceMonitor.defaultPollingInterval,
            makePollTimer: { interval, tolerance, action in
                timers.makeTimer(interval: interval, tolerance: tolerance, action: action)
            }
        )
        monitor.onChange = { [weak self] theme in
            self?.reported.append(theme)
        }
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter SystemIconAppearancePollingTests`

Expected: compile failure — `extra argument 'makePollTimer' in call`, `type 'SystemIconAppearanceMonitor' has no member 'defaultPollingInterval'`, `has no member 'pollToleranceFraction'`.

- [ ] **Step 3: Introduce the factory, the tolerance and the one-shot re-arm**

In `Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift`, add the constants after `didChangeNotificationName` (line 10):

```swift
    /// Safety-net cadence while nothing changes. The notification observer and
    /// the activation re-read are the primary signals, so this only has to be
    /// fast enough that a missed change is noticed quickly.
    static let defaultPollingInterval: TimeInterval = 2
    /// Longest a real change may wait when the safety net is the only signal
    /// left. See `maximumNoticeDelay` for the delay a user can actually see.
    static let maximumPollingInterval: TimeInterval = 10
    /// Slack the system may add to a fire so it can coalesce this wakeup with
    /// other work. Zero tolerance is what made this a precisely-timed wakeup.
    static let pollToleranceFraction: Double = 0.5
    /// Worst case from "the preference changed" to "the app noticed" when only
    /// the safety net is left: one full interval plus the slack above it.
    static var maximumNoticeDelay: TimeInterval {
        maximumPollingInterval * (1 + pollToleranceFraction)
    }

    typealias PollTimerFactory = @MainActor (
        _ interval: TimeInterval,
        _ tolerance: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> Timer

    /// The production poll timer: never repeating, because the interval changes
    /// as the monitor backs off or resets.
    static func makeRunLoopPollTimer(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: false) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
```

Change the stored properties (lines 12-17) and the initializer (lines 21-32) to:

```swift
    private let readTheme: () -> SystemIconAppearanceTheme
    private let notificationCenter: NotificationCenter
    private let pollingInterval: TimeInterval
    private let makePollTimer: PollTimerFactory
    private var nextPollingInterval: TimeInterval
    private var lastTheme: SystemIconAppearanceTheme
    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?

    var onChange: ((SystemIconAppearanceTheme) -> Void)?

    init(
        readTheme: @escaping () -> SystemIconAppearanceTheme = {
            SystemIconAppearanceReader.current()
        },
        notificationCenter: NotificationCenter = .default,
        pollingInterval: TimeInterval = SystemIconAppearanceMonitor.defaultPollingInterval,
        // An explicit closure, never a bare method reference: this repo forbids
        // passing actor-isolated methods as function values.
        makePollTimer: @escaping PollTimerFactory = { interval, tolerance, action in
            SystemIconAppearanceMonitor.makeRunLoopPollTimer(
                interval: interval,
                tolerance: tolerance,
                action: action
            )
        }
    ) {
        self.readTheme = readTheme
        self.notificationCenter = notificationCenter
        self.pollingInterval = pollingInterval
        self.makePollTimer = makePollTimer
        self.nextPollingInterval = pollingInterval
        self.lastTheme = readTheme()
    }
```

Replace `start()`, `stop()` and `refresh()` (lines 34-65) with:

```swift
    func start() {
        guard observers.isEmpty, pollTimer == nil else { return }
        observe(Self.didChangeNotificationName)
        observe(NSApplication.didBecomeActiveNotification)

        // The system neither posts a usable change notification nor updates the
        // WindowServer configuration promptly, but it does write the preference
        // right away, so poll it. A cached preferences read is very cheap, and
        // the tolerance below lets the system run it beside another wakeup.
        nextPollingInterval = pollingInterval
        scheduleNextPoll()
    }

    func stop() {
        observers.forEach(notificationCenter.removeObserver)
        observers.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        nextPollingInterval = pollingInterval
    }

    /// Re-reads the system style and reports it when it actually changed.
    ///
    /// - Returns: `true` when the theme changed, so the caller can go back to the
    ///   fast cadence.
    @discardableResult
    func refresh() -> Bool {
        let theme = readTheme()
        guard theme != lastTheme else { return false }
        lastTheme = theme
        onChange?(theme)
        return true
    }

    private func scheduleNextPoll() {
        pollTimer?.invalidate()
        let interval = nextPollingInterval
        pollTimer = makePollTimer(
            interval,
            interval * Self.pollToleranceFraction
        ) { [weak self] in
            self?.pollTimerFired()
        }
    }

    private func pollTimerFired() {
        // A callback that was already in flight when `stop()` ran must not
        // resurrect the poll.
        guard pollTimer != nil else { return }
        pollTimer = nil
        refresh()
        scheduleNextPoll()
    }
```

Rewrite `observe(_:)` (lines 67-77) so a reported change resets the cadence:

```swift
    private func observe(_ name: Notification.Name) {
        observers.append(notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A real change means the preference has moved, so the next poll
                // is worth doing soon; without a change the cadence may keep
                // backing off.
                if refresh() { restartPolling() }
            }
        })
    }

    private func restartPolling() {
        guard pollTimer != nil else { return }
        nextPollingInterval = pollingInterval
        scheduleNextPoll()
    }
```

In this task `pollTimerFired` still re-arms at the unchanged `nextPollingInterval`; the backoff is Task 2.

- [ ] **Step 4: Run the new tests**

Run: `swift test --filter SystemIconAppearancePollingTests`

Expected: PASS (7 tests).

- [ ] **Step 5: Run the existing monitor suite untouched**

Run: `swift test --filter SystemIconAppearanceMonitorTests`

Expected: PASS. That file is owned by the fixed-sleep plan (R-16) and must not be edited here.

If it fails, check first whether the failure predates this change: `git stash` the production edit, run the same filter, and `git stash pop`. A failure caused by this plan is almost certainly a tick-count assertion over a fixed window, because the poll period now grows after each idle fire; the fix is to re-derive that assertion from the armed intervals (or from "a reported change arrives within the bounded delay") while keeping its intent — a stopped monitor must stay silent even while a peer timer is still ticking. Never delete an assertion to make this suite green, and record any edit to that file in the commit message as a deliberate R-16 rebase.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift \
        Tests/StatusTrioCoreTests/SystemIconAppearancePollingTests.swift
git commit -m "perf(appearance): arm the icon-style poll with a tolerance"
```

---

### Task 2: Back Off While Nothing Changes, And Prove The Bound

**Files:**
- Modify: `Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift` (lines 34-125: `start()`, `stop()`, `pollTimerFired()`, `restartPolling()`)
- Test: `Tests/StatusTrioCoreTests/SystemIconAppearancePollingTests.swift` (append suite `SystemIconAppearanceBackoffTests`)

**Interfaces:**
- Produces: the idle backoff `pollingInterval * 2^(idle polls)`, capped at `maximumPollingInterval`, reset by `start()`, `stop()` and every reported change.
- Consumes: `PollTimerFactory` and the one-shot re-arm from Task 1.

- [ ] **Step 1: Write the failing backoff tests**

Append to `Tests/StatusTrioCoreTests/SystemIconAppearancePollingTests.swift`:

```swift
@MainActor
struct SystemIconAppearanceBackoffTests {
    @Test func idlePollsBackOffAndStopAtTheCeiling() {
        let timers = ManualPollTimerFactory()
        let harness = PollingHarness(timers: timers)
        harness.monitor.start()

        for _ in 0..<4 {
            timers.fire()
        }

        #expect(timers.arms.map(\.interval) == [2, 4, 8, 10, 10])
        #expect(timers.arms.allSatisfy {
            $0.interval <= SystemIconAppearanceMonitor.maximumPollingInterval
        })
    }

    /// The safety net is the only signal left when the documented notification
    /// never arrives, so the delay a user can see has to be bounded.
    @Test func aRealChangeIsNoticedWithinTheMaximumNoticeDelay() throws {
        let timers = ManualPollTimerFactory()
        let harness = PollingHarness(timers: timers)
        harness.monitor.start()
        for _ in 0..<3 {
            timers.fire()
        }
        #expect(timers.nextInterval == SystemIconAppearanceMonitor.maximumPollingInterval)

        let armedWhenTheThemeChanged = try #require(timers.nextInterval)
        harness.theme = SystemIconAppearanceTheme(style: .clear, appearance: .dark)
        timers.fire()

        #expect(harness.reported == [harness.theme])
        #expect(
            armedWhenTheThemeChanged
                * (1 + SystemIconAppearanceMonitor.pollToleranceFraction)
                <= SystemIconAppearanceMonitor.maximumNoticeDelay
        )
    }

    @Test func restartingAfterStopStartsFromTheBaseInterval() {
        let timers = ManualPollTimerFactory()
        let harness = PollingHarness(timers: timers)
        harness.monitor.start()
        for _ in 0..<3 {
            timers.fire()
        }
        #expect(timers.nextInterval == SystemIconAppearanceMonitor.maximumPollingInterval)

        harness.monitor.stop()
        harness.monitor.start()

        #expect(timers.nextInterval == SystemIconAppearanceMonitor.defaultPollingInterval)
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter SystemIconAppearanceBackoffTests`

Expected: three failures, all from the missing doubling —
`idlePollsBackOffAndStopAtTheCeiling` sees `[2, 2, 2, 2, 2]` instead of `[2, 4, 8, 10, 10]`; `aRealChangeIsNoticedWithinTheMaximumNoticeDelay` fails at `#expect(timers.nextInterval == SystemIconAppearanceMonitor.maximumPollingInterval)` because three idle polls still leave the interval at 2; `restartingAfterStopStartsFromTheBaseInterval` fails on the same expectation. Record the actual output before continuing.

- [ ] **Step 3: Add the backoff**

In `Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift`, replace `pollTimerFired()` from Task 1 with:

```swift
    private func pollTimerFired() {
        // A callback that was already in flight when `stop()` ran must not
        // resurrect the poll.
        guard pollTimer != nil else { return }
        pollTimer = nil

        let didChange = refresh()

        // Nothing changed: the preference is quiet, so this poll has no reason to
        // keep a precise cadence. A change puts it straight back on the base
        // interval, because the WindowServer configuration can land after the
        // preference write and the next poll is the one that catches it.
        nextPollingInterval = didChange
            ? pollingInterval
            : min(
                nextPollingInterval * 2,
                Self.maximumPollingInterval
            )

        scheduleNextPoll()
    }
```

- [ ] **Step 4: Run the backoff tests**

Run: `swift test --filter SystemIconAppearanceBackoffTests`

Expected: PASS (3 tests).

- [ ] **Step 5: Run both new suites and the existing monitor suite**

Run: `swift test --filter SystemIconAppearancePollingTests`
Run: `swift test --filter SystemIconAppearanceMonitorTests`
Run: `swift test --filter AppIconControllerTests`

Expected: PASS. `AppIconControllerTests.reRendersWhenTheSystemIconStyleChanges` is the Dock-side parity check for this monitor and must pass unchanged.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift \
        Tests/StatusTrioCoreTests/SystemIconAppearancePollingTests.swift
git commit -m "perf(appearance): back the icon-style poll off while nothing changes"
```

---

### Task 3: Full Verification

**Files:**
- No production files.

- [ ] **Step 1: Run the full test suite**

Run: `swift test`

Expected: every test passes, including the two new suites and the untouched `SystemIconAppearanceMonitorTests`.

- [ ] **Step 2: Run the release build**

Run: `swift build -c release`

Expected: successful build against the local SDK.

- [ ] **Step 3: Confirm no new teardown call site and no `deinit` is needed**

Run: `grep -n "monitor.stop()" Sources/StatusTrioCore/App/AppIconController.swift`
Run: `grep -n "appIconController.stop()" Sources/StatusTrioCore/App/AppEnvironment.swift`
Run: `grep -n "environment?.stop()" Sources/StatusTrioCore/App/AppDelegate.swift`

Expected: line 119, line 45, line 27 — the production teardown chain from app termination to `SystemIconAppearanceMonitor.stop()` is already complete, so this plan adds **no** new `stop()` call site.

Do **not** add a `deinit` to `SystemIconAppearanceMonitor` in this plan: the lifecycle plan (R-19, `2026-09-20-icon-parity-and-lifecycle-tests.md`, Task 3) owns that hunk and rebases on top of this one.

**Correction (2026-09-20, after review):** the earlier draft of this note said R-19 adds `deinit { MainActor.assumeIsolated { stop() } }`. That is no longer the design and must not be reintroduced. `MainActor.assumeIsolated` is a fatal assertion rather than a hop, and `deinit` runs on whichever thread releases the last reference, so that shape is the same latent-trap class the `VolumeMonitor` plan (R-06) is removing — and it is banned by the review index §3.4. R-19 instead uses the pattern the repo already sanctions for teardown-owned storage (`SystemStatusStore.swift:32`, `:78-85`): the observer tokens and `pollTimer` are held as `nonisolated(unsafe)` properties, a shared `nonisolated private func tearDownRegistrations()` does the direct cleanup, and both `stop()` and `deinit` call it, with the `AGENTS.md`-required comment stating why the access is safe.

This plan's obligation to R-19 is unchanged and is the reason R-05 must land first: `stop()` has to stay idempotent (pinned by `stoppingTwiceIsSafe`) because `deinit` now calls the same shared teardown function that `stop()` calls, and the one-shot (never repeating) timer introduced here is what makes an owner-less fire harmless — it fires once and is released by the run loop instead of repeating forever.

- [ ] **Step 4: Measure the idle cost before and after**

Run:

```bash
PID="$(pgrep -x StatusTrio)"
top -l 20 -s 1 -pid "$PID" | tail -5
```

Expected: idle CPU stays at the review baseline (0.125 % average, 25 MB RSS). If `powermetrics` is available it can show the per-process wakeups:

```bash
sudo powermetrics --samplers tasks -n 3 -i 2000 | grep -A 4 StatusTrio
```

Expected: the poll's wakeups drop by roughly the backoff factor: the steady-state cadence is 10 s (8,640 arms/day) instead of 2 s (43,200/day), and every arm now carries a tolerance so the system can coalesce it with other work. Record both observations in the commit message or PR body; the deterministic evidence is the armed-interval sequence asserted by `idlePollsBackOffAndStopAtTheCeiling`.

- [ ] **Step 5: Run the non-publishing release preflight**

Run:

```bash
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref "$BRANCH" \
  -f version=1.3.0 \
  -f build=12 \
  -f publish=false

RUN_ID="$(gh run list --repo lingyired/status-trio --workflow release.yml \
  --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$RUN_ID" --repo lingyired/status-trio --exit-status
```

Expected: workflow passes without publishing. This plan edits a `@MainActor` class, so the preflight is not optional.

- [ ] **Step 6: Review the diff**

Run: `git diff --check` and `git status --short`

Expected: no whitespace errors; only `Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift` modified and `Tests/StatusTrioCoreTests/SystemIconAppearancePollingTests.swift` created.

## Verification

- `swift test` (full suite) and `swift build -c release` both pass.
- `swift test --filter SystemIconAppearancePollingTests` and `--filter SystemIconAppearanceBackoffTests` pass; the armed intervals are exactly `[2, 4, 8, 10, 10]` and every arm carries `interval * 0.5` tolerance.
- `swift test --filter SystemIconAppearanceMonitorTests` passes **unmodified** (or, at worst, with the single intent-preserving rebase edit described in Task 1 Step 5) — no existing guarantee was weakened.
- `SystemIconAppearancePollingTests.stoppingTwiceIsSafe` pins the idempotent `stop()` that R-19's `deinit` forwards to.
- `swift test --filter AppIconControllerTests` passes, keeping the Dock-side reaction to a system style change intact.
- The non-publishing release preflight passes (Task 3 Step 5).
- The idle `top` sample (and the `powermetrics` wakeup sample where available) is recorded with the change.

## Out of Scope

- Adding `deinit` to `SystemIconAppearanceMonitor`, or any new `stop()` call site: the chain `AppDelegate.swift:27` -> `AppEnvironment.swift:45` -> `AppIconController.swift:119` already calls `monitor.stop()`, and the `deinit` itself is R-19's Task 3 (it rebases on this plan and relies on the idempotent `stop()` this plan pins).
- The fixed 300-600 ms sleeps in `Tests/StatusTrioCoreTests/SystemIconAppearanceMonitorTests.swift`: owned by the fixed-sleep plan (`2026-09-20-fixed-sleep-test-hardening.md`, finding R-16). Land it first; see Task 1 Step 5 for the only sanctioned rebase edit to that file.
- The `SystemStatusStore` fallback poll's missing tolerance: owned by the status-poll-scheduling plan (`2026-09-20-status-poll-scheduling.md`, finding R-03). Do not copy this change into `SystemStatusStore.swift`.
- Replacing the poll with a preference-change notification, or moving the poll off the main actor: the existing comment (`SystemIconAppearanceMonitor.swift:39-41`) documents why the poll is the safety net, and a `CFPreferencesCopyAppValue` read is not worth a background hop.
- Release notes: the change is invisible to users (same Dock icon, same reaction to a style change), so no `release-notes/1.3.0/*` entry is required.

## File Ownership & Conflicts

- Owned by this plan (per the review index §2, finding R-05): `Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift`, plus the new `Tests/StatusTrioCoreTests/SystemIconAppearancePollingTests.swift`.
- **Conflict with R-16** (`2026-09-20-fixed-sleep-test-hardening.md`): that plan owns `Tests/StatusTrioCoreTests/SystemIconAppearanceMonitorTests.swift`. Land R-16 first (index §3.1), then rebase this plan. The only sanctioned edit to that file here is Task 1 Step 5's re-derivation of an assertion that counted ticks over a fixed window, and only if this plan's growth of the poll period actually breaks it; every assertion must keep its intent.
- **Conflict with R-19** (`2026-09-20-icon-parity-and-lifecycle-tests.md`) on the same production file: R-19's Task 3 adds the `deinit` that forwards to `stop()` and states that R-05 lands first. That order is required, because R-19's `deinit` depends on the idempotent `stop()` this plan pins. This plan adds no `deinit` and no lifecycle test; R-19 owns `IconSurfaceLifetimeTests` and the deallocation coverage.
- `Sources/StatusTrioCore/App/AppIconController.swift`, `Sources/StatusTrioCore/App/AppEnvironment.swift` and `Sources/StatusTrioCore/App/AppDelegate.swift` are **not modified**: no new `stop()` call site is needed. They are quoted in Task 3 Step 3 only to document the existing teardown chain, and no other plan in this set owns them either.
- Relationship to R-03 (`2026-09-20-status-poll-scheduling.md`): that plan adds a tolerance to the `SystemStatusStore` fallback poll. The two files are disjoint and can land in either order, but keep the naming and the "tolerance is a fraction of the interval" convention consistent between them.
- No other plan writes to `Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift`; this plan can land in any wave.
