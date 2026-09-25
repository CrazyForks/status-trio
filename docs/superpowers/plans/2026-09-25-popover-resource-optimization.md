# Status Popover Resource Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure PR #71's status popover CPU and retained memory, remove a confirmed duplicate Bluetooth opening read, and identify any separately actionable post-close memory owner.

**Architecture:** Preserve `StatusBarController` as the popover lifetime owner, `SystemStatusStore` as the visibility/refresh coordinator, and each monitor as the system-read owner. Compare controlled, exact-build baseline and candidate runs before accepting a code change. Unknown memory ownership is an attribution task, not a speculative cache edit.

**Tech Stack:** SwiftPM, Swift 6.3.3 on CI, AppKit, SwiftUI, Combine, CoreBluetooth, macOS `ps`/`footprint`/`vmmap`, Xcode Time Profiler and Allocations.

**Spec:** [Status popover CPU and memory optimization design](../specs/2026-09-25-popover-resource-optimization-design.md)

## Global Constraints

- CI acceptance uses `macos-26`, Xcode `26.6`, Swift `6.3.3`; build app artifacts with the macOS 26 SDK or newer and preserve `scripts/build-app.sh` and `scripts/verify-platform-version.sh` checks.
- Do not build over a running app bundle. Use an isolated execution worktree with its own `dist/` and one stable profiling bundle ID for baseline and candidate; record the exact executable SHA-256 and Bluetooth/Wi-Fi permission state.
- Report RSS and physical footprint separately; compare three fresh-process runs per scenario. Count child `system_profiler` CPU in total CPU and do not equate cumulative allocations with retained bytes.
- Before committing Swift changes run `swift test` and `swift build -c release`. For changes to actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module`, run a non-publishing `release.yml` preflight before merge and log every failed Actions run in `docs/swift-ci-compatibility.md`.
- Keep Bluetooth authorization user initiated, preserve event and timeout recovery, and leave the menu bar and Dock icon paths in parity if profiling later justifies touching them.
- When implementing this written plan, use the newest available Luna model (`gpt-6-luna` at plan time), per the project's standing model preference.

## File map

| Responsibility | Files |
|---|---|
| Measurement record and decision | Create `docs/performance/popover-resource-2026-09.md`; read `docs/performance/memory-footprint-2026-09.md` and the spec above. |
| Popover opening and visibility | `Sources/StatusTrioCore/UI/StatusBarController.swift:285-305,450-480`; `Sources/StatusTrioCore/Store/SystemStatusStore.swift:429-496`. |
| Bluetooth read owner and tests | `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift:558-665,755-925`; `Tests/StatusTrioCoreTests/BluetoothPermissionTimingTests.swift`; `Tests/StatusTrioCoreTests/BluetoothPollingLifetimeTests.swift`. |
| Other page lifetimes | `Sources/StatusTrioCore/Monitoring/WiFiNetworkController.swift`; `Sources/StatusTrioCore/Monitoring/BatteryDetailsController.swift`; `Tests/StatusTrioCoreTests/WiFiNetworkScanCadenceTests.swift`. |
| CI and release guard | `.github/workflows/release.yml`, `docs/swift-ci-compatibility.md`; no release is published by this plan. |

## Review Focus

1. Bluetooth permission is undecided or denied: opening the popover must not start CoreBluetooth or prompt; Task 2 runs `testOpeningPopoverExposesBluetoothAuthorizationWithoutStartingMonitor` and `testOpeningThePopoverKeepsUnauthorizedBluetoothIdle`.
2. Settings already owns Bluetooth monitoring: opening must perform one fresh read, and closing must not stop that monitor; Task 2 adds `testSettingsOwnedBluetoothGetsOneOpeningRead` and runs `testExplicitlyEnabledBluetoothMonitorSurvivesPopupClose`.
3. A device event arrives during a read: its genuine follow-up must survive opening deduplication; Task 2 runs `testReadsCoalesceIntoOneFollowUpWhileAReadIsInFlight`.
4. A read finishes after close or times out: it must not publish stale data or wedge future reads; Task 2 runs the existing superseded-read and timeout tests in `BluetoothPollingLifetimeTests`.
5. A Wi-Fi detail scan or battery detail collector is active at close: it must stop with the panel; Task 3 runs `WiFiNetworkScanCadenceTests` and `BatteryPopoverPanelTests` while attributing post-close allocations.

---

### Task 1: Establish a controlled PR-head resource baseline

**Execution status:** Steps 1–2 completed; Steps 3–5 remain incomplete. The report records one excluded fresh-process attempt and later exploratory same-process samples, but the required three fresh-process sequences and profiler allocation stacks were not captured. Step 5's repeat protocol therefore remains unmet despite the report being committed. See [`popover-resource-2026-09.md`](../../performance/popover-resource-2026-09.md).

**Files:**
- Create: `docs/performance/popover-resource-2026-09.md`
- Read: `docs/superpowers/specs/2026-09-25-popover-resource-optimization-design.md`
- Read: `docs/performance/memory-footprint-2026-09.md`

**Interfaces:**
- Consumes: the exact PR-head executable, `StatusBarController`'s visible/closed states, and the existing system readers.
- Produces: a table of three raw runs per scenario, actual reader/process counts, CPU totals, retained-allocation attribution, and an explicit Task 2 eligibility verdict.

- [x] **Step 1: Prepare an isolated profiling build.** Record the commit and SDK, then build without opening the app. Use the same bundle ID for all baseline and candidate runs; grant Bluetooth only to that exact app if the scenario requires it. The execution worktree must have no running process using its `dist/` path.

```bash
git rev-parse HEAD
xcrun --sdk macosx --show-sdk-version
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.popover-resource APP_NAME='Status Trio Popover Perf' bash scripts/build-app.sh release no-open
shasum -a 256 dist/StatusTrio.app/Contents/MacOS/StatusTrio
xcrun vtool -show-build dist/StatusTrio.app/Contents/MacOS/StatusTrio
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' dist/StatusTrio.app/Contents/Info.plist
```

- [x] **Step 2: Write the measurement sheet before collecting data.** Create `docs/performance/popover-resource-2026-09.md` with one row per run and marker. Columns: commit/hash, bundle ID, OS/SDK, permissions, enabled sections, power/display state, PID, confirmed UI state, elapsed time, RSS KB, app CPU seconds, child CPU seconds, physical footprint MB/peak, `vmmap` Malloc Small/CoreAnimation/CG Raster/CG Image/IOSurface, profiler launches, Bluetooth/Wi-Fi/volume completed reads, and first-open/reopen latency. Label unavailable values explicitly.

- [ ] **Step 3: Capture three fresh-process sequences.** For each run: 2 minutes cold idle; summary open 60 seconds; Bluetooth section visible; close at 15 seconds and 2 minutes; Wi-Fi detail and battery detail in separate summary sessions; ten summary cycles of 10 seconds open/10 seconds closed; then 2 minutes closed. Confirm Settings closed at every marker. Read the exact PID from `pgrep -fl StatusTrio` and assign it to `pid`; assign a unique label such as `baseline-1` to `run_id`. Use `ps`, `footprint`, and `vmmap` at each marker and save their raw output outside Git, linked by run ID in the report.

```bash
ps -p "$pid" -o pid,etime,cputime,rss,command
footprint -p "$pid"
vmmap -summary "$pid"
```

- [ ] **Step 4: Capture CPU and allocation ownership.** In each of the three fresh-process runs, cover the full summary-opening and ten-cycle periods with Time Profiler across all processes so `system_profiler` children appear. In each run, start an Allocations trace before a separate popover interaction, enable allocation stack recording in Instruments, and inspect objects still live 2 minutes after close. Use a unique `run_id` in each trace filename; export/read process counts and stacks. If attach stalls or permissions cannot be confirmed, record that failure and use reader spies and the snapshots without inferring a memory owner.

```bash
xcrun xctrace record --template 'Time Profiler' --all-processes --time-limit 5m --output "/tmp/status-trio-popover-$run_id.trace"
xcrun xctrace record --template 'Allocations' --attach "$pid" --time-limit 5m --output "/tmp/status-trio-allocations-$run_id.trace"
```

- [ ] **Step 5: Verify and commit the baseline report.** Mark each trial with a permission prompt, connection/charging transition, failed read, or unconfirmed UI state as excluded and repeat it. State whether a clean opening completed at least two Bluetooth device reads, whether Wi-Fi/volume completed redundant reads, and whether an application-owned group accounts for at least 2 MB still live after close. Do not write a code fix from a single sample.

```bash
git diff --check
git add docs/performance/popover-resource-2026-09.md
git commit -m 'docs(perf): measure PR 71 popover CPU and memory'
```

### Task 2: Remove a confirmed duplicate Bluetooth opening read

**Execution status: skipped.** Task 1 did not capture the completed-read count required to establish duplicate-read eligibility. The implementation and test steps below were not run; no production Swift change was made.

**Gate:** Execute only if Task 1 records at least two completed no-event device reads for one ordinary popover opening. If the count is already one, record “Task 2 skipped: no duplicate completed read” in the report and continue to Task 3 without changing production code.

**Files:**
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift:429-448`
- Modify: `Tests/StatusTrioCoreTests/BluetoothPermissionTimingTests.swift`
- Read/run: `Tests/StatusTrioCoreTests/BluetoothPollingLifetimeTests.swift`
- Modify: `docs/performance/popover-resource-2026-09.md`

