# 2026-09-20 Code Review — Findings Index and Plan Set

> **For agentic workers:** This file is the **spec** for the twenty plans listed below. If you were handed one of those plan files, read this file first: it holds the verified evidence, the cross-plan file-ownership matrix, and the merge order. Each plan is written to be executable **independently by a different worker**.

**Review scope:** all of `Sources/` (18,398 lines across 126 Swift files) plus `Tests/` (20,487 lines), scripts and CI as sampled.
**Review revision:** `13cdbbc` (branch `main`, clean working tree).
**Review date:** 2026-09-20.

---

> **Paused 2026-09-20, with a handoff document:** the owner asked to stop after R-01 merged and to write the remainder down. Progress, carry-forward obligations, the twelve untouched plans, the frozen class-C set, the owner's outstanding measurements, resume commands, and every ruling made so far are in [`2026-09-20-class-a-handoff.md`](2026-09-20-class-a-handoff.md). Read that first when resuming.

## 0. Owner decision (2026-09-20): this plan set is on hold

Execution has been **paused by the owner** until they have time to work through it deliberately. Three constraints survive the pause and must be honoured by whoever resumes:

1. **No Apple Developer account exists, so nothing about certificates, notarisation, entitlements or the shipped bundle's signature may change.** The current Ad-hoc status is accepted.
2. **The app has real users and Sparkle auto-update works today — it must keep working.** A change is acceptable only if it provably does not alter what an already-installed copy does, explicitly including its ability to receive updates.
3. **Nothing is to be started yet.** The set is written and parked; this is a long task, not an urgent one.

### Classification against those constraints

