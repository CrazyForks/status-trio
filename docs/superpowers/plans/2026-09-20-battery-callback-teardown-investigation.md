# Battery Callback Teardown Investigation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decide, with reproducible evidence, whether `BatteryMonitor` can release its IOPS callback context while the run-loop callback is still reading it — and apply the minimal teardown-affinity fix only if the hazard is confirmed. A documented "cannot reproduce" is an acceptable outcome; speculative synchronization is not.

**Architecture:** This is an investigation, so production code stays frozen until the evidence is in. `BatteryMonitor` hands `BatteryCallbackContext` to the C callback as an **unretained** pointer: the box is created with `Unmanaged.passRetained` (`Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift:155`), read through `takeUnretainedValue()` (`:160-162`), and released exactly once in `deinit` (`:133`) or in `teardownNotifications()` (`:242`). IOPS delivers that callback on the **main run loop** (the source is added at `:171`), and removing a run-loop source (`:127`) does not stop a callback that is already executing — so a release that happens on another thread while the main run loop is inside the callback is a use-after-free by construction. The investigation therefore needs (a) a harness that keeps only the raw pointer, so an over-release is observable at all — the existing `IOPSNotificationSourceHarness` deliberately retains the context (`Tests/StatusTrioCoreTests/BatteryMonitorTests.swift:526-532`), which masks the bug — and (b) a deterministic test that blocks the main thread in a semaphore while another thread performs the last release, which makes the teardown thread an assertion instead of a race. Thread Sanitizer is the empirical second half. If the hazard is confirmed, the minimal fix carries the three teardown-owned values to the main actor in one `@unchecked Sendable` box, so the last release happens on the same thread that runs every callback and the two can no longer interleave.

**Tech Stack:** Swift 6 SwiftPM package, XCTest, Dispatch (`DispatchQueue`, `DispatchSemaphore`, `NSLock`), CoreFoundation run loops, IOKit.ps, Thread Sanitizer via `swift test --sanitize=thread`.

**Spec:** Derived from the 2026-09-20 code review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md (finding **R-14**, severity C6 Medium).

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3. The local machine is Xcode 27 / Swift 6.4 — a local build is NOT proof that CI compiles.
- Forbidden in this repo: `isolated deinit`, enabling `IsolatedDeinit`, `weak let` (use `weak var`), passing actor-isolated methods directly as function values (use an explicit closure), assuming `Bundle.module` casing. `docs/swift-ci-compatibility.md` records CI failures caused by each of these; read it before you start.
- Run `swift test` and `swift build -c release` before committing Swift changes.
- These plans touch actors/`deinit`, so a non-publishing release preflight is mandatory **if any production file changes**: `gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false` then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`.
- Every failed CI run must be recorded in `docs/swift-ci-compatibility.md` (run ID, failed stage, root cause, fix, verification).
- Tests are mixed: most use Swift Testing (`import Testing`, `@Test`, `#expect`), some XCTest. Match the file you extend. In this repo 22 of 89 test files use Swift Testing, and `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift` is XCTest (`:1-5`) — the new file must be XCTest too, and it must follow that file's harness style.
- `nonisolated(unsafe)` is allowed only for teardown-owned storage, and the reason must be stated next to the declaration. `BatteryMonitor.swift:105-107` currently carries three such declarations without a stated reason; this plan adds the reason in the same commit as any fix, and does not touch them otherwise.
- Do not duplicate the sibling plan: `Sources/StatusTrioCore/Monitoring/ReadWatchdog.swift` and `VolumeMonitor.deinit` belong to `2026-09-20-volume-monitor-main-actor-io.md`. Nothing in this plan touches `VolumeMonitor.swift`, `WiFiMonitor.swift` or their tests.
- No speculative synchronization: no locks, atomics, `os_unfair_lock`, `DispatchQueue.sync` barriers or retry loops are added to the callback path by this plan. If the hazard is not confirmed, the deliverable is the document, not a diff.
- Thread Sanitizer runs are diagnostic only and must not be wired into CI: `swift test --sanitize=thread` is 5–15× slower and rebuilds every dependency, and this suite contains AppKit/UI tests whose TSan noise is out of scope.

## Review Focus

