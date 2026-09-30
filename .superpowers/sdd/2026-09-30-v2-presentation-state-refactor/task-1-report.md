# Task 1 Report: Presentation Behavior Baseline

## Result

Status: **DONE_WITH_CONCERNS**

Added only the requested test fixture, baseline tests, behavior matrix, and this report. No production source changed. `PresentationFixtures.snapshot(rssi:scalar:muted:)` provides the common 68% battery / connected Wi-Fi / `.wifi` / volume snapshot, and `bluetoothDevice` forwards the existing `SheetFixtures` device. The baseline records current behavior and passes before any presentation migration.

## Behavior and test ownership

The detailed matrix is in [`docs/presentation-state-behavior-matrix.md`](../../../docs/presentation-state-behavior-matrix.md). It names the existing mapping, renderer, parity, geometry, cache, animation, localization, panel-region, Bluetooth claim, and live-control tests, summarizes the behavior each one pins, and identifies where later mapper/scene, shared icon owner, renderer comparison, and panel-owner work still needs integration assertions.

The matrix distinguishes representative coverage from exhaustive coverage. In particular, current center-slot tests establish battery percentage precedence over network selection and battery absence fallback, while Bluetooth selection/error ordering is covered in the mapping tests; no single decision table covers all overlapping candidates. Existing panel tests own their section-specific behavior, but there is no single six-region state owner or owner-level test for shared state, per-region deduplication, and panel actions. Task 4 renderer comparison must call separate legacy and scene paths to avoid comparing an implementation with itself.

The animation fingerprint currently has separate approved entries for macOS 26 CI (`9f0c892e2602f4d4f9c541be1d93963e14d46e76f3ef24b46cd2dfbc25a22d1d`) and macOS 27 local (`0ef6d483e344f6056fa3799f9f33bac0092246e3dbfbb3619a4666d7e9e9c190`). The Wi-Fi SF Symbol test uses a threshold because rasterization varies with the OS/toolchain. Do not refresh these baselines without evidence of a platform rendering change.

## Verification evidence

Focused baseline:

```text
$ swift test --filter PresentationBaselineTests
Executed 3 tests, with 0 failures (0 unexpected).
EXIT_CODE=0
```

Full suite:

```text
$ swift test
✔ Test run with 410 tests in 69 suites passed after 2.139 seconds.
EXIT_CODE=0
```

Two existing Dock state-strip tests were skipped because their optional output environment variables were not set; the full suite reported zero failures.

Release build:

```text
$ swift build -c release
Build complete! (46.45秒)
EXIT_CODE=0
```

Diff validation:

```text
$ git diff --check
DIFF_CHECK_EXIT=0
```

The local validation environment is macOS 27.0.1 (build 26A434), macOS SDK 27.0, Xcode 27.0 (build 27A266a), Swift 6.4. The required acceptance environment is macOS 26 / Xcode 26.6 / Swift 6.3.3, so local success does not establish that CI toolchain result. The design-wide `publish=false` release preflight remains an integration gate; this characterization-only commit did not dispatch that workflow.

The complete command logs were captured during this run at `/tmp/status-trio-task1-swift-test.log` and `/tmp/status-trio-task1-release-build.log` on the local machine.

## Fix round 1: center-slot interaction coverage

Review found that the first matrix deferred one required baseline case: present-battery percentage competing with prioritized network-error handling while a Bluetooth output is active, plus absent-battery fallthrough when Bluetooth replacement is enabled. Added these two tests to `PresentationBaselineTests` without production changes:

- `testPresentBatteryPercentageWinsOverPrioritizedNetworkErrorAndBluetoothOutput` renders a `.noInternet` Wi-Fi state with a real Bluetooth output and network-error priority enabled. It compares only the center-slot pixel region: with the battery slot enabled, the region must match the battery-only reference and differ from the prioritized-network reference.
- `testAbsentBatteryFallsThroughToEnabledBluetoothReplacement` uses the shared Bluetooth output with no battery. The center region must match the Bluetooth replacement reference and differ from the ordinary network reference even when the battery-slot option is enabled.

These comparisons avoid volume pixels, whose tint also changes with Bluetooth. The baseline now records the current branch order: a present battery percentage wins first; otherwise enabled Bluetooth replacement is considered and may preserve a prioritized network error; otherwise the ordinary connection glyph is drawn.

Fix round verification on macOS 27.0.1 / SDK 27.0 / Xcode 27.0 / Swift 6.4:

```text
$ swift test --filter PresentationBaselineTests
Executed 5 tests, with 0 failures (0 unexpected).
EXIT_CODE=0

$ swift test
Executed 1116 tests, with 6 tests skipped and 0 failures (0 unexpected).
✔ Test run with 410 tests in 69 suites passed after 2.227 seconds.
EXIT_CODE=0

$ swift build -c release
Build complete! (23.91秒)
EXIT_CODE=0

$ git diff --check
DIFF_CHECK_EXIT=0
```

The six skips are existing opt-in output tests; none failed. Full logs for this fix round were captured at `/tmp/status-trio-task1-fix1-swift-test.log` and `/tmp/status-trio-task1-fix1-release-build.log` on the local machine. The macOS 26 / Xcode 26.6 / Swift 6.3.3 CI result and design-wide `publish=false` preflight remain integration gates.