**Interfaces:**
- Consumes: `BluetoothDeviceController.isActive`, `activate()`, `refresh()`, and the existing `BluetoothPanelActivation.shouldActivate` permission gate.
- Produces: `activateBluetoothForPopover()` that relies on the newly started state monitor's first `.available` callback for its initial read, but explicitly refreshes a monitor already active for Settings.

- [ ] **Step 1: Write the failing opening test and test doubles.** Add two tests to `BluetoothPermissionTimingTests`: `testNewPopoverBluetoothMonitorGetsOneOpeningRead` and `testSettingsOwnedBluetoothGetsOneOpeningRead`. Use the existing empty battery/Wi-Fi/volume fakes. Extend its private state-monitor spy with `emitPoweredOnOnStart` (default `false`) and add an `NSLock`-protected counting reader; `start()` invokes `onStateChange?(.allowed, .poweredOn)` synchronously when that flag is true, and the reader counts then calls `completion(.success([]))`. The first test opens a granted popover, waits for the queued completion, and expects `readCount == 1`; the second enables Settings Bluetooth first, records the count, opens the popover, and expects exactly one additional read. End each test by closing the popover and stopping the store.

```swift
func testNewPopoverBluetoothMonitorGetsOneOpeningRead() async {
    let reader = CountingPermissionTimingBluetoothReader()
    let monitor = BluetoothStateMonitorSpy(
        authorization: .allowed,
        emitPoweredOnOnStart: true
    )
    let bluetooth = BluetoothDeviceController(
        worker: reader,
        stateMonitor: monitor,
        notificationCenter: NotificationCenter(),
        workspaceNotificationCenter: NotificationCenter()
    )
    let store = SystemStatusStore(
        batteryMonitor: EmptyBatteryMonitorForBluetoothTiming(),
        wifiMonitor: EmptyWiFiMonitorForBluetoothTiming(),
        volumeMonitor: EmptyVolumeMonitorForBluetoothTiming(),
        bluetoothDevices: bluetooth
    )
    store.setPopoverVisible(true)
    try? await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(reader.readCount, 1)
    store.setPopoverVisible(false)
    store.stop()
}
```

