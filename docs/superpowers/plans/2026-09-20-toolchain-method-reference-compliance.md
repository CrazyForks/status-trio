# Toolchain Method-Reference Compliance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove every place where an actor-isolated method is passed as a function value, add a self-testing guard that makes the pattern impossible to reintroduce, and prove the result on the CI toolchain with a non-publishing release preflight.

**Architecture:** No architectural change. Eight handler arguments in `StatusBarController.installPopoverContentIfNeeded()`, one `Button(action:)` in `SettingsDisclosureRow`, and two `action: dismiss.callAsFunction` sites in `WiFiNetworkListView` are rewritten from method references into explicit closures. Behavior is identical; the codegen path that crashed IRGen at CI run `34758026894` is no longer taken. A standalone `scripts/check-forbidden-patterns.sh` scans `Sources/` for function values that resolve to a method declaration, with an inline, justified allowlist for the nonisolated references that are verified safe.

**Tech Stack:** Swift 6.3.3-compatible SwiftPM package, AppKit, SwiftUI, bash 3.2 (the version macOS ships), `grep -E`, existing GitHub Actions release workflow.

**Spec:** Derived from the 2026-09-20 code review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3; local Xcode 27 / Swift 6.4 compiling is NOT proof. `docs/swift-ci-compatibility.md` lists the concrete failures this caused.
- Forbidden in this repo: `isolated deinit`, enabling `IsolatedDeinit`, `weak let` (use `weak var`), passing actor-isolated methods directly as function values (use an explicit closure), assuming `Bundle.module` casing.
- Run `swift test` and `swift build -c release` before committing Swift changes. A non-publishing release preflight (`gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false`, then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`) is mandatory for changes touching actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources.
- Every failed CI run must be recorded in `docs/swift-ci-compatibility.md` with run ID, failed stage, root cause, fix and verification.
- Any change to menu bar icon rendering or icon settings must be mirrored in the Dock icon in the same change, and covered by tests for both outputs.
- Tests are mixed: most use Swift Testing (`import Testing`, `@Test`, `#expect`, `@MainActor` suites), some XCTest (`XCTAssert*`, `XCTSkipUnless`). Match the file you extend.
- This plan changes no rendering, no setting, and no user-visible behavior. Every rewrite calls exactly the same method, in the same order, from the same isolation domain. A rewrite that changes any of those three things is a bug, not a fix.
- The guard is committed before the fixes but enforced only after the fixes land, so no commit in this branch leaves a failing gate behind.
- Enforcement lives in `swift test` and in `scripts/test.sh`, never in a workflow file: `.github/workflows/release.yml` is owned exclusively by the release-pipeline plan and `.github/workflows/ci.yml` exclusively by the CI-gate plan. See `## File Ownership & Conflicts`.

## Review Focus

- A user clicking **Settings…** in the popover must still land in the app's settings window, and **Quit** must still quit: the rewrite keeps `openSettings`/`quitAction` (stored closures, unchanged) and the six system-settings handlers as main-actor calls. Pinned by `SettingsRowHitAreaTests.testPopupSettingsButtonUsesFullRowHitArea` (the popover still builds and lays out with the rewritten arguments) and by the guard's `--self-test` case asserting a swapped-in method reference is reported.
- A user who clicks the battery "open settings" control must reach the *battery* pane, not the Wi-Fi pane: `handleOpenBatterySettings` and `handleOpenWiFiSettings` are adjacent arguments of the same type, so a copy-paste slip is a silent wrong-pane bug. Pinned by the rewritten argument list in `StatusBarController.swift` plus a new assertion that each of the eight closures resolves to a distinct handler (the reference in the closure body is the pin, checked by the guard's inventory step).
- A user toggling the network-settings disclosure row must still expand it: `SettingsDisclosureRow.toggle()` is MainActor-isolated because the type conforms to SwiftUI's `@MainActor` `View` protocol (`SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface:17482`). Pinned by `SettingsDisclosureRowTests` (presentation values) and `SettingsRowHitAreaTests.testDisclosureRowUsesFullRowHitArea` (the row is still a full-width hit target).
- A user with the Wi-Fi password or permission alert open must still be able to dismiss it with **Cancel** and **Open Settings**: the two rewritten sites are the only `dismiss.callAsFunction` references, and `DismissAction.callAsFunction()` is declared `@_Concurrency.MainActor` in the SDK used by CI's macOS 26 SDK family. Pinned by `SettingsRowHitAreaTests.testWiFiDetailsToggleUsesFullRowHitArea` (the list still builds) and by the guard, which reports any reappearance of `.callAsFunction` as a violation.
- A contributor must not be able to reintroduce the pattern, and the guard must not block legitimate code: pinned by `scripts/check-forbidden-patterns.sh --self-test`, which asserts `handleOpenBatterySettings`, `toggle` and `dismiss.callAsFunction` are flagged while `isOutputDevice`, `projectCandidate`, `networkConfiguration`, `removeObserver`, `URL.init(string:)`, `\.element` and the stored-closure `onOpenBatterySettings` argument are not.

## Verified inventory (re-verified at review revision `13cdbbc`; do not re-derive)

Category (a1) — actor-isolated methods declared in this repo, passed as function values:

| Site | Shape | Isolation evidence |
| --- | --- | --- |
| `Sources/StatusTrioCore/UI/StatusBarController.swift:208` | `requestWiFiNameAccess: handleRequestWiFiNameAccess` | `@MainActor final class StatusBarController` at :14-15; `@objc private func` at :529 |
| `.../StatusBarController.swift:209` | `requestBluetoothAuthorization: handleRequestBluetoothAuthorization` | `@objc private func` at :534 |
| `.../StatusBarController.swift:210` | `openBatterySettings: handleOpenBatterySettings` | `@objc private func` at :539 |
| `.../StatusBarController.swift:211` | `openWiFiSettings: handleOpenWiFiSettings` | `@objc private func` at :544 |
| `.../StatusBarController.swift:212` | `openLocationSettings: handleOpenLocationSettings` | `@objc private func` at :549 |
| `.../StatusBarController.swift:213` | `openBluetoothSettings: handleOpenBluetoothSettings` | `private func` at :559 (no `@objc`; still MainActor-isolated) |
| `.../StatusBarController.swift:214` | `openSettings: handleOpenSettings` | `@objc private func` at :519 |
| `.../StatusBarController.swift:215` | `openSoundSettings: handleOpenSoundSettings` | `@objc private func` at :554 |
| `Sources/StatusTrioCore/UI/Settings/SettingsDisclosureRow.swift:62` | `Button(action: toggle)` | `struct SettingsDisclosureRow: View` at :37; `private func toggle()` at :94 |
| `Sources/StatusTrioCore/UI/WiFiNetworkListView.swift:286` | `action: dismiss.callAsFunction` | `@Environment(\.dismiss) private var dismiss` at :273; `DismissAction` is `@preconcurrency @_Concurrency.MainActor` with a MainActor `callAsFunction()` |
| `Sources/StatusTrioCore/UI/WiFiNetworkListView.swift:294` | `action: dismiss.callAsFunction` | same as above |

Eight + one + two = **eleven rewrites**. The popover receives `quit: quitAction` at `StatusBarController.swift:216`, and `quitAction` is a stored closure (`private let quitAction: () -> Void` at :36, assigned at :68) — it is **not** a method reference and must not be rewritten.

Category (a2) — why the two `dismiss.callAsFunction` sites belong to the same failure class even though the method is not ours: the conversion from a MainActor-isolated method to a plain `() -> Void` function value happens in our module, and that conversion thunk is what the recorded IRGen defect was about. The SDK declares the isolation explicitly:

```
SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface:1712:
@preconcurrency @_Concurrency.MainActor public struct DismissAction {
  @_Concurrency.MainActor @preconcurrency public func callAsFunction()
}
```

Category (b) — stored closure properties forwarded as function values. Audited and deliberately left alone: `Sources/StatusTrioCore/UI/Settings/AppIconSectionView.swift:28` (`onShowIconGuide`, declared :8), `BluetoothDeviceListView.swift:16,35,171,246` (`:10-12`, `:132-134`), `WiFiStatusView.swift:79,86` (`:10-12`), `VolumeControlsView.swift:36` (`:10`, `:12`), `BatteryDetailsView.swift:24` (`:9-10`), `NavigationBackRow.swift:9` (`:6`), `WiFiNetworkListView.swift:41,135,156,178` (`:8-11`), `IconGuideOnboardingView.swift:94` (`:11-12`), `BatteryStatusView.swift:13` (`:8-9`), `PopoverFooterView.swift:32,49` (`:18-19`), `BluetoothDeviceListView.swift:238,246`. These are **not** method references; `Button(action: onOpenBatterySettings)` copies a closure that was already formed at the call site. Do not "fix" them.

Category (c) — nonisolated method references, verified safe, deliberately excluded: `Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift:53` and `Sources/StatusTrioCore/UI/MainMenuController.swift:61` (`observers.forEach(notificationCenter.removeObserver)` — Foundation's `removeObserver` is nonisolated); `Sources/StatusTrioCore/Audio/CoreAudioOutputController.swift:24` (`.filter(isOutputDevice)`, declared `nonisolated private func` at :151); `Sources/StatusTrioCore/Monitoring/WiFiNetworkController.swift:130` (`.compactMap(projectCandidate)`, declared at :241) and `:257` (`.map(networkConfiguration(interface:))`, declared at :281) — both live on `private final class CoreWLANNetworkWorker` (:79), which is not actor-isolated, and are called from its serial queue. Also excluded: `URL.init(string:)` at `StatusBarController.swift:568,585,592,598,605` and other `.init` references (library initializers, no isolation thunk).

The verification command for the whole inventory is `bash scripts/check-forbidden-patterns.sh --list`, which prints one `file:line` per scanned function-value site with its verdict (`violation`, `allowed`, `external`).

---

### Task 1: Forbidden-Pattern Guard With A Self-Test

**Files:**
- Create: `scripts/check-forbidden-patterns.sh`

**Interfaces:**
- Produces: `bash scripts/check-forbidden-patterns.sh [--root <dir>] [--list] [--self-test]`; exit 0 = clean, 1 = violations found, 2 = usage error.
- Produces: `--list` output of the form `<path>:<line>:<verdict>:<identifier>` where verdict is `violation`, `allowed`, or `external`.
- Consumes: nothing.

- [ ] **Step 1: Write the guard and its embedded self-test fixtures**

Create `scripts/check-forbidden-patterns.sh` with this structure (the file must stay self-contained: the allowlist and the self-test fixtures live in the script, and the self-test writes its fixtures to `mktemp -d`):

```bash
#!/usr/bin/env bash
# Fails when an actor-isolated method is passed as a function value.
#
# AGENTS.md: "Do not pass actor-isolated methods directly as function values.
# Use an explicit closure instead." docs/swift-ci-compatibility.md records CI
# run 34758026894, where `Binding.set: localization.setPreference` crashed
# IRGen on the Swift 6.1.2 release toolchain; the documented remedy is the
# explicit closure this script enforces.
#
# Detection rule, in this order:
#   1. Collect function-value positions: `action:`/`get:`/`set:`/`using:`/
#      `block:` arguments and `.map/.compactMap/.filter/.forEach/.sink/.assign`
#      arguments, plus any `.callAsFunction` reference.
#   2. Drop anything that is already a closure (`{`), a call (`(`), a keypath
#      (`\.`), or a library initializer reference (`<Type>.init`).
#   3. A remaining bare identifier whose last component is declared as
#      `func <name>(` anywhere under Sources/ is a VIOLATION unless it is in
#      ALLOWED below.
#   4. Anything else is `external` and is reported by --list but never fails.
#
# False-positive policy: the rule errs strict on purpose. Nonisolated methods
# declared in this repo are flagged too, so each one needs an allowlist entry
# with a written justification. That keeps a reviewer in the loop instead of
# silently trusting a heuristic that cannot see isolation.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="scan"

# identifier<TAB>justification
ALLOWED=(
  "isOutputDevice	nonisolated private func, CoreAudioOutputController.swift:151; .filter(isOutputDevice) at :24 runs in a nonisolated method, so no isolation thunk is generated."
  "networkConfiguration	CoreWLANNetworkWorker (WiFiNetworkController.swift:79) is a nonisolated final class; the reference at :257 runs on its serial queue."
  "projectCandidate	CoreWLANNetworkWorker (WiFiNetworkController.swift:79) is a nonisolated final class; the reference at :130 runs on its serial queue."
  "removeObserver	Foundation API, nonisolated; used as observers.forEach(notificationCenter.removeObserver) at SystemIconAppearanceMonitor.swift:53 and MainMenuController.swift:61."
)
```

The scanner body (still in the same file) uses one `grep -nE` per shape, then the declaration lookup:

```bash
scan_shapes() {
  local root="$1"
  grep -rnE \
    -e '(action|get|set|using|block):[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[),]' \
    -e '\.(map|compactMap|filter|forEach|sink|assign)\([[:space:]]*[A-Za-z_][A-Za-z0-9_.]*\)' \
    -e '\.callAsFunction\b' \
    "$root/Sources" --include='*.swift' || true
}
```

`classify()` takes the captured expression, applies rule 2, then looks the last path component up with `grep -rnE "func ${name}\(" "$ROOT/Sources" --include='*.swift'`; a hit that is not in `ALLOWED` prints `violation`. `--self-test` writes four fixture files under `$(mktemp -d)` — one with `@MainActor final class Probe { func handleThing() {} }` plus `Button(action: handleThing) { EmptyView() }`, one with `struct ProbeView: View { private func toggle() {} ; var body: some View { Button(action: toggle) { EmptyView() } } }`, one with `Button(action: dismiss.callAsFunction) { EmptyView() }`, and one containing only the allowlisted and excluded shapes (`observers.forEach(center.removeObserver)`, `.filter(isOutputDevice)`, `.compactMap(projectCandidate)`, `.map(networkConfiguration(interface:))`, `.compactMap(URL.init(string:))`, `.map(\.element)`, `Button(action: onOpenBatterySettings) { EmptyView() }`) — then scans it with `--root` and asserts exactly three violations named `handleThing`, `toggle`, `callAsFunction`, and no violation for `removeObserver`, `isOutputDevice`, `projectCandidate`, `networkConfiguration`, `URL.init`, `element`, `onOpenBatterySettings`. `--self-test` prints one line per assertion and exits 1 if any assertion fails.

- [ ] **Step 2: Run the guard against the current tree and record the expected RED**

Run: `bash scripts/check-forbidden-patterns.sh`
Expected: exit code 1, with exactly eleven violation lines: `StatusBarController.swift` 208, 209, 210, 211, 212, 213, 214, 215; `SettingsDisclosureRow.swift:62`; `WiFiNetworkListView.swift:286` and `:294`. Any extra line is a real finding that belongs in this branch; any missing line means the rule is too narrow and Step 1 is not finished.

- [ ] **Step 3: Run the self-test and record the expected PASS**

Run: `bash scripts/check-forbidden-patterns.sh --self-test`
Expected: exits 0 and prints `self-test: 10/10 violations detected`, `self-test: 7/7 safe shapes ignored`. This proves the guard's precision before it is used to justify runtime-significant edits.

- [ ] **Step 4: Verify the allowlist entries against the tree**

Run: `bash scripts/check-forbidden-patterns.sh --list | grep -E 'allowed|external'`
Expected: one `allowed` line per allowlist entry (`removeObserver`, `isOutputDevice`, `projectCandidate`, `networkConfiguration`) and `external` lines for the `.init`/keypath sites. If an allowlist entry produces no `allowed` line, the code it justified has changed — delete the entry instead of leaving it stale.

- [ ] **Step 5: Commit the guard without wiring it in**

```bash
chmod +x scripts/check-forbidden-patterns.sh
git add scripts/check-forbidden-patterns.sh
git commit -m "chore(scripts): add forbidden-pattern guard for actor-isolated method references

The guard scans Sources/ for function values that resolve to a method
declaration and fails with the offending file:line. It carries an inline,
justified allowlist for the nonisolated references that are verified safe,
and --self-test proves both directions on generated fixtures.

It is not enforced yet: the working tree still has
eleven violations, and the gate is switched on in the last task of this
branch so no commit in between leaves a red gate behind."
```

---

### Task 2: Rewrite The Eight `StatusPopoverView` Handler Arguments

**Files:**
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift`

**Interfaces:**
- Consumes: `scripts/check-forbidden-patterns.sh` from Task 1.
- Produces: no new API. `StatusPopoverView` keeps the same eleven `() -> Void` properties declared at `StatusPopoverView.swift:258-266`; only the eight argument expressions at the call site change.

- [ ] **Step 1: Confirm RED for this file only**

Run: `bash scripts/check-forbidden-patterns.sh 2>&1 | grep StatusBarController`
Expected: exit 0 for the `grep` and eight lines for `StatusBarController.swift:208-215`.

- [ ] **Step 2: Replace the eight method references with explicit closures**

Edit `installPopoverContentIfNeeded()` so the call reads (each closure calls exactly one member, so this is behavior-identical and no `@objc` attribute or handler signature changes):

```swift
    private func installPopoverContentIfNeeded() {
        guard popover.contentViewController == nil else { return }
        let rootView = LocalizedRootView(localization: localization) {
            StatusPopoverView(
                store: store,
                settings: settings,
                scrollTargets: popoverScrollTargets,
                // Pass explicit closures, never the method references: a
                // MainActor-isolated method converted to a function value
                // generates the thunk that crashed IRGen in CI run 34758026894
                // (docs/swift-ci-compatibility.md).
                requestWiFiNameAccess: { self.handleRequestWiFiNameAccess() },
                requestBluetoothAuthorization: { self.handleRequestBluetoothAuthorization() },
                openBatterySettings: { self.handleOpenBatterySettings() },
                openWiFiSettings: { self.handleOpenWiFiSettings() },
                openLocationSettings: { self.handleOpenLocationSettings() },
                openBluetoothSettings: { self.handleOpenBluetoothSettings() },
                openSettings: { self.handleOpenSettings() },
                openSoundSettings: { self.handleOpenSoundSettings() },
                quit: quitAction
            )
        }
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }
```

- [ ] **Step 3: Prove the eight closures are distinct and correctly paired**

Run: `sed -n '204,220p' Sources/StatusTrioCore/UI/StatusBarController.swift`
Expected: eight closures, each naming one distinct handler, in the argument order `requestWiFiNameAccess`, `requestBluetoothAuthorization`, `openBatterySettings`, `openWiFiSettings`, `openLocationSettings`, `openBluetoothSettings`, `openSettings`, `openSoundSettings`. A duplicated or swapped name here is the silent wrong-pane bug this step exists to catch.

- [ ] **Step 4: Run the guard again**

Run: `bash scripts/check-forbidden-patterns.sh 2>&1 | grep -c StatusBarController || true`
Expected: `0`.

- [ ] **Step 5: Run the suites that build the popover**

Run: `swift test --filter SettingsRowHitAreaTests`
Run: `swift test --filter PopoverScrollTargetsTests`
Expected: both PASS. These two construct `StatusPopoverView` with the same argument labels (`Tests/StatusTrioCoreTests/SettingsRowHitAreaTests.swift:16`, `PopoverScrollTargetsTests.swift:16`), so a label or type change fails here.

- [ ] **Step 6: Build and commit**

```bash
swift build
git add Sources/StatusTrioCore/UI/StatusBarController.swift
git commit -m "fix(ui): pass popover handlers as explicit closures

Eight MainActor-isolated handlers were passed to StatusPopoverView as bare
method references. AGENTS.md forbids the pattern and docs/swift-ci-compatibility.md
records the IRGen crash it caused on the CI toolchain (run 34758026894).

Each argument is now an explicit closure calling the same method. quitAction
is unchanged: it is a stored closure, not a method reference."
```

---

### Task 3: Rewrite `SettingsDisclosureRow`'s Button Action

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Settings/SettingsDisclosureRow.swift`

**Interfaces:**
- Consumes: `scripts/check-forbidden-patterns.sh` from Task 1.
- Produces: no new API. `toggle()` keeps its signature and body; only the `Button` action expression changes.

- [ ] **Step 1: Confirm RED for this file only**

Run: `bash scripts/check-forbidden-patterns.sh 2>&1 | grep SettingsDisclosureRow`
Expected: one line, `SettingsDisclosureRow.swift:62`.

- [ ] **Step 2: Rewrite the action as an explicit closure**

```swift
        Button(action: { toggle() }) {
```

State the reason in the plan's review notes and keep the code comment short: `SettingsDisclosureRow` conforms to SwiftUI's `View` protocol, which is declared `@preconcurrency @_Concurrency::MainActor` (`SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface:17482`), so the global actor is inferred for the type and `toggle()` is MainActor-isolated. `SettingsDisclosurePresentation` in the same file is a plain `enum` and is not involved — leave it alone.

- [ ] **Step 3: Run the guard again**

Run: `bash scripts/check-forbidden-patterns.sh 2>&1 | grep SettingsDisclosureRow || true`
Expected: no output.

- [ ] **Step 4: Run the disclosure-row tests**

Run: `swift test --filter SettingsDisclosureRowTests`
Run: `swift test --filter SettingsRowHitAreaTests`
Expected: both PASS. `SettingsDisclosureRowTests.swift:6-47` pins the rotation and accessibility values produced by `SettingsDisclosurePresentation`; `SettingsRowHitAreaTests.testDisclosureRowUsesFullRowHitArea` (`Tests/StatusTrioCoreTests/SettingsRowHitAreaTests.swift:60-85`) pins that the row is still a 300 pt-wide hit target, which is what an accidental `.buttonStyle` or `.contentShape` move would break.

- [ ] **Step 5: Commit**

```bash
swift build
git add Sources/StatusTrioCore/UI/Settings/SettingsDisclosureRow.swift
git commit -m "fix(settings): pass the disclosure row toggle as an explicit closure

SettingsDisclosureRow conforms to SwiftUI's MainActor-isolated View protocol,
so toggle() is MainActor-isolated and Button(action: toggle) formed a function
value from it. Same fix as the popover handlers."
```

---

### Task 4: Rewrite The Two `dismiss.callAsFunction` Sites

**Files:**
- Modify: `Sources/StatusTrioCore/UI/WiFiNetworkListView.swift`

**Interfaces:**
- Consumes: `scripts/check-forbidden-patterns.sh` from Task 1.
- Produces: no new API. `dismiss` keeps its `@Environment(\.dismiss)` declaration at :273.

- [ ] **Step 1: Confirm RED for this file only**

Run: `bash scripts/check-forbidden-patterns.sh 2>&1 | grep WiFiNetworkListView`
Expected: two lines, `WiFiNetworkListView.swift:286` and `:294`.

- [ ] **Step 2: Rewrite both actions**

```swift
                Button(localization.string(.wifiActionOpenSettings), action: { dismiss() })
```

```swift
                    Button(localization.string(.commonCancel), action: { dismiss() })
```

`action: { dismiss() }` is behavior-identical to `dismiss.callAsFunction`: the same `DismissAction` is invoked, on the same actor, exactly once per click. Do not change the alert's structure, its button order, or its `role:`; those are user-visible.

- [ ] **Step 3: Run the guard again**

Run: `bash scripts/check-forbidden-patterns.sh 2>&1 | grep -c callAsFunction || true`
Expected: `0` — the rule has no allowlist entry for `callAsFunction` on purpose.

- [ ] **Step 4: Run the Wi-Fi view suites**

Run: `swift test --filter SettingsRowHitAreaTests`
Run: `swift test --filter WiFiClassifierTests`
Expected: both PASS. `SettingsRowHitAreaTests.testWiFiDetailsToggleUsesFullRowHitArea` hosts the Wi-Fi list and measures its controls; `WiFiClassifierTests` pins the controller behavior behind the alert.

- [ ] **Step 5: Commit**

```bash
swift build
git add Sources/StatusTrioCore/UI/WiFiNetworkListView.swift
git commit -m "fix(wifi): invoke the alert dismiss action through an explicit closure

dismiss.callAsFunction is a reference to a MainActor-isolated SDK method
(@_Concurrency.MainActor on DismissAction.callAsFunction), and the conversion
to a function value is compiled in our module - the same codegen path as the
recorded IRGen crash. action: { dismiss() } is behavior-identical."
```

---

### Task 5: Enforce The Guard From The Test Suite And The Repo Test Script

Enforcement does not go through a workflow file. `.github/workflows/release.yml` is owned exclusively by the release-pipeline plan (`2026-09-20-release-pipeline-hardening.md`, finding R-10) and `.github/workflows/ci.yml` exclusively by the CI-gate plan (`2026-09-20-test-gate-workflow.md`, finding R-15), so this plan must not edit either. Running the guard from inside `swift test` is strictly better anyway: every path that runs the suite — release.yml's `Run tests` step (`:242-256`), the pull-request gate, and a local `swift test` — enforces the rule with no workflow edit and no shared-file conflict.

**Files:**
- Create: `Tests/StatusTrioCoreTests/ForbiddenPatternGuardTests.swift`
- Modify: `scripts/test.sh`

**Interfaces:**
- Consumes: `scripts/check-forbidden-patterns.sh` (clean at this point) and its `--self-test` mode from Task 1.
- Produces: a failing `swift test` whenever the pattern reappears, in every workflow that runs the suite.

- [ ] **Step 1: Assert the tree is clean before switching the gate on**

Run: `bash scripts/check-forbidden-patterns.sh`
Expected: exit code 0, no violation lines. If this fails, do not wire the gate — finish Tasks 2-4 first.

- [ ] **Step 2: Add the enforcement test**

Create `Tests/StatusTrioCoreTests/ForbiddenPatternGuardTests.swift`, using the subprocess and `#filePath` conventions the suite already uses (`Tests/StatusTrioCoreTests/SingleInstanceGuardTests.swift:79-100` spawns `/usr/bin/python3`; `Tests/StatusTrioCoreTests/TestSupport/SocialCoverSheet.swift:28` derives the package root from `#filePath`):

```swift
import XCTest

/// Runs the AGENTS.md forbidden-pattern guard as part of `swift test`.
///
/// This is the enforcement point, deliberately not a workflow step: every CI
/// job and every local run that executes the suite runs the guard, and the
/// workflow files stay owned by their own plans.
final class ForbiddenPatternGuardTests: XCTestCase {
    func testSourcesContainNoActorIsolatedMethodReferences() throws {
        let result = try runGuardScript(arguments: [])
        XCTAssertEqual(
            result.status,
            0,
            "scripts/check-forbidden-patterns.sh reported violations:\n\(result.output)"
        )
        XCTAssertTrue(
            result.output.contains("No forbidden actor-isolated method references found"),
            result.output
        )
    }

    func testGuardSelfTestPasses() throws {
        let result = try runGuardScript(arguments: ["--self-test"])
        XCTAssertEqual(
            result.status,
            0,
            "the guard's own precision self-test failed:\n\(result.output)"
        )
    }

    /// `<package root>/Tests/StatusTrioCoreTests/<this file>`.
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func runGuardScript(arguments: [String]) throws -> (status: Int32, output: String) {
        let script = packageRoot.appendingPathComponent("scripts/check-forbidden-patterns.sh")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: script.path),
            "the guard script is missing from this checkout"
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.currentDirectoryURL = packageRoot
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Read before waiting: a full pipe would deadlock waitUntilExit().
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
```

- [ ] **Step 3: Run the enforcement test**

Run: `swift test --filter ForbiddenPatternGuardTests`
Expected: PASS, two tests.

- [ ] **Step 4: Prove the enforcement test detects a regression**

Temporarily change one rewritten argument back in `Sources/StatusTrioCore/UI/StatusBarController.swift`:

```swift
                requestWiFiNameAccess: handleRequestWiFiNameAccess,
```

Run: `swift test --filter ForbiddenPatternGuardTests`
Expected: FAIL with `scripts/check-forbidden-patterns.sh reported violations:` followed by `Sources/StatusTrioCore/UI/StatusBarController.swift:208: violation: handleRequestWiFiNameAccess`. This compiles, which is the point: the guard catches a shape the compiler accepts. Revert the edit.

- [ ] **Step 5: Call the guard from `scripts/test.sh` as well**

`scripts/test.sh` currently runs `swift test` (with an optional filter argument). Add the guard before the `swift test` invocation, and keep it unconditional so a filtered run still enforces the rule:

```bash
# Enforce the AGENTS.md rule the CI toolchain needs: never pass an
# actor-isolated method as a function value (docs/swift-ci-compatibility.md).
bash "$SCRIPT_DIR/check-forbidden-patterns.sh"

if [[ $# -gt 0 ]]; then
    swift test --filter "$1"
else
    swift test
fi
```

- [ ] **Step 6: Verify the wiring locally**

Run: `bash scripts/test.sh`
Expected: the guard prints `No forbidden actor-isolated method references found under <package root>/Sources` and exits 0, then `swift test` runs the full suite to PASS, including `ForbiddenPatternGuardTests`.

- [ ] **Step 7: Commit**

```bash
git add Tests/StatusTrioCoreTests/ForbiddenPatternGuardTests.swift scripts/test.sh
git commit -m "test: enforce the forbidden-pattern guard from the test suite

ForbiddenPatternGuardTests runs scripts/check-forbidden-patterns.sh and its
--self-test mode as part of swift test, so the actor-isolated method-reference
rule is enforced by every job that runs the suite, including the release
workflow's Run tests step and the pull-request gate, without editing a workflow
file owned by another plan. scripts/test.sh also runs the guard before swift test."
```

---

### Task 6: Non-Publishing Release Preflight And CI Record

**Files:**
- Modify: `docs/swift-ci-compatibility.md` (only if the preflight fails)

**Interfaces:**
- Consumes: the branch from Tasks 1-5.
- Produces: the acceptance evidence that the CI toolchain compiles the rewritten call sites.

- [ ] **Step 1: Run the full suite and the release build locally**

Run: `swift test`
Run: `swift build -c release`
Expected: both PASS. Local passing is not acceptance; it only removes the cheap failures before spending a CI run.

- [ ] **Step 2: Push the branch**

```bash
git push -u origin fix/actor-method-reference-compliance
```

- [ ] **Step 3: Trigger the non-publishing preflight**

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref fix/actor-method-reference-compliance \
  -f version=1.3.0 \
  -f build=13 \
  -f publish=false
```

`build=13` is greater than the published appcast build (9) and greater than `Support/Info.plist`'s current value (11), which the release rules require. Do not create a release from this run.

- [ ] **Step 4: Watch the run**

```bash
gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: `Run tests` succeeds (it now runs `ForbiddenPatternGuardTests` inside the suite, so a reappearing method reference fails this stage), then `Build, sign, notarize, and publish` and `Upload release artifacts` succeed, no Release is published and `appcast.xml` is unchanged.

- [ ] **Step 5: Record the outcome in the incident log**

If the preflight fails in `Run tests` or in the build step, append a row to the failure table in `docs/swift-ci-compatibility.md` with the run ID, the failed stage, the root cause, the fix and the follow-up verification run — the format is fixed by the "失败记录规则" section at lines 44-54. If the preflight passes, append a short subsection under "失败记录" recording the run ID, the counts (tests passed) and that this branch changed no behavior; that record is what lets the next worker skip re-litigating the pattern.

- [ ] **Step 6: Commit the record**

```bash
git add docs/swift-ci-compatibility.md
git commit -m "docs: record the method-reference preflight result

Non-publishing preflight on fix/actor-method-reference-compliance: the guard
and the full test suite pass on macos-26 / Xcode 26.6 / Swift 6.3.3, and the
eleven rewritten call sites compile there."
```

---

## Verification

- `bash scripts/check-forbidden-patterns.sh` exits 0 with zero violations, and `--list` shows four allowlisted and the reviewed `external` sites.
- `bash scripts/check-forbidden-patterns.sh --self-test` exits 0, proving the guard flags `handleThing`, `toggle` and `dismiss.callAsFunction` while ignoring `removeObserver`, `isOutputDevice`, `projectCandidate`, `networkConfiguration(interface:)`, `URL.init(string:)`, keypaths and stored-closure arguments.
- `swift test` and `swift build -c release` pass.
- `git diff` on `Sources/` contains only the eleven rewrites and no changed signatures, no changed `@objc` attributes, no reordered arguments other than the closure bodies, and no `StatusPopoverView` property changes.
- The non-publishing release preflight on `fix/actor-method-reference-compliance` passes: `Run tests` exercises `ForbiddenPatternGuardTests`, which runs the guard and its self-test, and Step 4 of Task 5 records the failure that a reintroduced method reference produces there.
- `docs/swift-ci-compatibility.md` carries the run ID and the outcome.

## Out of Scope

- Category (b): stored closure properties forwarded as function values (`Button(action: onOpenBatterySettings)` and the other audited sites). They are not method references, they cannot produce an isolation thunk, and rewriting them would be churn.
- Category (c): nonisolated method references (`observers.forEach(notificationCenter.removeObserver)`, `.filter(isOutputDevice)`, `.compactMap(projectCandidate)`, `.map(networkConfiguration(interface:))`) and `.init` references. Verified safe; the allowlist exists so they are visible in `--list` output rather than silently ignored.
- Any behavior change to the popover, the settings rows, the Wi-Fi alerts, or the menu bar icon. This plan is a codegen-shape change only.
- Replacing `StatusBarController`'s `@objc` handlers with SwiftUI-native observation; that is a separate refactor with its own risk surface.
- The menu bar ↔ Dock parity work for icon options (see `2026-09-20-icon-parity-and-lifecycle-tests.md`) and the fixed-sleep test hardening (see `2026-09-20-fixed-sleep-test-hardening.md`).
- Release notes: this change is not user-visible, so no `release-notes/1.3.0/` entry is added.

## File Ownership & Conflicts

Owned by this plan:

| File | Change |
| --- | --- |
| `scripts/check-forbidden-patterns.sh` | new |
| `Sources/StatusTrioCore/UI/StatusBarController.swift` | eight argument expressions in `installPopoverContentIfNeeded()` |
| `Sources/StatusTrioCore/UI/Settings/SettingsDisclosureRow.swift` | one `Button` action |
| `Sources/StatusTrioCore/UI/WiFiNetworkListView.swift` | two `Button` actions |
| `Tests/StatusTrioCoreTests/ForbiddenPatternGuardTests.swift` | new |
| `scripts/test.sh` | one guard invocation |
| `docs/swift-ci-compatibility.md` | one record entry |

Conflicts and sequencing:

- `Sources/StatusTrioCore/UI/StatusBarController.swift` is also owned by `2026-09-20-menubar-render-key-normalization.md` (R-07). The review index fixes the order: **this plan lands first**; R-07 rebases and keeps only its render-key call-site edits. Do not run both workers on this file at once.
- `.github/workflows/release.yml` is owned exclusively by `2026-09-20-release-pipeline-hardening.md` (R-10) and `.github/workflows/ci.yml` exclusively by `2026-09-20-test-gate-workflow.md` (R-15). This plan edits neither: enforcement rides inside `swift test` through `ForbiddenPatternGuardTests`, which every job that runs the suite picks up for free. If R-10's hardening rewrites the `Run tests` step, it must keep running `swift test` (and therefore the guard); if R-15's gate adds a separate lint job, that job may call `bash scripts/check-forbidden-patterns.sh` directly instead of waiting for the suite — a useful speed-up, not a second source of truth.
- `scripts/test.sh` is unclaimed by any other plan in the 2026-09-20 set, so the one-line call added in Task 5 Step 5 does not contend with anyone. Keep it: it fails in under a second, before a full build, when someone runs the repo's own test entry point.
- `docs/superpowers/plans/2026-09-20-review-findings-index.md` owns the plan map; do not edit it from this branch.
- No plan in the set owns `Sources/StatusTrioCore/UI/StatusPopoverView.swift`, so this plan may not change the property declarations there — and does not need to.