- **Releasing the last `SystemStatusStore` reference off the main thread while a power-source notification fires.** `SystemStatusStore.deinit` (`Sources/StatusTrioCore/Store/SystemStatusStore.swift:78-85`) does not call `stop()`, so `batteryMonitor` (`:18`) is released on whatever thread drops the store, and `BatteryMonitor.deinit` (`BatteryMonitor.swift:125-136`) then releases the context (`:133`) while the main run loop may be inside the callback (`:158-167`). Pinned by `testOffMainReleaseRunsTeardownOnTheMainActor` and `testCallbackExecutingWhileTheLastReferenceIsReleasedOffMain`.
- **Unplugging the power adapter at the moment the app tears down.** The IOPS notification and the release race each other; the user sees a crash on quit or on the next popover open, with no reproducer. Pinned by the same two tests, which is why one of them is statistical and must be run under TSan.
- **A "fix" that breaks the normal power-source path.** The percentage, charging and low-power-mode updates all flow through the same source and callback. Pinned by `BatteryMonitorTests.testIOPSNotificationCallbackRefreshesUntilStopped` (`:310-349`) and `testPowerStateNotificationRefreshesUntilStopped` (`:351-383`), which must stay green.
- **A teardown that runs twice.** `stop()`/`recover()` release the context in `teardownNotifications()` (`:232-245`) and `deinit` releases it again only when `stop()` never ran; a fix that defers the release must not double-release, which would itself be a use-after-free. Pinned by `testStartAndStopAreIdempotent` (`:286-308`), `testRecoverReinstallsNotificationsAndKeepsStreamAlive` (`:243-284`) and `testDeinitRemovesSourceWhenStopWasNotCalled` (`:446-465`).
- **A harness that hides the bug.** The existing harness retains the context (`:526-532`), so no test written against it can ever observe the over-release; the new harness must keep only the pointer, and its ability to observe the release is itself asserted. Pinned by the post-teardown `weakContext` assertion in `testOffMainReleaseRunsTeardownOnTheMainActor`.

---

### Task 1: Build the non-retaining harness and the deterministic contract test

**Files:**
- Create: `Tests/StatusTrioCoreTests/BatteryCallbackTeardownTests.swift`
- Read (do not modify): `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift`

**Interfaces:**
- Consumes: `IOPSRunLoopSourceFactory` (`BatteryMonitor.swift:25-28`), `BatteryMonitor.init(reader:lowPowerModeProvider:iopsRunLoopSourceFactory:)` (`:110-123`), `BatteryMonitoring` (`Sources/StatusTrioCore/Monitoring/MonitorProtocols.swift`).
- Produces: test-only `NonRetainingIOPSNotificationSourceHarness`, `RetainedReference`, `LockedFlag`, and a private `FakeBatteryReader` / `makeReading(percentage:)` pair, because the ones in `BatteryMonitorTests.swift` are file-private (`:482-496`, `:467-475`).
- Produces: the contract the fix must satisfy — `deinit` must not remove the run-loop source or release the callback context on the releasing thread.

- [ ] **Step 1: Create the new test file with the harness and the contract test**