Add this Settings-owned case beside it, using the same store construction and test doubles. The first read comes from `setBluetoothEnabled(true)`; the popover must add exactly one.

```swift
func testSettingsOwnedBluetoothGetsOneOpeningRead() async {
    let reader = CountingPermissionTimingBluetoothReader()
    let monitor = BluetoothStateMonitorSpy(
        authorization: .allowed,
        emitPoweredOnOnStart: true
    )
    let bluetooth = BluetoothDeviceController(
        worker: reader,
        stateMonitor: monitor,
        notificationCenter: NotificationCenter(),
        workspaceNotificationCenter: NotificationCenter()
    )
    let store = SystemStatusStore(
        batteryMonitor: EmptyBatteryMonitorForBluetoothTiming(),
        wifiMonitor: EmptyWiFiMonitorForBluetoothTiming(),
        volumeMonitor: EmptyVolumeMonitorForBluetoothTiming(),
        bluetoothDevices: bluetooth
    )
    store.setBluetoothEnabled(true)
    try? await Task.sleep(for: .milliseconds(100))
    let beforeOpen = reader.readCount
    store.setPopoverVisible(true)
    try? await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(reader.readCount, beforeOpen + 1)
    store.setPopoverVisible(false)
    XCTAssertTrue(bluetooth.isActive)
    store.stop()
}
```

Extend the existing private `BluetoothStateMonitorSpy` initializer/start method and add this reader in the same test file:

```swift
private final class CountingPermissionTimingBluetoothReader:
    BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var readCount: Int { lock.withLock { count } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock { count += 1 }
        completion(.success([]))
    }
}

// In BluetoothStateMonitorSpy:
private let emitPoweredOnOnStart: Bool

init(
    authorization: BluetoothAuthorizationStatus = .notDetermined,
    emitPoweredOnOnStart: Bool = false
) {
    self.authorization = authorization
    self.emitPoweredOnOnStart = emitPoweredOnOnStart
}

func start() {
    startCount += 1
    if emitPoweredOnOnStart {
        onStateChange?(.allowed, .poweredOn)
    }
}
```

