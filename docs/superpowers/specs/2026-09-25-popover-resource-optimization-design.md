# Status popover CPU and memory optimization design

## Intent and scope

Continue PR #71 by determining whether the status popover opened from the menu bar or Dock has avoidable CPU or retained memory cost. Preserve the current status accuracy, permission behavior, first-open response, and quick-reopen experience. Measure the latest PR commit before changing production code; accept only improvements attributable to an identified cost.

The scope is the status popover's summary (including its Bluetooth section), Wi-Fi and battery detail pages, their monitoring lifecycle, and memory remaining after the popover closes. The Settings window is closed during popover measurements and is included only where an explicit Bluetooth monitoring setting changes the popover's behavior. Menu bar and Dock icon rendering are outside this work unless profiling directly implicates a shared path; any later icon change must retain menu bar and Dock parity.

## Existing evidence and limits

- PR #71 already makes VPN monitoring follow popover visibility, stops popover-only Bluetooth monitoring on close, limits Bluetooth HID registry properties, and releases the closed popover's SwiftUI content after 60 seconds. Its [memory report](../../performance/memory-footprint-2026-09.md) records 17–18 MB physical footprint for clean menu-bar idle and about 73.5 MB after a full-permission popover interaction. The latter has no confirmed application-level retaining owner.
- The report's earlier 634.4 MB Bluetooth HID figure is cumulative created-and-destroyed allocation over 3:01, not retained memory. The revised HID reader and latest VPN lifecycle code lack a controlled post-change trace.
- On 2026-09-25, the already-running development process PID 59584 showed 78 MB physical footprint after several hours. Its binary was built at 13:07, before the PR head `cbe3a0e` at 16:49. CPU time rose from 27.57 s to 27.82 s over a 15 s sample, about 1.7% of one core; an 8 s `sample` trace found its main thread mostly waiting for events. The popover's visibility and earlier interactions were not controlled. These readings cannot establish current-head popover CPU or memory cost.
- Source review identifies a candidate opening burst: `SystemStatusStore.setPopoverVisible(true)` calls `BluetoothDeviceController.activate()` and then `refresh()`, while `receiveSystemState` can also request `refresh()`. The controller coalesces overlapping requests into one in-flight read and one follow-up, so an ordinary opening may still launch two `system_profiler` device reads. This is a hypothesis until a read-count trace confirms it. `setDetailsVisible(true)` followed by `refreshAll()` can similarly request Wi-Fi more than once; its in-flight coalescing may turn that into a follow-up read.
- The 60-second popover content release cannot explain physical memory still present several minutes after close. Shortening that delay is not a proposed steady-state fix without allocation evidence.

## Measurement design

Use a fresh release-style app built from the exact PR head with the macOS 26 SDK or newer, a recorded executable hash, version/build, bundle ID, macOS version, power state, display scale, enabled sections, and Bluetooth/Wi-Fi permissions. Keep the same app identity and permissions for before/after runs. Do not substitute the installed app, a stale `dist` binary, or the already-running PID for this baseline. Run the same scenario three times in fresh processes and preserve each raw result.

Measure these states separately, confirming popover and Settings visibility at every marker:

1. Cold launch with neither window opened: 2-minute idle baseline.
2. Summary popover opened once and held for 60 seconds: opening burst and steady open CPU.
3. The Bluetooth section in the summary, then the Wi-Fi and battery detail pages in separate fresh sessions: reader and page-specific CPU.
4. Summary close: 15 seconds and 2 minutes after close, with no Settings window.
5. Ten summary cycles with 10 seconds open and 10 seconds closed, then 2 minutes closed: cumulative CPU, allocation churn, retained memory, and reopen latency.

At each marker, record `ps` RSS and cumulative CPU time, `footprint` current and peak physical footprint, and `vmmap -summary` categories. Use Time Profiler for active CPU call stacks and Allocations with Malloc Stack Logging from before the interaction to identify allocations still live after close. Count actual `system_profiler` launches and the app's Bluetooth, Wi-Fi, and volume reader invocations, distinguishing requests from completed system reads. Include child-process CPU time in the opening and repeated-cycle totals. Store the scenario table and commands in a dated `docs/performance/` report; keep large `.trace` files outside Git and record their local paths and tool settings in that report.