```swift
import Foundation
import IOKit.ps
import XCTest
@testable import StatusTrioCore

/// The IOPS callback context is handed to the C callback as an unretained
/// pointer (`BatteryMonitor.swift:155-167`), so this suite must not add a second
/// owner: `IOPSNotificationSourceHarness` in BatteryMonitorTests.swift retains the
/// context (`:526-532`) and therefore cannot observe an over-release. This harness
/// keeps only the raw pointer, exactly like the run-loop source does.
@MainActor
final class BatteryCallbackTeardownTests: XCTestCase {
    func testOffMainReleaseRunsTeardownOnTheMainActor() async {
        let harness = NonRetainingIOPSNotificationSourceHarness()
        var monitor: BatteryMonitor? = BatteryMonitor(
            reader: FakeBatteryReader(result: makeReading(percentage: 50)),
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: harness.factory
        )
        monitor?.start()
        guard let contextPointer = harness.contextPointer else {
            XCTFail("The monitor must install a callback context")
            return
        }
        // Weak on purpose: reading it after teardown proves the release happened.
        weak var weakContext: AnyObject? = Unmanaged<AnyObject>
            .fromOpaque(contextPointer)
            .takeUnretainedValue()
        XCTAssertNotNil(weakContext)
        XCTAssertTrue(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))

        let reference = RetainedReference(monitor!)
        monitor = nil

        // The main thread is parked in `wait`, so the main actor cannot run a
        // deferred teardown while the releasing thread observes the state. That is
        // what makes this test an assertion instead of a race.
        let sourceStillInstalled = LockedFlag()
        let workerFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            reference.release()
            sourceStillInstalled.set(
                CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode)
            )
            workerFinished.signal()
        }
        guard workerFinished.wait(timeout: .now() + 5) == .success else {
            XCTFail("The releasing thread must finish")
            return
        }

        XCTAssertTrue(
            sourceStillInstalled.value,
            "deinit must not remove the run-loop source on the releasing thread: IOPS invokes the callback on the main run loop"
        )
        XCTAssertNotNil(
            weakContext,
            "deinit must not release the callback context on the releasing thread: the callback reads it with takeUnretainedValue()"
        )

        // After the main actor drains, the deferred teardown must have run exactly
        // once: the source is gone and the context is deallocated.
        await Task { @MainActor in }.value
        XCTAssertFalse(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))
        XCTAssertNil(weakContext)
    }
}

/// Installs a real `CFRunLoopSource` and keeps only the context pointer and the
/// C callback, so `BatteryMonitor`'s `passRetained`/`release` pair stays balanced
/// without a second owner.
private final class NonRetainingIOPSNotificationSourceHarness {
    let source: CFRunLoopSource
    private(set) var callback: IOPSNotificationCallback?
    private(set) var contextPointer: UnsafeMutableRawPointer?
    private(set) var factoryInvocationCount = 0

    var factory: IOPSRunLoopSourceFactory {
        { [self] contextPointer, callback in
            factoryInvocationCount += 1
            self.contextPointer = contextPointer
            self.callback = callback
            return source
        }
    }

    init() {
        var sourceContext = CFRunLoopSourceContext(
            version: 0,
            info: nil,
            retain: nil,
            release: nil,
            copyDescription: nil,
            equal: nil,
            hash: nil,
            schedule: nil,
            cancel: nil,
            perform: nil
        )
        source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &sourceContext)!
    }

    /// Invokes the production C callback with the context pointer, the way the
    /// main run loop does. Used only by the TSan stress test.
    func invokeCallback() {
        callback?(contextPointer)
    }
}

/// Carries one retained reference to another thread so a test can choose the
/// thread that performs the last release.
private final class RetainedReference: @unchecked Sendable {
    private let unmanaged: Unmanaged<AnyObject>

    init(_ object: AnyObject) {
        unmanaged = Unmanaged.passRetained(object)
    }

    func release() {
        unmanaged.release()
    }
}

/// Thread-safe single-value box for observations made on the releasing thread.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool { lock.withLock { storage } }
    func set(_ newValue: Bool) { lock.withLock { storage = newValue } }
}

private final class FakeBatteryReader: BatteryReadingProviding {
    var result: BatteryReading?
    private(set) var readCount = 0

    init(result: BatteryReading?) {
        self.result = result
    }

    func read() -> BatteryReading? {
        readCount += 1
        return result
    }
}

private func makeReading(percentage: Int) -> BatteryReading {
    BatteryReading(
        currentCapacity: percentage,
        maxCapacity: 100,
        isCharging: false,
        isConnectedToPower: false,
        isPresent: true
    )
}
```

- [ ] **Step 2: Run it and record the RED**

Run: `swift test --filter BatteryCallbackTeardownTests/testOffMainReleaseRunsTeardownOnTheMainActor`
Expected: FAIL. `sourceStillInstalled.value` is `false` because `deinit` runs `CFRunLoopRemoveSource(CFRunLoopGetMain(), …)` at `BatteryMonitor.swift:127` on the releasing thread, and the `weakContext` assertion fails because `deinit` released the context at `:133` on the same thread. If the test instead crashes inside `CFRunLoopRemoveSource`, that is the same evidence (a CoreFoundation call made from a thread that does not own the run loop); record which of the two you observed, plus the exact assertion or frame, in `docs/battery-callback-teardown.md`.

- [ ] **Step 3: Confirm the surrounding behaviour is unchanged**

Run: `swift test --filter BatteryMonitorTests`
Expected: PASS. This task adds a file only; nothing in `BatteryMonitor.swift` changes yet.