- [ ] **Step 2: Confirm the test fails against the baseline.** Run the focused test. Expected result: the newly started monitor's synchronous `.available` callback starts one read and the unconditional store `refresh()` queues a second; the assertion reports `2` rather than `1`. If it reports `1`, check the Task 1 runtime counter and skip the fix if no duplicate completed read exists.

```bash
swift test --filter 'BluetoothPermissionTimingTests.testNewPopoverBluetoothMonitorGetsOneOpeningRead'
```

- [ ] **Step 3: Make the smallest opening-path change.** Capture activation state before the optional `activate()`. Keep the existing permission gate and ownership flag. Explicitly refresh only if the controller was already active; a new monitor's state callback performs its initial read. Do not change `BluetoothDeviceController`'s event coalescing or watchdog.

```swift
let wasActive = bluetoothDevices.isActive
if !isBluetoothEnabled {
    isBluetoothActivatedForPopover = true
    bluetoothDevices.activate()
}
if wasActive {
    bluetoothDevices.refresh()
}
```

- [ ] **Step 4: Verify behavior and runtime benefit.** Run both new tests; run the authorization, close/reopen, in-flight event, superseded-read, and timeout tests named in Review Focus. Rebuild the profiling app with the same bundle ID and permissions; repeat Task 1's three-run summary and ten-cycle scenarios. Record actual completed read and `system_profiler` launch counts, combined app-plus-child CPU, first-open/reopen latency, and 2-minute post-close footprint. If the one-read rule or latency gate fails, revert the source change and record the reason.

```bash
swift test --filter 'BluetoothPermissionTimingTests'
swift test --filter 'BluetoothPollingLifetimeTests'
swift test
swift build -c release
```

- [ ] **Step 5: Commit only a verified change.** Claim a CPU reduction only when the median ten-cycle combined CPU time falls at least 10% and exceeds the entire baseline run-to-run range; otherwise report only the confirmed reduction in reads. Update the performance report with all three candidate runs, then commit the source, tests, and report after the full Swift gates pass.

```bash
git diff --check
git add Sources/StatusTrioCore/Store/SystemStatusStore.swift Tests/StatusTrioCoreTests/BluetoothPermissionTimingTests.swift docs/performance/popover-resource-2026-09.md
git commit -m 'perf(popover): avoid duplicate Bluetooth opening read'
```

### Task 3: Attribute post-close memory and choose the next bounded change

**Execution status:** Step 1 remains incomplete because the Allocations trace failed to attach and no three-run allocation/footprint comparison exists. Step 2's source review and 17 focused lifecycle tests completed, but live hosting-controller deallocation remains unverified, so the full step remains unchecked. Steps 3–4 completed: the report records no justified memory edit and was committed. The measured executable used source commit `c5a6240`, a docs-only descendant of PR head `cbe3a0e`, so the PR's VPN/HID changes were present. See [`popover-resource-2026-09.md`](../../performance/popover-resource-2026-09.md).

**Files:**
- Modify: `docs/performance/popover-resource-2026-09.md`
- Read/run: `Tests/StatusTrioCoreTests/WiFiNetworkScanCadenceTests.swift`, `Tests/StatusTrioCoreTests/BatteryPopoverPanelTests.swift`, `Sources/StatusTrioCore/UI/StatusBarController.swift:450-480`

**Interfaces:**
- Consumes: Task 1 Allocations stacks and three-run 2-minute post-close physical-footprint results, plus Task 2's candidate results if Task 2 ran.
- Produces: an owner-ranked memory finding with live-byte totals and one of two decisions: a named application-owned target for a separate, file-specific remediation plan, or no justified memory edit.

- [ ] **Step 1: Compare live allocations with physical footprint.** For each of the three runs, subtract cold-idle live bytes from 2-minute post-close live bytes by allocation stack. Name app-owned stacks and bytes. Compare `Malloc Small`, CoreAnimation, CG Raster, CG Image, and IOSurface deltas against the corresponding physical-footprint change. Do not call allocator fragmentation, framework initialization, or the trace's cumulative allocation a leak.