The three runs use the same machine, app preferences, permission state, scenario timing, and build style. Interleave baseline and candidate runs when testing a code change so device or system drift does not systematically favor one build. Record anomalous events such as a device connection change, charging transition, permission prompt, or failed read; rerun that trial instead of treating it as an ordinary opening.

## Component and data-flow changes

The existing boundaries remain: `StatusBarController` owns the popover and its delayed content release; `SystemStatusStore` owns visibility and refresh requests; each monitor owns its system read and event source. Measurement hooks may be test-only spies or temporary profiling signposts. No new permanent coordinator or third-party dependency is required.

If a no-event popover opening performs two Bluetooth profiler device reads, adjust the activation path to request one fresh read when the monitor is newly started and one fresh read when Settings already keeps it active. An actual connection event, permission change, explicit refresh button, timeout recovery, or later safety-net tick must still trigger a read. Do not remove the one-follow-up protection for events arriving during an in-flight read. If Wi-Fi or volume show an analogous repeated completed read, handle each as a separate measured change in its own controller or store trigger path.

For memory, first name the application-owned allocation stack or retained object group responsible for a repeatable post-close delta. Change only that owner's lifetime or cache boundary. Candidate owners include popover content, monitor-held arrays, and shared profiler report bytes, but none is selected without attribution. If Allocations finds only framework initialization, allocator-held free pages, or a delta below the gate below, record the finding and leave the 60-second retention policy and cache lifetimes unchanged.

## Failure and concurrency behavior

Closing the popover must stop popover-only VPN/Bluetooth work, scans, periodic tasks, and event registrations already tied to visibility. An in-flight system read may finish after close, but its generation/token gate must prevent a stale result from republishing into a later session. A Bluetooth authorization prompt must still appear only after the user explicitly requests it. A failed or timed-out read must retain the current bounded retry/recovery behavior; eliminating a duplicate opening read must not suppress a genuine follow-up event.

If a profiling tool cannot attach or a permission state cannot be confirmed, record the failure and switch to read counters plus `ps`/`footprint` snapshots for that scenario. Do not infer a retained-memory owner from `heap` categories, RSS, or a single process's high-water mark alone.

## Acceptance criteria

- Baseline report identifies the exact PR-head binary and includes three controlled runs for each state above, with separate in-process and child-process CPU accounting and physical footprint. A missing trace is reported as a limit, not filled by inference.
- The Bluetooth change is eligible only if the baseline confirms at least two completed no-event device reads for one ordinary opening. After a change, a test spy and runtime counter show one completed read per ordinary opening, while Settings-enabled monitoring, reopening, actual device events, explicit refresh, permission changes, and timeout recovery remain correct.
- A CPU improvement is claimed only if the median combined app-plus-child CPU time over ten cycles falls by at least 10% and by more than the full baseline run-to-run range. Otherwise, the result may be described as fewer reads, but not as a measured CPU reduction.
- A memory improvement is claimed only if allocation stacks identify an application-owned retained group, its median live bytes fall by at least 2 MB, and median physical footprint 2 minutes after close falls by at least 3 MB across the same three-run comparison. A lower RSS alone does not satisfy this gate.
- Median first-open and quick-reopen latency may not increase by more than the greater of 100 ms or 10% of baseline. Status values and permissions remain correct; no monitor or scan continues solely because the popover was previously opened.
- Each accepted Swift change passes `swift test` and `swift build -c release`. Because the likely paths involve `@MainActor`, `deinit`, or SwiftUI lifecycle, run the required non-publishing `release.yml` preflight on the implementation branch before merge. Log any failed Actions run in `docs/swift-ci-compatibility.md`. No release is part of this work.

## Decision rule and deliverables

The first deliverable is the dated performance report and a confirmed cost ranking. Then implement the smallest CPU change that passes its gate and repeat the exact scenarios. Attempt a memory change only after retained-object attribution passes its gate. If neither gate is met, close the investigation with a measured conclusion and no production edit.

The implementation plan will break the work into measurement, conditional CPU change, conditional memory change, and verification checkpoints. The measurements decide which conditional tasks run; no speculative cleanup is treated as an optimization result.