- [ ] **Step 4: Commit the harness and the failing test**

```bash
git add Tests/StatusTrioCoreTests/BatteryCallbackTeardownTests.swift
git commit -m "test(battery): add a non-retaining IOPS callback teardown harness"
```

The knowingly failing assertion is temporary by design: Task 3 decides whether Task 4 turns it green or deletes it. Do not merge this commit on its own.

---

### Task 2: Look for the race under Thread Sanitizer

**Files:**
- Modify: `Tests/StatusTrioCoreTests/BatteryCallbackTeardownTests.swift`

**Interfaces:**
- Consumes: Task 1's `NonRetainingIOPSNotificationSourceHarness.invokeCallback()`, `RetainedReference`.
- Produces: `testCallbackExecutingWhileTheLastReferenceIsReleasedOffMain` — the empirical half of the evidence.

- [ ] **Step 1: Add the stress test**

```swift
    /// Statistical, not deterministic: the production callback body is short, so
    /// this test maximizes the number of interleavings instead of forcing one.
    /// Its value is the Thread Sanitizer report it can produce, not its assertions.
    func testCallbackExecutingWhileTheLastReferenceIsReleasedOffMain() async {
        for _ in 0..<250 {
            let harness = NonRetainingIOPSNotificationSourceHarness()
            var monitor: BatteryMonitor? = BatteryMonitor(
                reader: FakeBatteryReader(result: makeReading(percentage: 50)),
                lowPowerModeProvider: { false },
                iopsRunLoopSourceFactory: harness.factory
            )
            monitor?.start()
            guard harness.contextPointer != nil else {
                XCTFail("The monitor must install a callback context")
                return
            }
            let reference = RetainedReference(monitor!)
            monitor = nil

            let released = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                reference.release()
                released.signal()
            }
            // The callback body dereferences the context with takeUnretainedValue()
            // while the releasing thread is inside deinit.
            harness.invokeCallback()
            guard released.wait(timeout: .now() + 5) == .success else {
                XCTFail("The releasing thread must finish")
                return
            }

            // Let a deferred main-actor teardown run before the next iteration.
            await Task { @MainActor in }.value
        }
    }
```

- [ ] **Step 2: Run it under TSan and capture the log**

Run:

```bash
TSAN_OPTIONS=halt_on_error=1 swift test --sanitize=thread \
  --scratch-path /tmp/st-tsan \
  --filter BatteryCallbackTeardownTests 2>&1 | tee /tmp/st-tsan.log
```

Expected: the run is slow (a full TSan rebuild plus 250 iterations) and exits non-zero **if** the race is observed; grep the log for `ThreadSanitizer` / `heap-use-after-free`. Record the outcome verbatim in the doc, including a clean run: `grep -c "ThreadSanitizer" /tmp/st-tsan.log` returning `0` is a finding, not a failure to investigate. If `halt_on_error` is not honoured on this runner, the report still lands in the log — judge by the log, not by the exit code.

- [ ] **Step 3: Sanity-check that TSan is actually watching**

Run: `swift test --sanitize=thread --scratch-path /tmp/st-tsan --filter BatteryCallbackTeardownTests/testOffMainReleaseRunsTeardownOnTheMainActor`
Expected: the same deterministic failure as Task 1 Step 2, proving the filtered TSan build compiles and runs the suite. A clean stress run from Step 2 only means something if this step shows TSan is running at all.

- [ ] **Step 4: Run the ordinary suite to prove nothing was broken**

Run: `swift test --filter BatteryCallbackTeardownTests`
Expected: only `testOffMainReleaseRunsTeardownOnTheMainActor` fails (the known RED); the stress test itself must not crash or hang outside TSan.

- [ ] **Step 5: Commit**

```bash
git add Tests/StatusTrioCoreTests/BatteryCallbackTeardownTests.swift
git commit -m "test(battery): stress the callback against an off-main last release"
```

---

### Task 3: Record the evidence and decide

**Files:**
- Create: `docs/battery-callback-teardown.md`
- Read: `docs/fullscreen-popover-investigation.md` (structure and tone), `docs/swift-ci-compatibility.md` (the failure-record rules)

**Interfaces:**
- Consumes: Task 1's deterministic result, Task 2's TSan log and outcome.
- Produces: the decision (fix / no fix) that Task 4 acts on, with the evidence attached.