| Class | Meaning | Plans |
| --- | --- | --- |
| **C — frozen until the owner schedules it** | Touches signing/packaging, the update trust chain, or the release path in a way that needs owner action in repository settings | R-11 build signing (**frozen: no Developer account; every step changes the shipped signature**), R-08 signed feed (**frozen: changes the update contract for any build that ships it, and permanently fixes the EdDSA key**), R-10 release pipeline (needs owner action on environment/tag protection), R-09 fallback policy (**the owner must first weigh losing mirror availability, which is what users on restricted networks depend on**) |
| **B — user-visible, ship carefully and watchfully** | Changes something a user can observe, or has already stored | R-12 keychain migration (the user's saved Wi-Fi passwords), R-13 lock-failure alert and clipboard behaviour, R-03 default refresh interval (how fresh the menu bar icon looks) |
| **A — user-invisible, safe to start first** | Performance, correctness, tests and CI that no user can observe | R-01, R-02, R-04, R-05, R-06, R-07, R-14, R-15, R-16, R-17, R-18, R-19, R-20 |

### When execution resumes

- Start with **R-18** — it is the one item that can block shipping anything else — then the rest of class A.
- Class C stays parked until the owner unpauses it. If R-08 is ever unparked, the acceptance bar is: a copy of the previously released build still updates successfully from the newly published feed, verified **before** the change reaches users.
- The wave order in §3.2 still applies; it was constructed so that every worker within a wave touches disjoint files.
- The two workspace files dirtied outside this task (`Tests/StatusTrioCoreTests/DockIconStateStripTests.swift` and `Tests/StatusTrioCoreTests/TestSupport/DockIconStateStrip.swift`) belong to unrelated concurrent work. They compile and their tests pass; leave them alone.

---

## 1. Baseline evidence (verified during the review — do not re-derive)

| Check | Command | Result |
| --- | --- | --- |
| Debug build | `swift build` | passes, no errors |
| Full build incl. tests | `swift build --build-tests --scratch-path /tmp/st-review-build` | passes; **7 warning locations in 4 diagnostic kinds** (see R-20) |
| Test suite | `swift test --scratch-path /tmp/st-review-build` | **149 tests / 26 suites pass**, ~1.0 s of test time, ~17 s wall including the build check |
| Installed app at idle | `top -l 20 -s 1 -pid <StatusTrio>` | avg **0.125 % CPU**, **25 MB RSS**, 5–6 threads, cumulative `idlew` 0 |

Two conclusions that shape every plan:

1. **The steady-state architecture is already efficient.** The idle measurement is good, so no plan may propose an architectural rewrite of the event-driven monitors. Each fix is a bounded correction to a specific path that escaped the existing discipline.
2. **The installed app being measured is 1.2.1 / build 10, not the working tree (1.3.0 / build 11).** Re-measure after any change lands; do not cite the numbers above as post-change evidence.

Toolchain facts that gate acceptance (from `AGENTS.md` and `docs/swift-ci-compatibility.md`):

- CI: `macos-26` runner, Xcode 26.6, Swift 6.3.3. Local: Xcode 27, Swift 6.4. **A local build is not proof.**
- Forbidden: `isolated deinit`, `IsolatedDeinit`, `weak let`, actor-isolated method references as function values, assuming `Bundle.module` lproj casing.
- The app must build against the macOS 26 SDK or newer (issue #40).
- `swift test` + `swift build -c release` before every commit of Swift changes.
- Non-publishing release preflight is the acceptance gate for changes touching actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics or `Bundle.module` resources:

  ```bash
  gh workflow run release.yml --repo lingyired/status-trio --ref <branch> \
    -f version=1.3.0 -f build=12 -f publish=false
  gh run watch <run-id> --repo lingyired/status-trio --exit-status
  ```

- Menu bar ↔ Dock icon parity is a hard rule: any icon-rendering or icon-setting change must update both paths and both test sets in the same change.
- User-visible changes need an entry in the in-flight `release-notes/1.3.0/en.md` and `release-notes/1.3.0/zh-Hans.md` (each starting with a `# <title>` line containing `%VERSION%` and `%BUILD%`). All 12 languages are required only for `publish=true`.

### 1.1 Experiments already performed (do not repeat, do not contradict)

**A. `/usr/sbin/system_profiler -json SPBluetoothDataType` cost** — three runs: 0.07 s, 0.12 s, 0.14 s wall (0.02 s user each). **Context that makes this a best case:** on the measured machine the report contained `device_connected: 0` and `device_not_connected: 6`. `system_profiler` queries connected devices (including their battery levels) over the Bluetooth link, so runs with one or more connected devices are expected to be substantially slower than the numbers above. Two consequences: (i) R-01's savings are larger in practice than the measured figures suggest, and (ii) because a run can plausibly exceed the 15 s interval, the missing in-flight latch turns from a theoretical concern into a process pile-up — which is why both halves of R-01 must land together.

**B. Hardened runtime on the ad-hoc release path is NOT a free win** — measured on a throwaway copy of `dist/StatusTrio.app` under `/tmp` (never the real bundle):

| Step | Result |
| --- | --- |
| `codesign --force --sign - --options runtime` (framework, then app) | accepted: `flags=0x10002(adhoc,runtime)`, `Runtime Version=15.0.0`, `TeamIdentifier=not set`; `codesign --verify --strict` still passes |
| launch that bundle | **fails**: `dyld: Library not loaded: @rpath/Sparkle.framework/... (code signature ... not valid for use in process: mapping process and mapped file (non-platform) have different Team IDs)` |
| re-sign the app with `--options runtime --entitlements <plist with com.apple.security.cs.disable-library-validation>` | launches (no dyld diagnostic; the process reaches `applicationDidFinishLaunching` and exits because the installed instance holds the single-instance lock) |

Consequences a worker must respect: the existing `if [[ "$SIGNING_IDENTITY" != "-" ]]` guard in `scripts/build-app.sh` is load-bearing, not sloppiness; "always add `--options runtime`" would ship a non-launchable app; the only ad-hoc hardening path is runtime **plus** `disable-library-validation`, which explicitly trades library validation away and is therefore not an injection defence. Never verify a signing change by inspecting flags alone — always launch the built bundle.

---

## 2. Finding → plan map

Severity is the reviewer's judgement after reading the code; "verified" means the reviewer re-read the cited lines. `P#`/`S#`/`C#`/`T#`/`W#` are the identifiers used in the review report.

| ID | Sev | Finding | Plan file | Owned files |
| --- | --- | --- | --- | --- |
| **R-01** | P1 High | Bluetooth polls `/usr/sbin/system_profiler` every 15 s and never stops after the popover closes; no in-flight latch; `deinit` leaks observers and leaves CoreBluetooth running | `2026-09-20-bluetooth-polling-and-lifetime.md` | `Monitoring/BluetoothDeviceController.swift`, `Monitoring/BluetoothBatteryReader.swift`, `MonitorProtocols.swift`, `Store/SystemStatusStore.swift`¹, Bluetooth tests |
| **R-02** | P2 High | The Wi-Fi page re-runs a full all-channel `scanForNetworks` on every ~5 s status yield, including after navigating back, plus a `networksetup` subprocess per scan; no-interface Macs rebuild the whole CoreWLAN event stack every 30 s forever | `2026-09-20-wifi-scan-cadence.md` | `Monitoring/WiFiNetworkController.swift`, `Monitoring/WiFiMonitor.swift`², `UI/StatusPopoverView.swift`, Wi-Fi tests |
| **R-03** | P3 High | Unconditional 5 s fallback poll with no `tolerance` and no visibility gating (battery + CoreWLAN + `SCDynamicStore` + CoreAudio on every tick); `liveVolume` republished while unchanged | `2026-09-20-status-poll-scheduling.md` | `Store/SystemStatusStore.swift`, `Settings/SettingsStore.swift`, `App/AppEnvironment.swift`, `SystemStatusStoreTests.swift`, `SettingsStoreTests.swift`, `release-notes/1.3.0/*`. Design: default 5 s → 15 s, `interval/5` tolerance, battery every tick with Wi-Fi/volume every 4th hidden tick, skip while the display is asleep |
| **R-04** | P4 High | Settings preview tiles rasterize 512² Dock images inside SwiftUI `body`: ~4 renders per body evaluation, ~84 per slider drag, 30 pt tile from a 512 px bitmap; onboarding grid renders ~10 per evaluation | `2026-09-20-icon-preview-rendering.md` | `UI/Icon/DockIconRenderer.swift`, `UI/Icon/DockIconRenderCache.swift`¹¹, `UI/IconPreviewComponents.swift`, `UI/Settings/StatusIconPreviewCard.swift`, `UI/IconGuideView.swift` (card only), new `UI/Icon/DockIconPreviewCache.swift`, 4 new test files. **Deliberately not modified:** `SettingsVisualPreviews.swift`, `AppIconSectionView.swift` |
| **R-05** | P5 Medium | 2 s appearance poll with no `tolerance` → 43,200 precisely-timed wakeups/day for a cheap preference read | `2026-09-20-appearance-poll-tolerance.md` | `App/SystemIconAppearanceMonitor.swift` |
| **R-06** | P6 Medium | Main-actor CoreAudio HAL IPC (`eventMonitor.reconcile()`) blocks the menu bar run loop and defeats `ReadWatchdog`; `MainActor.assumeIsolated` inside `VolumeMonitor.deinit` is a latent fatal trap | `2026-09-20-volume-monitor-main-actor-io.md` | `Monitoring/VolumeMonitor.swift`, `Monitoring/WiFiMonitor.swift`², `VolumeMonitorTests.swift`, `VolumeMonitorAsyncTests.swift` |
| **R-07** | P7 Medium | Menu bar render cache keys on raw `rssi`/volume scalar instead of the quantized values that are actually drawn (the Dock path already normalizes bars/steps, but see the caveat below) | `2026-09-20-menubar-render-key-normalization.md` | `UI/Icon/StatusBarRenderCache.swift`, `UI/StatusBarController.swift`³ (gate reorder only), `Tests/StatusTrioCoreTests/StatusBarRenderCacheTests.swift`, `release-notes/1.3.0/*`. Adds a **second gate** for the VoiceOver value, which reads SSID/percentage/`isCharged` — values that are not pixels and today sit behind the image gate, so normalizing the key alone would have been a regression |
| **R-08** | S1 High | Update feed is neither signed nor verified (`SURequireSignedFeed` absent) although Sparkle supports signed feeds; a feed writer can roll users back to any genuinely signed older build, or replace release notes. **`SUVerifyUpdateBeforeExtraction` must land in the same change** — `SPUUpdater.m:373-386` makes `SPUUpdater` fail with `SUInvalidUpdaterError` when `SURequireSignedFeed` is YES without it, and `UpdaterManager.swift:52-56` turns that into a modal alert at launch. Consequence to accept deliberately: it also makes the EdDSA key permanent, because rotating it would require a Developer ID-signed DMG (`Autoupdate/AppInstaller.m:289-296`), which this repo cannot produce | `2026-09-20-signed-update-feed.md` | `Support/Info.plist`, `appcast.xml`⁴, `scripts/release.sh`⁴ (2 inserted lines), new `scripts/sign-appcast.sh`, new `scripts/verify-signed-appcast.rb`, new `scripts/verify-app-bundle-plist.sh`, new `Tests/StatusTrioCoreTests/SignedUpdateFeedTests.swift`, `release-notes/1.3.0/*` |
| **R-09** | S2 High | Update fallback silently sends appcast + DMG requests through third-party mirrors on *any* URL error (including TLS failures and cancellation), and never resets the source | `2026-09-20-update-source-fallback-policy.md` | `App/UpdateSourceFallback.swift`, `App/UpdaterManager.swift`, `App/AppDelegate.swift`⁹, `Settings/SettingsStore.swift`¹², `Localization/LocalizationKey.swift` + 12 `Localizable.strings`¹³, `UI/Settings/GeneralSectionView.swift`, 4 test files, 12 `release-notes/1.3.0/*.md`¹⁴ |
| **R-10** | S3 High | Release job hands the EdDSA private key to whatever code the dispatched ref contains; no protected environment; `security import -A`; workflow-scope `contents: write`; floating action tags | `2026-09-20-release-pipeline-hardening.md` | `.github/workflows/release.yml` |
| **R-11** | S4 Medium | Shipped builds get no hardened runtime and no entitlements (which turns out to be **deliberate and load-bearing**, see §1.1), are signed `--deep`, and the SDK stamp is a hardcoded `26.0` that makes the SDK assertion tautological; docs teach users to strip quarantine | `2026-09-20-build-signing-hardening.md` | `scripts/build-app.sh`, `scripts/verify-platform-version.sh`, `README.md`, `AGENTS.md` |
| **R-12** | S5 Medium | Keychain protection class is requested but not honoured (legacy keychain, no data-protection keychain, no `ThisDeviceOnly`); two deprecated Security APIs; system-keychain fallback has no test at all | `2026-09-20-keychain-hardening.md` | `Monitoring/WiFiPasswordStore.swift`, `Tests/StatusTrioCoreTests/WirelessListModelsTests.swift` (keychain test only), new `KeychainWiFiPasswordStoreTests.swift`, `Package.swift`, `release-notes/1.3.0/*`. **No change to `WiFiNetworkController.swift` is needed** — verified by the plan author |
| **R-13** | S6 Low | Single-instance lock lacks `O_NOFOLLOW`/`S_IFREG` validation and fails silently with no way to distinguish "already running" from "lock broken"; network details copied to the general pasteboard without a transient marker | `2026-09-20-single-instance-and-pasteboard.md` | `App/SingleInstanceGuard.swift`, `App/AppDelegate.swift`⁹, `UI/WiFiNetworkListView.swift`, new `App/LockProbe.swift`, new `App/ConcealedPasteboard.swift`, `Localization/LocalizationKey.swift` + 12 `Localizable.strings`, `Sources/StatusTrio/main.swift`, `SingleInstanceGuardTests.swift`, new `PasteboardConcealmentTests.swift`, `release-notes/1.3.0/*` |
| **R-14** | C6 Medium | Suspected use-after-free: `BatteryMonitor` releases the callback context while an IOPS callback may still be executing | `2026-09-20-battery-callback-teardown-investigation.md` | new `Tests/StatusTrioCoreTests/BatteryCallbackTeardownTests.swift`, new `docs/battery-callback-teardown.md`, `Monitoring/BatteryMonitor.swift` **only if confirmed**. Deliberately does not touch `BatteryMonitorTests.swift` |
| **R-15** | T1 High | The only workflow runs on tags and manual dispatch, so ~20k lines of tests have no automatic gate | `2026-09-20-test-gate-workflow.md` | `.github/workflows/ci.yml` (new) |
| **R-16** | T2 High | Two `AppIconControllerTests` sync with a fixed 900 ms sleep against a 0.5 s debounce (one is the documented CI flake; the other passes for the wrong reason); same pattern in three more test files | `2026-09-20-fixed-sleep-test-hardening.md` | `AppIconControllerTests.swift`, `App/AppIconController.swift`⁸, `UI/MainMenuController.swift`⁸, `SystemIconAppearanceMonitorTests.swift`⁶, `MainMenuControllerTests.swift`, `BatteryMonitorTests.swift`⁵ |
| **R-17** | T3/T5 Medium | The preflight appcast validator exits 0 when release notes are missing while `release.sh` then hard-fails (the recorded `35375443023` root cause) — the notes check at `release.sh:142-147` runs **before** the `PUBLISH=false` exit at `:238-241`, so the skip has no legitimate escape hatch and is removed outright. Second defect: **nothing enforces** the invariant that the published appcast and the committed copy agree (they are byte-identical today, sha256 `2f4bf90d…`, newest item 1.2.0/build 9 — so this is not existing drift, but the preflight validates a document containing no 1.3.x item) | `2026-09-20-preflight-validator-and-appcast-sync.md` | `scripts/validate-appcast-notes.sh`, new `scripts/check-appcast-sync.sh`, `scripts/release.sh`⁴, new `Tests/StatusTrioCoreTests/ReleaseScriptsTests.swift`, `docs/swift-ci-compatibility.md` |
| **R-18** | C1 High | **Release blocker candidate:** eight actor-isolated methods are passed as function values into `StatusPopoverView` (plus `SettingsDisclosureRow.toggle` and `WiFiNetworkListView`'s two `dismiss.callAsFunction` sites); `AGENTS.md` forbids it and the identical shape crashed CI IRGen in run `34758026894` | `2026-09-20-toolchain-method-reference-compliance.md` | `UI/StatusBarController.swift`³ (lines ~208-215 only), `UI/Settings/SettingsDisclosureRow.swift`, `UI/WiFiNetworkListView.swift`, `scripts/test.sh`¹⁵, new `scripts/check-forbidden-patterns.sh`, new `Tests/StatusTrioCoreTests/ForbiddenPatternGuardTests.swift`, `docs/swift-ci-compatibility.md` |
| **R-19** | T7 Medium | No test enumerates the icon option enums to enforce menu bar ↔ Dock parity, and no test covers `deinit`/teardown behaviour | `2026-09-20-icon-parity-and-lifecycle-tests.md` | new `Tests/StatusTrioCoreTests/IconOptionParityMatrixTests.swift`, new `Tests/StatusTrioCoreTests/TestSupport/CountingNotificationCenter.swift`, new `Tests/StatusTrioCoreTests/IconSurfaceLifetimeTests.swift`, `IconRenderCoalescerTests.swift`, `App/SystemIconAppearanceMonitor.swift`⁶ (Task 3 only), `docs/swift-ci-compatibility.md`. Uses the sanctioned `nonisolated(unsafe)` + shared `tearDownRegistrations()` pattern — **no `assumeIsolated`**. Deliberately leaves `DockIconRenderCacheTests.swift` and `Issue13IconParityTests.swift` untouched |
| **R-20** | W1 Low | **7 warning locations in 4 diagnostic kinds:** `String(cString:)` deprecation in `AudioOutputDeviceIcon.swift`; two `kSecUseAuthenticationUI*` deprecations in `WiFiPasswordStore.swift` (owned by R-12); four `weak var` never-mutated warnings in tests that collide with the `AGENTS.md` `weak let` rule | `2026-09-20-compiler-warning-cleanup.md` | `Audio/AudioOutputDeviceIcon.swift`, `AudioOutputDeviceIconTests.swift`, new `Tests/StatusTrioCoreTests/DeinitProbe.swift`, `WiFiClassifierTests.swift` (2 lines), `VolumeMonitorTests.swift`⁷ (1 line), `VolumeMonitorAsyncTests.swift`⁷ (1 line), `docs/swift-ci-compatibility.md`, `AGENTS.md` (rule line only) |

Superscripts mark files that more than one plan touches — see §3.

---

## 3. File-ownership matrix and merge order

### 3.1 Shared-file conflicts (must be sequenced, never run in parallel by two workers)

| File | Plans | Rule |
| --- | --- | --- |
| `UI/StatusBarController.swift` ³ | R-07, R-18 | **R-18 lands first.** It rewrites the handler arguments; R-07 then rebases and keeps its own edits to the render-key call site only. |
| `scripts/release.sh` ⁴ | R-08, R-17 | **R-08 lands first** (it changes how the appcast is generated/signed). R-17 then adjusts the validator contract and the working-copy sync. |
| `Store/SystemStatusStore.swift` ¹ | R-01, R-03 | **R-03 lands first** (it restructures the poll loop and visibility gating). R-01 rebases and only changes the Bluetooth activation/deactivation rules. |
| `Monitoring/WiFiMonitor.swift` ² | R-02, R-06 | Either order, but not simultaneously. R-02 owns the recovery-loop logic; R-06 owns `deinit`/thread-affinity. Split by function, not by file, and review both diffs together. |
| `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift` ⁵ | R-16 only | R-14 deliberately puts its harness in a **new** file (`BatteryCallbackTeardownTests.swift`) rather than editing this one, which removes the conflict entirely. R-16 owns this file. |
| `Tests/StatusTrioCoreTests/SystemIconAppearanceMonitorTests.swift` ⁶ | R-05, R-16 | R-05 owns the production timer change; R-16 owns the test synchronization change. Land R-16 first so R-05's new timing test starts from deterministic helpers. |
| `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`, `VolumeMonitorAsyncTests.swift` ⁷ | R-06, R-20 | R-06 owns the production change and may add tests; R-20 touches only the `weak var` warning lines. Land R-06 first. |
| `UI/Icon/DockIconRenderer.swift` | R-04, R-19 | R-19 may only change production code if a new test proves a real bug. Land R-04 first. |
| `UI/WiFiNetworkListView.swift` | R-13, R-18 | Same file, disjoint regions (R-18: lines ~286 and ~294 `dismiss.callAsFunction`; R-13: line ~351 pasteboard). Either order; R-18 is wave 1, so R-13 rebases onto it. |
| `App/AppIconController.swift` ⁸ | R-16, R-19 | **R-16 owns production changes** (injectable `snapshotDebounceInterval`). R-19 may add lifetime tests but must rebase on R-16 and must not add seams of its own here. |
| `App/SystemIconAppearanceMonitor.swift` ⁶ | R-05, R-16, R-19 | R-05 owns the timer change, R-16 owns the test synchronization rewrite in its test file, R-19 may pin the `stop()` contract. **No worker may add `MainActor.assumeIsolated` to this type's `deinit`** — see §3.4. |
| `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift` | R-02, R-06, R-20 | Three-way, split by function: R-02 adds cadence tests, R-06 adds one additive test + fake, R-20 edits exactly two warning lines (:701, :1148). Land R-02 and R-06 first; R-20 rebases. |
| `App/AppDelegate.swift` | R-01, R-13 | Different concerns (R-13: lock-failure alert + exit path; R-01: Bluetooth teardown). Land R-13 in wave 1, R-01 rebases. |
| `AGENTS.md` | R-11, R-20 | Disjoint sections: R-11 owns the quarantine/Gatekeeper guidance, R-20 owns the `weak let` rule line (~45). Either order. |
| `docs/swift-ci-compatibility.md` | R-06, R-14, R-18, R-20 | **Append-only.** Never rewrite another plan's rows; add yours at the end of the failure table. |
| `release-notes/1.3.0/en.md`, `release-notes/1.3.0/zh-Hans.md` ¹⁴ | R-03, R-07, R-09, R-13 (and any plan that changes user-visible behavior) | **Append-only.** Add one bullet each; do not reorder or reword existing bullets. Keep both language files in sync in the same commit. |
| `App/AppEnvironment.swift` | R-03 only | The third copy of the default refresh interval (`AppEnvironment.makeStore`). Assigned to R-03 by both R-03's and R-01's plans. |
| `UI/Icon/DockIconRenderCache.swift` ¹¹ | R-04, R-07 | R-04 adds a **defaulted** `pixelLength` to `DockIconRenderKey`; R-07's parity matrix compares against that key. Land R-04 first so the defaulted parameter exists, then R-07. |
| `Localization/LocalizationKey.swift` + the 12 `Resources/*.lproj/Localizable.strings` | R-09, R-13 | Append-only. Any new key must be added to **all 12** `.strings` files in the same commit (the build script counts `InfoPlist.strings` files but does not check key parity — so this is on the worker). |
| `Package.swift` | R-12 only | Adding `.linkedFramework("LocalAuthentication")`. No other plan should touch the manifest. |
| `Settings/SettingsStore.swift` ¹² | R-03, R-09 | R-03 (wave 1) changes the default refresh interval; R-09 (wave 3) adds the mirror-disclosure preference. Land R-03 first. |
| `App/AppDelegate.swift` ⁹, `Localization/LocalizationKey.swift` + 12 `Localizable.strings` ¹³ | R-09, R-13 | R-13 (wave 1) adds lock-failure strings and the `main.swift` probe; R-09 (wave 3) adds the disclosure row. **Append-only** for the `.strings` files and `LocalizationKey.swift`; every new key goes into all 12 languages in the same commit. |
| `appcast.xml` ⁴ | R-08, R-17 | R-08 signs the feed (feed-level `sparkle:edSignature`); R-17 adds the sync contract. R-08 first, R-17 rebases. |
| `scripts/test.sh` ¹⁵ | R-18 only | Unclaimed by any other plan, so the forbidden-pattern guard can call it from here. R-18 deliberately does **not** edit `release.yml` (R-10) or `ci.yml` (R-15); instead the guard is enforced from inside `swift test` via a test target, so both the release job and the future PR gate pick it up with zero workflow edits. |
| `Sources/StatusTrio/main.swift` | R-13 only | The lock-probe entry point. |

### 3.2 Recommended waves

Workers in the same wave touch disjoint files and can run in parallel.

- **Wave 1 — unblock the release path and stop the bleeding**
  R-18 (toolchain compliance + forbidden-pattern guard), R-15 (test gate), R-03 (poll scheduling), R-01 (Bluetooth polling), R-04 (icon preview rendering), R-12 (keychain), R-13 (single instance + pasteboard).
- **Wave 2 — finish the performance and trust work**
  R-02 (Wi-Fi cadence), R-06 (main-actor audio IO), R-05 (appearance poll), R-07 (render key, after R-18), R-08 (signed feed), R-10 (release workflow hardening), R-16 (fixed sleeps).
- **Wave 3 — remainder and hardening**
  R-17 (validator + appcast sync, after R-08), R-09 (fallback policy), R-11 (build signing + SDK stamp), R-14 (battery investigation), R-19 (parity + lifecycle tests, after R-04), R-20 (warning cleanup, after R-06).

### 3.3 Per-plan acceptance (identical for every plan)

1. `swift test` and `swift build -c release` pass.
2. `bash scripts/validate-appcast-notes.sh` passes for anything touching appcast/release notes.
3. A non-publishing release preflight passes whenever the plan touches actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics or `Bundle.module` resources — and therefore for **every plan in this set that changes Swift code**, because all of them touch at least `@MainActor` types. When in doubt, run the preflight.
4. Any failed CI run is appended to `docs/swift-ci-compatibility.md` with run ID, failed stage, root cause, fix and verification.
5. Behavior changes are measured, not assumed: for performance plans, re-run the idle `top` sample (and `powermetrics` where the plan asks for it) before and after, and record both numbers in the PR or commit message.

### 3.4 Worker prohibitions (learned the hard way during this review)

These are not style preferences — each one was either measured or is recorded in `docs/swift-ci-compatibility.md`:

1. **Never add `MainActor.assumeIsolated` to a `deinit`.** It is a fatal assertion, not a hop, and `deinit` runs on whichever thread drops the last reference. Use `nonisolated(unsafe)` teardown-owned storage plus a plain `deinit` (the pattern at `Store/SystemStatusStore.swift` lines ~32, ~78-85), or keep `stop()` as the only teardown path and pin that contract with a test. R-06 removes one such site; no other plan may add one.
2. **Never enable the hardened runtime on the ad-hoc path without `com.apple.security.cs.disable-library-validation`.** Measured: it makes the app fail to load `Sparkle.framework` (`different Team IDs`) and therefore not launch at all. See §1.1 B.
3. **Never verify a signing or packaging change by inspecting metadata alone.** `codesign -dv` showing `flags=0x10002(adhoc,runtime)` was true for a bundle that could not launch. Always launch the built bundle and confirm the menu bar icon appears and the popover opens.
4. **Never pass an actor-isolated method as a function value**, including `dismiss.callAsFunction`. Use `{ dismiss() }`. This is the R-18 release-blocker class.
5. **Never assume a `@MainActor` protocol makes a conforming class's witnesses nonisolated.** Verified by the R-06 author with `swiftc -typecheck -swift-version 6`: a plain class conforming to a `@MainActor` protocol is inferred to be main-actor-isolated at the type level, so "just mark the witnesses `nonisolated`" does not compile as intended. Use a `@MainActor` façade plus a `nonisolated` `@unchecked Sendable` helper.
6. **Never accept a fixed `sleep` as synchronization in a test.** The repo's compatibility doc mandates polling the target state with a bounded cap; the helpers already exist (`waitForRender`, `waitForCoalescedRenders`, `ManualSleeper`, `ManualWiFiClock`, `ManualEventSleeper`, `ReadCounter`).

---

## 4. What is explicitly NOT a finding

Recording these here prevents a worker from "fixing" something that is already correct:

- **The Dock render key is not fully normalized either.** `DockIconRenderKey` (`Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift` lines 4-57) quantizes `wifiBars` and `volumeSteps`, but when `volumeOptions.displayStyle == .arc` it stores the raw clamped volume scalar in `volumeArcProgress` (lines 49-51). So the Dock path is the right *model* for R-07, not a finished implementation: R-07 must decide explicitly whether to normalize the arc progress too (a pixel-bucket argument) or to record why it deliberately stays raw. Also note `DockIconImageCache` is keyed by `DockIconRenderKey` alone and therefore has no notion of pixel size — R-04 must add the pixel length to the key (or use a separate cache per size) rather than reusing it unchanged.
- **No password leakage path.** Three `Logger`s exist, none logs credentials, SSIDs, BSSIDs or device names; there is no `print`/`NSLog` anywhere. Passwords never enter `UserDefaults`, `@Published` state, or error text.
- **No command injection.** The only two subprocesses use absolute paths with constant argv (`/usr/sbin/system_profiler -json SPBluetoothDataType`, `/usr/sbin/networksetup -listpreferredwirelessnetworks <ifName>`); no shell is invoked, and SSIDs never reach a path, URL, format string or shell word.
- **No local IPC surface.** No XPC/mach service, no distributed notifications, no URL scheme, no AppleScript handler; the only file created is the 0600 lock file.
- **TCC timing is correct.** Location is requested only from an explicit user action while `.notDetermined`; CoreBluetooth starts only when a Bluetooth surface opens; both purpose strings match actual use.
- **`IconRenderCoalescer` is correct.** Main-actor bound, keeps the newest request, no dropped final state, no AppKit off-main.
- **`ReadWatchdog`'s abandoned-thread trade-off is documented** in its own header comment and is a deliberate design decision, not an oversight. Do not restructure it without measurement.
- **The test suite's deterministic-wait infrastructure and env-gated sheet/asset generation are good**; extend them rather than replacing them.

---

## 5. Corrections to the original review (found while writing these plans)

Recorded so a worker does not act on a claim the review got wrong. Each was verified by reading code, by measurement, or by the plan author's own check.

| Original claim | Reality |
| --- | --- |
| "exactly 4 build warnings" | **7 warning locations in 4 diagnostic kinds.** Two of the seven are the `kSecUseAuthenticationUI*` deprecations owned by R-12, so "warning-free" is only reachable once R-12 and R-20 both land. |
| "the shipped build has no hardened runtime; always pass `--options runtime`" | **Wrong and dangerous.** It makes the app fail to load `Sparkle.framework` (`different Team IDs`) and therefore never launch. The existing identity guard in `scripts/build-app.sh` is load-bearing. The only ad-hoc path is runtime **plus** `disable-library-validation`, and even that is not an injection defence. See §1.1 B. |
| "the Dock render key already normalizes this" | Only for `wifiBars`/`volumeSteps`. The `.arc` display style still stores a raw clamped volume scalar in `volumeArcProgress`. R-07 is the right model to copy, not a finished implementation. |
| "Sparkle's `generate_appcast` will sign the feed" | **The repo never invokes `generate_appcast`.** `scripts/update-appcast.rb` builds the feed and `scripts/release.sh:199` pipes the key to `sign_update`, so R-08 uses `sign_update`'s feed mode. |
| "the committed appcast has drifted a release behind" | **It has not.** The committed copy and the live feed are byte-identical today (82,865 bytes, sha256 `2f4bf90d…`). The real defect is that nothing *enforces* the invariant, and that `SURequireSignedFeed` needs `SUVerifyUpdateBeforeExtraction` in the same change or `SPUUpdater` refuses to start. |
| "the preflight skip needs a documented escape hatch" | It does not: `scripts/release.sh` checks release notes at `:142-147`, before the `PUBLISH=false` exit at `:238-241`, so no dispatch can succeed without notes. R-17 removes the skip outright. |
| "nine actor-isolated method references" | **Eight** (the ninth argument, `quit: quitAction`, is a stored closure). Plus `SettingsDisclosureRow.toggle` and two `dismiss.callAsFunction` sites. |
| (not noticed in the review) | Normalizing the menu bar render key alone would have introduced an **accessibility regression**: `StatusPresentation.statusItemAccessibilityValue` reads the SSID, the exact percentage and `isCharged`, and those updates sit behind the image gate today. R-07 adds a separate accessibility gate. |
| (not noticed in the review) | `codesign --deep` **propagates the app's entitlements to every nested item** — signing with `--deep --options runtime --entitlements …` gave `Sparkle.framework/Versions/B/Updater.app` an entitlement it does not need. That is the concrete reason to stop signing with `--deep` (R-11). |
| (not noticed in the review) | Enabling `SURequireSignedFeed` makes the EdDSA key **permanent**: rotating it would require a Developer ID-signed DMG (`Autoupdate/AppInstaller.m:289-296`), which this repo cannot produce. Accept this deliberately when landing R-08. |