- [ ] **Step 2: Check the already-defined close boundary.** Verify `StatusBarController.popoverDidClose` calls `setPopoverVisible(false)` and `closePopoverDetails`, and its release task sets `popover.contentViewController = nil` after the 60-second delay. Run the popover retention, Wi-Fi scan, and battery detail lifecycle suites; use the allocation trace to check whether the hosting controller deallocates after release. If a suite fails, handle the failure under the repository's debugging workflow before attributing memory.

```bash
swift test --filter 'PopoverContentRetentionTests'
swift test --filter 'WiFiNetworkScanCadenceTests'
swift test --filter 'BatteryPopoverPanelTests'
```

- [x] **Step 3: Record the decision.** If an application-owned group contributes at least 2 MB median live bytes and at least 3 MB median physical footprint at 2 minutes, write its exact stack, file/owner, entry/close path, and three-run numbers into the report, then create a separate narrow design/plan for that owner before editing it. This preserves the spec's evidence gate: the current plan cannot truthfully prescribe a lifetime change for an owner the trace has not named. If the gate is not met or tracing was unavailable, record that no memory optimization is established and leave the 60-second retention/cache policy unchanged.

- [x] **Step 4: Commit the attribution report.** Include trace paths/tool settings, excluded runs, and whether the latest VPN/HID changes were present in the measured binary.

```bash
git diff --check
git add docs/performance/popover-resource-2026-09.md
git commit -m 'docs(perf): attribute post-popover retained memory'
```

### Task 4: Final verification and PR #71 handoff

**Execution status:** No Swift source changed in this plan, so full local gates were not rerun; earlier local baseline tests and build passed, 17 focused lifecycle tests passed in Task 1, and CI run `36131258691` revalidated tests/build on macOS 26. Steps 2–3 completed: preflight run `36131258691` passed with `publish=false`, and the PR body was updated and verified while PR #71 remained draft.

**Files:**
- Modify: `docs/performance/popover-resource-2026-09.md` only if final verification changes a recorded result.
- Modify: `docs/swift-ci-compatibility.md` only if a GitHub Actions run fails.
- Read: `.github/workflows/release.yml` and the repository `AGENTS.md` rules.

**Interfaces:**
- Consumes: Tasks 1–3 results and any accepted Swift commit.
- Produces: a PR comment/body update that distinguishes demonstrated CPU improvement, fewer reads without measured CPU improvement, and unresolved memory attribution.

- [x] **Step 1: Run the final local gates if Swift changed.** No Swift source changed in this plan, so the full local gates were not rerun; the working tree and diff were checked for accidental changes.

```bash
swift test
swift build -c release
git diff --check
git status --short --branch
```

- [x] **Step 2: Run the non-publishing CI preflight if required.** Push the implementation branch after local gates. Inspect the latest published version/build, enter explicit higher values that satisfy the release-note validator, dispatch against the pushed branch, and watch the returned run ID. For every failed run, add its run ID, stage, root cause, fix, and verification result to `docs/swift-ci-compatibility.md` before retrying. Do not publish a release.

```bash
git push origin HEAD:codex/memory-footprint-opt
gh release view --repo lingyired/status-trio --json tagName
git fetch origin main
git show origin/main:appcast.xml | rg -m 1 '<sparkle:version>'
echo 'Enter explicit next version:'
read -r preflight_version
echo 'Enter explicit next build number:'
read -r preflight_build
gh workflow run release.yml --repo lingyired/status-trio --ref codex/memory-footprint-opt -f version="$preflight_version" -f build="$preflight_build" -f publish=false
gh run list --repo lingyired/status-trio --workflow release.yml --branch codex/memory-footprint-opt --limit 3
echo 'Enter the dispatched run ID:'
read -r preflight_run_id
gh run watch "$preflight_run_id" --repo lingyired/status-trio --exit-status
```

- [x] **Step 3: Review and hand off PR #71.** Confirm the measured binary matches the final source commit, all accepted changes meet the spec's read-count/CPU/memory/latency gates, and the performance report states remaining limits. Update the PR summary with verified numbers and any skipped conditional task; leave the PR as draft until its required checks pass. If Task 3 identified a memory owner, link its separate plan rather than claiming this PR already reduced that memory.

## Execution order

Task 1 is mandatory. Task 2 runs only after its completed-read gate; Task 3 always records the memory decision, and an owner-specific remediation is a separate plan. Task 4 closes the work after every accepted Swift change has passed the repository gates. If Task 1 identifies a different CPU hotspot instead of the proposed Bluetooth opening burst, record its call stack and create a small amendment with its exact files and tests before changing that path.