- [ ] **Step 1: Write the document**

Create `docs/battery-callback-teardown.md` following the shape of `docs/fullscreen-popover-investigation.md` (Chinese headings, code and commands in English). Required sections and content:

- `# IOPS 回调上下文与 deinit 的释放竞态（复审 C6）` — state the status line (`状态：**已确认（按构造成立）/ 未能复现**`) with the verdict.
- `## 现象` — what a user would see: a crash on quit or on the next popover open, with no console log, when the last `SystemStatusStore` reference is released off the main thread (`SystemStatusStore.swift:78-85`) while a power-source notification is in flight.
- `## 代码路径` — the exact lines: `BatteryMonitor.swift:155` (`passRetained`), `:160-162` (`takeUnretainedValue`), `:171` (source added to the main run loop), `:127` and `:133` (`deinit` removal and release), `:232-245` (`stop()`/`recover()` path), and the note that removing a run-loop source does not stop a callback that is already executing.
- `## 决定性证据` — the deterministic result from Task 1 Step 2: the exact command, the observed outcome (`sourceStillInstalled` and the `weakContext` assertion, or the CoreFoundation frame if it crashed), and the file:line that produced it.
- `## Thread Sanitizer` — the exact command from Task 2 Step 2, `grep -c "ThreadSanitizer" /tmp/st-tsan.log`, the report text if any (verbatim), the iteration count (250), and an explicit statement when the answer is "no report observed".
- `## 结论` — the decision table below, with the row that applies.
- `## 修复` — only when a fix lands: what changed, why it is minimal, and the regression test name.
- `## 残余风险` — the honesty section: what the fix does *not* prove (e.g. the deferred teardown cannot run if the process exits first, and `deinit` still reads teardown-owned storage from the releasing thread; that storage is only values, never shared state).

Decision table to apply verbatim:

| Deterministic contract test (Task 1) | TSan stress (Task 2) | Verdict | Action |
| --- | --- | --- | --- |
| RED: teardown observed off-main | report | Confirmed, reproduced | Task 4 fix + regression test + preflight |
| RED: teardown observed off-main | no report | Confirmed by construction, crash not reproduced | Task 4 fix + regression test + preflight, and record the negative TSan result |
| GREEN | no report | Cannot reproduce | **No code change.** Delete the contract test, keep this document, close the finding with the negative result recorded |

- [ ] **Step 2: Cross-check the negative path**

If the verdict is "cannot reproduce", the document must say what would change it: the hazard needs a non-main release of the last `SystemStatusStore`/`BatteryMonitor` reference *and* a callback in flight; the repo has neither today (the app calls `environment.stop()` → `store.stop()` → `batteryMonitor.stop()` at `AppEnvironment.swift:47` and `SystemStatusStore.swift:168`, and every callback capture in the store is `[weak self]`). Say so explicitly, and say that no synchronization was added because no evidence supported it.

- [ ] **Step 3: Commit the document**

```bash
git add docs/battery-callback-teardown.md
git commit -m "docs: record the IOPS callback teardown investigation"
```

---

### Task 4: Apply the minimal main-actor teardown (only for the "confirmed" rows)

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift`
- Modify: `Tests/StatusTrioCoreTests/BatteryCallbackTeardownTests.swift`

**Interfaces:**
- Consumes: Task 3's decision, Task 1's contract test.
- Produces: `nonisolated deinit` that hands `runLoopSource`, `lowPowerObserver` and `callbackContext` to the main actor in one `@unchecked Sendable` box; `stop()`/`recover()` semantics unchanged.

- [ ] **Step 1: Add the hand-off box next to `BatteryCallbackContext`**

```swift
/// Carries `deinit`-time teardown to the main actor. `@unchecked Sendable`: each
/// value is handed over exactly once, is not touched again by the releasing
/// thread, and is only used from the main actor afterwards.
///
/// Why the main actor: IOPS invokes the callback on the main run loop
/// (`installNotifications()` adds the source with `CFRunLoopGetMain()`), and the
/// callback reads `callbackContext` with `takeUnretainedValue()`. Releasing the
/// box on the main actor makes the last release and every read happen on the same
/// thread, so they cannot interleave — which is exactly what the off-main release
/// in `deinit` could not guarantee.
private struct BatteryTeardown: @unchecked Sendable {
    let runLoopSource: CFRunLoopSource?
    let lowPowerObserver: NSObjectProtocol?
    let callbackContext: Unmanaged<BatteryCallbackContext>?

    var hasWork: Bool {
        runLoopSource != nil || lowPowerObserver != nil || callbackContext != nil
    }

    @MainActor
    func run() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
        }
        callbackContext?.release()
    }
}
```

- [ ] **Step 2: Rewrite `deinit`, and state why the teardown-owned storage is safe**

Replace `deinit` (`:125-136`) with:

```swift
    deinit {
        // `deinit` is nonisolated and may run on any thread that releases the last
        // reference. Only thread-safe work happens here; everything that touches
        // the main run loop or the callback context is handed to the main actor,
        // where the IOPS callback also runs. `continuation.finish()` is thread-safe.
        continuation.finish()
        let teardown = BatteryTeardown(
            runLoopSource: runLoopSource,
            lowPowerObserver: lowPowerObserver,
            callbackContext: callbackContext
        )
        guard teardown.hasWork else { return }
        Task { @MainActor in
            teardown.run()
        }
    }
```

Extend the storage declarations (`:105-107`) with the required reason, leaving the annotations in place:

```swift
    /// `nonisolated(unsafe)`: teardown-owned. Written only on the main actor while
    /// the monitor is running, read by `deinit` (any thread) and then handed to
    /// `BatteryTeardown` exactly once. Nothing else touches them off the main actor.
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var lowPowerObserver: NSObjectProtocol?
    nonisolated(unsafe) private var callbackContext: Unmanaged<BatteryCallbackContext>?
```

Safety argument to keep in the code review thread: `stop()`/`recover()` still run `teardownNotifications()` on the main actor and nil the three fields (`:232-245`), so `deinit`'s box is empty after a normal stop and the context is never released twice; and between `deinit` and the deferred `run()` the box stays alive because the `Task` captures it, so a callback that is still in flight reads a live box whose `monitor` weak reference is already `nil` (`:163`) and returns without refreshing.

- [ ] **Step 3: Reject the alternatives in one line each (record in the doc)**

- *Release the box after `CFRunLoopSourceInvalidate`.* Rejected: invalidation does not wait for a callback that has already started, so the window stays open, and there is no local evidence about its off-thread guarantees.
- *Let the callback own a strong reference.* Rejected: the callback fires repeatedly; a retained value per invocation has no matching release that does not free the box on the first call.
- *Lock the callback path.* Rejected: it adds synchronization where the real defect is thread affinity, and it does not make the run-loop source removal legal.

- [ ] **Step 4: Turn the contract test green and pin the release**

Task 1's test already asserts the post-fix behaviour; add the explicit release check at the end of the test body:

```swift
        await Task { @MainActor in }.value
        XCTAssertFalse(
            CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode),
            "The deferred teardown must remove the source on the main actor"
        )
        XCTAssertNil(weakContext, "The deferred teardown must release the callback context exactly once")
```

- [ ] **Step 5: Run the battery suites**

Run: `swift test --filter BatteryCallbackTeardownTests`
Expected: PASS, including the stress test.

Run: `swift test --filter BatteryMonitorTests`
Expected: PASS — `testDeinitRemovesSourceWhenStopWasNotCalled` (`:446-465`) still ends with the source removed, now after the main actor has drained, and `testStartAndStopAreIdempotent` (`:286`) still sees a single release.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift Tests/StatusTrioCoreTests/BatteryCallbackTeardownTests.swift
git commit -m "fix(battery): hand IOPS teardown to the main actor"
```

---

### Task 5: Verification (only when a production file changed)

**Files:**
- No production files.

- [ ] **Step 1: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 2: Run the release build**

Run: `swift build -c release`
Expected: successful build against the macOS 26-or-newer SDK.

- [ ] **Step 3: Re-run the sanitizer**

Run:

```bash
TSAN_OPTIONS=halt_on_error=1 swift test --sanitize=thread \
  --scratch-path /tmp/st-tsan \
  --filter BatteryCallbackTeardownTests 2>&1 | tee /tmp/st-tsan-after.log
```

Expected: no `ThreadSanitizer` report. Append both logs' verdicts to `docs/battery-callback-teardown.md`.

- [ ] **Step 4: Run the non-publishing release preflight**

Run:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref fix/battery-callback-teardown \
  -f version=1.3.0 \
  -f build=12 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: passes without publishing. The fix touches `deinit` and `@MainActor`, so this preflight is the acceptance gate.

- [ ] **Step 5: Record the preflight**

Append the run to `docs/swift-ci-compatibility.md` using the document's existing per-run convention (run ID, stage results, version/build, publication status). If a stage fails, record run ID, failed stage, root cause, fix and the verification run — never "passed after a rerun" alone.

- [ ] **Step 6: Commit**

```bash
git add docs/battery-callback-teardown.md docs/swift-ci-compatibility.md
git commit -m "docs: record the battery callback teardown fix and its preflight"
```

## Verification

- [ ] The decision in `docs/battery-callback-teardown.md` names one row of the decision table, and the evidence behind it (command, observed outcome) is in the same document.
- [ ] Either `Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift` is unchanged and no test is left knowingly failing, or the fix is in with `swift test` green.
- [ ] If the fix landed: `swift test`, `swift build -c release`, the TSan re-run, and the non-publishing preflight all pass, and the preflight run ID is recorded in `docs/swift-ci-compatibility.md`.
- [ ] `grep -n "BatteryTeardown\|assumeIsolated\|NSLock\|os_unfair" Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift` shows the hand-off box and no lock, no `MainActor.assumeIsolated`, and no new synchronization primitive.
- [ ] `git diff --stat` touches only the files listed in File Ownership, and `git diff --check` reports no whitespace errors.
- [ ] No `isolated deinit`, no `weak let`, and no actor-isolated method passed as a function value anywhere in the diff.
- [ ] If the verdict is "cannot reproduce": the contract test is deleted, `swift test --filter BatteryCallbackTeardownTests` passes or the file is removed, and the document states what future change would require re-opening the investigation.

## Out of Scope

- **`ReadWatchdog` and `VolumeMonitor.deinit`.** Both belong to `2026-09-20-volume-monitor-main-actor-io.md`; do not duplicate that work here, and do not cite this plan's TSan runs as evidence for it.
- **`SystemStatusStore.deinit` calling `stop()`.** `Sources/StatusTrioCore/Store/SystemStatusStore.swift` is owned by R-01/R-03 (Bluetooth polling, poll scheduling). Adding a `stop()` call there would remove one trigger for this race, but it is a different subsystem and a different plan; record it as an option in the document instead.
- **`BatteryMonitor.refresh()`'s synchronous `IOPSCopyPowerSourcesInfo` read.** It runs on the main actor by design and is outside this finding; if it ever blocks, that is a separate review item.
- **Wiring TSan into CI.** Diagnostic only; `--sanitize=thread` is too slow and the UI test suites are noisy under it.
- **Any change to `IOPSBatteryReader`, `BatteryStatus`, or the SwiftUI battery surfaces.** Read-only for this investigation.

## File Ownership & Conflicts

**Owns (exclusive):**
- `Tests/StatusTrioCoreTests/BatteryCallbackTeardownTests.swift` (new)
- `docs/battery-callback-teardown.md` (new)
- `Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift` — **only if Task 3 confirms the hazard**; otherwise this file stays untouched.

**Shared:**
- `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift` — R-16 (fixed-sleep hardening) owns this file and lands first (index §3.1). This plan does not edit it: the existing `IOPSNotificationSourceHarness` retains the context (`:526-532`) and cannot express the unretained contract, so the new harness lives in the new file by design. If a reviewer insists the regression test belong in `BatteryMonitorTests.swift`, rebase after R-16 and keep the change purely additive.
- `docs/swift-ci-compatibility.md` — append-only, shared with every plan; add at most one section for this plan's preflight and never rewrite existing rows.
- No overlap with R-19 (icon parity/lifecycle tests): if R-19 later adds a battery `deinit` test, `BatteryCallbackTeardownTests` is the source of truth for the callback-context contract.

**Does not touch:** `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`, `WiFiMonitor.swift`, `ReadWatchdog.swift`, `Store/SystemStatusStore.swift`, `App/AppEnvironment.swift`, `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`, `VolumeMonitorAsyncTests.swift`, `scripts/*`, `.github/workflows/*`, `release-notes/*`, `appcast.xml`.
