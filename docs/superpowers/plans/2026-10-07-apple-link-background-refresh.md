# Apple Link Background Refresh Implementation Plan

> Approved execution: one implementation worker, `ccs-token-unlimited-com/gpt-6-luna`, in the existing worktree. Keep this file's progress ledger current and include actual RED/GREEN command output in the final handoff.

**Goal:** Add opt-in 1–10 minute Apple battery refresh while the popover is closed, with shared demand, cancellation, retained fresh readings, privacy gates, and a conservative cross-source display projection.

**Architecture:** Extend the existing `SettingsStore`, Bluetooth settings, `SystemStatusStore`, BLE scanner, trusted mobile battery controller, and Apple/Bluetooth row projections. A single demand policy composes foreground popover visibility with background preference, master/global gates, Bluetooth availability, and visible/selected/hidden identities; settings is never a read-demand owner. Keep BLE UUID and trusted phone/watch identity separate; deduplicate only display rows when a normalized meaningful name and compatible device family/model produce one unambiguous pair.

**Tech Stack:** Existing SwiftPM app, Swift 6.3-compatible Swift/SwiftUI/Combine/CoreBluetooth and Swift Testing.

**Spec:** User-approved Apple Link background-refresh requirements in the initiating request; existing identity/catalog constraints in `docs/superpowers/specs/2026-10-06-apple-device-battery-design.md`. The supplied design file name differs from the request's shorthand path; this is the extant approved document.

## Global Constraints

- Work only in `/Users/lingsmbp/.codex/worktrees/nearby-ble-allowlist/status-trio`, branch `codex/nearby-ble-allowlist`, starting HEAD `f7af1cd47c061b7f72f13c558189392d986336ee`.
- Preserve all 54 pre-existing uncommitted integration edits, UUID dedup, and valid-battery-only rows. Never overwrite the baseline diff or original app SHA under `.build/apple-link26-verification`.
- Do not commit, push, run CI, merge, publish, release-build, universal-build, or package. Parent owns full verification after focused tests.
- Respect CI compatibility: macOS 26 SDK minimum; no isolated deinit, no actor-isolated methods passed directly as function values, and no weakening unrelated helper-PID1s or pixelFingerprint assertions.
- All 12 shipped locales receive the new background-refresh toggle and interval copy. Interval is 1–10 whole minutes; default 1; toggle defaults off and only appears under the Apple devices master toggle.
- Settings never starts discovery, battery reads, or demand. With background off, only an actually open Bluetooth status popover with master/global/list gates can own battery demand.
- Preserve current future-only `nextVerifiedRowExpiration(now:)` behavior and its expiration tests. Fresh snapshots survive viewport/read-authorization changes and popover closure for 20 minutes; real disable/hide/removal still revokes private snapshots and stale callbacks.
- Do not infer identity or ownership from battery equality, generic model, global name, or hardcoded name heuristics. Never report “not nearby” from missing snapshots, failures, or a closed popover.

## Review Focus

1. Concurrent foreground/background triggers, scan completion, settings changes, sleep and Bluetooth loss must not overlap jobs or allow stale callbacks to publish.
2. Saved settings interval values must clamp to 1–10 and missing values default to 1 without resetting a value when the toggle is switched off and back on.
3. Same-name cross-source candidates collapse only as one compatible, unique BLE/trusted pair; two same-named trusted phones, battery-only matches, incompatible models, and unresolved temporary names remain independent.
4. An empty/changed viewport must not erase a fresh snapshot or create a false “not nearby” state, while explicit hide/disable/remove revokes it.
5. A late GATT formal name must update the row keyed by original UUID and must not leave an advertised temporary name as persisted metadata.

## Execution Steps

### Step 1: Settings and persistence

Files: `Settings/SettingsStore.swift`, `UI/Settings/BluetoothSectionView.swift`, all 12 `Resources/*.lproj/Localizable.strings`, relevant SettingsStore/localization tests.

- [ ] Add failing persistence tests for background toggle default-off, 1-minute default, valid interval persistence across OFF/ON, and invalid low/high stored values clamping to 1/10.
- [ ] Run the focused tests and capture the expected RED failure before production edits.
- [ ] Add localized toggle visible only while `showsAppleDevicesAndBattery` is on and interval stepper visible only while background refresh is on; persist interval independently of toggle.
- [ ] Run focused settings/localization tests and capture GREEN output; verify all 12 resource locales have both new localized values.

### Step 2: Shared foreground/background demand and periodic lifecycle

Files: `Store/SystemStatusStore.swift`, `Monitoring/BluetoothDeviceController.swift`, `Monitoring/BluetoothLEBatteryScanner.swift`, `Monitoring/MobileBatteryController.swift`, `Monitoring/AppleDeviceDiscoveryController.swift`, `UI/BluetoothStatusView.swift`, `UI/StatusPopoverView.swift`, focused controller/lifecycle tests.

- [ ] First add deterministic-clock integration tests for OFF/settings-no-demand, open-popover demand, closed-panel background intervals, no overlap, master/global/list gates, excluded hidden IDs, Bluetooth unavailable/sleep cancellation, resume without catch-up burst, and trusted phone/watch plus BLE refresh.
- [ ] Run focused tests and record RED output before changes.
- [ ] Route both surfaces through existing demand APIs with Settings excluded. Retain at most two BLE connections, bounded scans/connections, timeout, 60-second retry, shared in-flight tasks, cancellation revisions, and interval-based trusted helper reads; no continuous scanning. Separate “currently permitted” from “metadata/read is fresh” so 20-minute initial suppression cannot block background updates.
- [ ] Run the new controller integration suite plus related existing demand, scan cadence, panel visibility, helper controller, and sleep tests; capture GREEN output.

### Step 3: Privacy-safe cache and state presentation

Files: `Monitoring/MobileBatteryController.swift`, `Models/AppleDeviceCatalog.swift`, `UI/MobileBatteryDeviceRows.swift`, related lifecycle/catalog tests.

- [ ] Add failing tests proving fresh cached valid battery data is immediately shown on open, survives popover close/viewport-empty/read-ID changes for 20 minutes, refreshes after the intended cooldown, expires after its cache lifetime, and is purged only for explicit privacy revocation; check stale generations cannot publish.
- [ ] Run focused RED tests before implementation.
- [ ] Keep read authorization revocation separate from metadata freshness and snapshot lifetime. Do not purge because viewport/read IDs become empty; retain expired-state distinction without claiming “not nearby” on absent reads or closed surfaces. Continue exposing only valid battery rows.
- [ ] Remove iPhone updated/source timestamps and trusted phone/iPad/watch update-time subtitles. Keep AirPods channel/charging presentation and ordinary Bluetooth row style unchanged.
- [ ] Run focused GREEN lifecycle and presentation tests; preserve the future-only row-expiration contract.

### Step 4: Shared cross-source display projection and formal-name updates

Files: `UI/BluetoothDeviceListPresentation.swift`, `UI/BluetoothStatusView.swift`, `Monitoring/BluetoothLEBatteryScanner.swift`, `Models/AppleDeviceCatalog.swift`, relevant presentation/scanner/catalog tests.

- [ ] Add failing projection tests for unique normalized meaningful compatible BLE/trusted pairs, ambiguous same-name phones, battery-only and generic-model nonmatches, independent aliases for read routing/hide/order, and preserved UUID/UDID/watch-parent identity.
- [ ] Add failing late-rename test proving a current formal peripheral/GATT name updates the existing UUID row rather than appending another or retaining a temporary advertised label. Examine AirBattery's `BLEBattery.swift`, `AirBatteryModel.getAll/updateDevice` only as local reference; do not copy global exact-name identity or watcher exclusion.
- [ ] Run focused RED tests before production edits.
- [ ] Integrate one shared display projection into the existing presentation model; select best metadata/readings without merging source identities. Avoid name blacklists/ownership claims. If no identity link resolves a temporary candidate name, safely defer that unresolved display candidate rather than guessing. Explore GATT 2A00 only if necessary.
- [ ] Run focused GREEN projection, scanner, hide/order, and UUID identity tests.

### Step 5: Focused handoff verification

- [ ] Run only focused affected test groups, not `swift test` or `swift build -c release`; parent owns full verification.
- [ ] Run `git diff --check` and compare changed paths against the recorded original 54-file set; leave pre-existing edits intact and the branch uncommitted.
- [ ] Verify `.build/apple-link26-verification` contents and app hashes are unchanged; do not create any app build/package artifact.
- [ ] Report exact focused test counts, actual RED/GREEN log paths, changed absolute paths, remaining risks, the runtime-reported model, and that full verification remains with parent.

## Progress Ledger

- Baseline: branch `codex/nearby-ble-allowlist`, HEAD `f7af1cd47c061b7f72f13c558189392d986336ee`; 54 tracked paths already modified. Baseline diff artifact: `.build/apple-link26-verification/pre-change.diff` (244,320 bytes).
- Protected artifacts verified before edits: `/Applications/Status Trio.app/Contents/MacOS/StatusTrio` SHA-256 `885baf8e7378719bcf7c84f54378f2f6f6f591818d093eda1541d07831b37c27`; `dist/development/Status Trio (Apple Link).app/Contents/MacOS/StatusTrio` SHA-256 `299b46a6c8e51be1d0ca23e6155d4aab72c51fe79a7063e385cf993f04b189a7`; original DMG SHA-256 `273b74cd41b4d236a38d59da67401a173ec4382d778c1bbd7b42c8639418f590`. All match `.build/apple-link26-verification` manifests.
- Approval: user explicitly approved design and implementation; no further confirmation required. This session is the sole implementation worker on the configured `ccs-token-unlimited-com/gpt-6-luna` route; no delegation or model discovery is needed.
- Skill note: worktree has vendored TDD, executing-plans, SwiftUI, Swift Testing, and worktree skills. `swift-concurrency-pro` exists only at `/Users/lingsmbp/.codex/skills/swift-concurrency-pro`; its actor/cancellation/structured guidance was read. Worktree already is an isolated linked worktree.
- Plan path correction: the existing Apple device design is `docs/superpowers/specs/2026-10-06-apple-device-battery-design.md`; the user request's shorthand name without `-design` does not exist.
- Current status: implementation underway in the sole configured `ccs-token-unlimited-com/gpt-6-luna` worker. No commits or out-of-worktree changes.
- Runner incident and resolution: under the earlier workspace-write resume, four attempts failed before test execution (`sandbox_apply: Operation not permitted`, protected module cache). Coordinator identified the resume sandbox reset. Under the current danger-full-access resume, `swift test --disable-sandbox --filter ...` runs normally. No package or production changes were made for the environment issue.
- TDD order note: settings production/UI/localization edits preceded the first runnable test because runner failure occurred before execution. Reproduced a surgical RED by temporarily changing only the new default to `true`, running `swift test --disable-sandbox --filter SettingsStoreTests/testAppleBackgroundRefreshDefaultsOffAndIntervalDefaultsToOneMinute`, observing `XCTAssertFalse failed` at the new test, then restoring the implementation. The accepted GREEN is `swift test --disable-sandbox --filter SettingsStoreTests`: 85/85.
- Valid RED: `swift test --disable-sandbox --filter MobileBatteryControllerTests/testReleasingTemporaryViewportRetainsFreshCachedSnapshot` failed two assertions because `setAuthorizedDeviceIDs([])` and closing the surface cleared level 74. Implemented retained snapshots on temporary permit loss plus explicit `revokeDeviceIDs`; focused controller suite now passes 20/20.
- Valid RED: `swift test --disable-sandbox --filter SystemStatusStoreTests/testSettingsMasterToggleDoesNotStartAppleDiscoveryOrBatteryReads` failed `XCTAssertFalse(discovery.isDiscovering)` and discovery count `1`, proving master-only Settings demand. Store now separates eligibility from demand; focused test passes 1/1.
- Projection tests were added after production helper shape was established because the runner was initially unavailable; `BluetoothDeviceListPresentationTests` passes 28/28, including exact unique-pair merge and ambiguous/battery-only nonmerge.
- Additional focused GREEN evidence: `MobileBatteryPresentationTests` 8/8; `AppleDeviceCatalogTests` 10/10 (including pending status without snapshot); `BluetoothLEBatteryScannerStateTests` 10/10 (including formal-name precedence); `LocalizationParityTests` 4/4; SettingsStoreTests 85/85; MobileBatteryControllerTests 20/20.
- Store master-off compatibility is restored and verified: `SystemStatusStoreTests/testDisablingAppleMasterStopsMetadataDiscoveryAndRevokesMobileReads` passes 1/1. Background closed-panel ownership test passes 1/1 after explicitly waiting for the async discovery reader count; it asserts discovery with zero selected reads, then selected-ID read, then stop when a master gate closes.
- Final targeted GREEN snapshot: `MobileBatteryControllerTests` 20/20; `BluetoothDeviceListPresentationTests` 28/28; `MobileBatteryPresentationTests` 8/8; `AppleDeviceCatalogTests` 10/10; `BluetoothLEBatteryScannerStateTests` 10/10; `SettingsStoreTests` 85/85; `LocalizationParityTests` 4/4. These are focused filters only, not the full suite.
- BLE controller demand suite: `swift test --disable-sandbox --filter NearbyBLEControllerDemandTests` passed 13/13, covering Settings token no-demand, foreground visible permits, hidden callback rejection, background refresh of a fresh saved UUID, scan stop/resume on system sleep, and radio/master gates. Store suite passes 65/65; trusted controller 20/20; shared list projection 29/29; scanner state/name 10/10; settings 85/85; mobile presentation 8/8; Apple catalog 10/10; localization parity 4/4.
- Final serial focused verification (all green): `SystemStatusStoreTests` 65/65 (`/tmp/apple-link-system-store-green.log`); `MobileBatteryControllerTests` 20/20 (`/tmp/apple-link-mobile-controller-green.log`); `BluetoothDeviceListPresentationTests` 29/29 (`/tmp/apple-link-list-presentation-green.log`); `NearbyBLEControllerDemandTests` 13/13 (`/tmp/apple-link-nearby-demand-green.log`); `BluetoothLEBatteryScannerStateTests` 10/10 (`/tmp/apple-link-scanner-green.log`); `SettingsStoreTests` 85/85 (`/tmp/apple-link-settings-green.log`); `LocalizationParityTests` 4/4 (`/tmp/apple-link-localization-green.log`); `AppleDeviceCatalogTests` 10/10 (`/tmp/apple-link-catalog-green.log`); `MobileBatteryPresentationTests` 8/8 (`/tmp/apple-link-mobile-presentation-green.log`). RED evidence logs are `/tmp/apple-link-step1-surgical-red.log`, `/tmp/apple-link-step3-red.log`, `/tmp/apple-link-step2-settings-red.log`, and `/tmp/apple-link-step4-projection-red.log`; settings/some architecture had to be implemented before a usable runner existed, and this is recorded above.
- Sleep behavior verified separately: store-level `willSleep`/`didWake` test confirms trusted USB/Wi-Fi discovery is independent from Bluetooth radio sleep; BLE controller test confirms BLE scanner stops and resumes on sleep/wake. Wake does not trigger an extra trusted helper cycle; the next configured interval is used.
- Final bounded worker: BLE readings now rank by `NearbyBluetoothBatteryDevice.lastUpdated`, not a stale panel-row timestamp or render-time `Date()`. Persisted panel levels are fallback-only when the live BLE cache has no entry and their actual timestamp is present, valid, and no older than 20 minutes; future readings are rejected. Extracted the canonical-first external-status choice into the presentation function used by `BluetoothDeviceRow`, with inverse canonical/source assertions. Cross-source identity matching remains unchanged.
- Regression RED: `/tmp/apple-link26-final-presentation-red.log` ran 35 presentation tests and failed only the new inverse-timestamp assertion (`Optional(20)` selected instead of live BLE `Optional(18)`). GREEN: `/tmp/apple-link26-final-presentation.log`, 35/35.
- Final serial focused GREEN runs: `SystemStatusStoreTests` 68/68 (`/tmp/apple-link26-final-store.log`); `MobileBatteryControllerTests` 21/21 (`/tmp/apple-link26-final-controller.log`); `SettingsStoreTests` 85/85 (`/tmp/apple-link26-final-settings.log`). Total 209 tests, 0 failures. An initial store run exposed that the foreground fixture omitted the Bluetooth-section gate; the fixture now explicitly enables it and passes. The controller test now waits for the asynchronous cancellation callback and asserts no subsequent cadence read.
- This worker's bounded code/test paths: `Sources/StatusTrioCore/UI/BluetoothDeviceListPresentation.swift`, `Sources/StatusTrioCore/UI/BluetoothDeviceRow.swift`, `Tests/StatusTrioCoreTests/BluetoothDeviceListPresentationTests.swift`, `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift`, and `Tests/StatusTrioCoreTests/MobileBatteryControllerTests.swift`. This ledger is the only additional path changed during handoff.
- Handoff checks: `git diff --check` passed. `shasum -a 256 -c .build/apple-link26-verification/preserved-apps.sha256` verified both protected app executables; `shasum -a 256 -c .build/apple-link26-verification/build25.sha256` verified the protected DMG. No baseline artifact was written. No full test suite, release build, CI, package, install, commit, push, or release was run; parent owns broader verification and review.

## Parent local verification and packaging handoff — 2026-10-08

- After final review, Luna completed foreground partial-alias hiding before source-catalog filtering, immediate authorization revocation and rejection of late callbacks; stale Settings/master-only lifecycle fixtures were corrected without weakening the forbidden-pattern guard. Latest bounded pass: 125 focused tests green (5 discovery, 12 lifecycle, 2 guard, 36 presentation, 70 store). Reviewer Locke rechecked stable source and found no remaining blocker; hardware behavior remains unverified.
- Fresh `swift test` exited 0: 1201 XCTest cases, 6 skipped, 0 failures; 558 Swift Testing cases passed in 88 suites. Log: `/tmp/apple-link26-full-test-final.log`.
- Fresh `swift build -c release` exited 0. Log: `/tmp/apple-link26-release-build.log`. Universal build via `scripts/build-app.sh release no-open` exited 0 with build 26, version 1.4.0, codename Apple Link, bundle ID com.lingsmbp.StatusTrio.dev.apple-link, Developer ID signing; app/helper architecture, platform metadata and packaged-runtime checks passed. Log: `/tmp/apple-link26-universal-build.log`. Native helper / dependency-parser / rpath shell checks also passed: `/tmp/apple-link26-native-helper-checks.log`.
- Toolchain: local Xcode 27.0 / Swift 6.4, SDK 27.0. This is local testing evidence, NOT CI Xcode 26.6 / Swift 6.3.3 proof. No CI, commit, push, merge or publication. Existing protected app and build-25 DMG manifests remain unchanged.
- Notarization BLOCKED: initial `notarytool history --keychain-profile status-trio-notary` succeeded; later submit and explicit-login-keychain history queries report `No Keychain password item found for profile: status-trio-notary`. No submission ID was returned. Signing identity remains valid. Do not label build 26 notarized or distribute it as a notarized test package. No credential values were read, printed or stored.
- Local-only signed DMG is prepared under `/Users/lingsmbp/Downloads/Status-Trio-Apple-Link-1.4.0-26-Test/`, with filename ending `-Local-Test.dmg` and explicit limitation in 测试说明.txt. User must confirm/restore the saved notarization profile before app/DMG notarization and stapling can finish.

### Notarization recovered and accepted — 2026-10-08

- User confirmed they had not changed `status-trio-notary`. A fresh history query succeeded without changing the saved profile or keychain settings. The earlier lookup failure no longer reproduces; its cause is not established, so do not report a deleted credential or claim a proven lock/timeout cause.
- App notarization accepted: `5f0e5eb5-4884-4edc-b757-08f41ffa6dba`. App stapling and validation passed; Gatekeeper reports `accepted`, `source=Notarized Developer ID`.
- Final DMG rebuilt with the stapled app, signed, notarized and stapled: submission `8b466a5f-5e69-4c71-bc59-ee87331b9a37` accepted. DMG staple validation and Gatekeeper primary-signature assessment passed. This supersedes the earlier blocked packaging status.
- Final distribution artifact: `/Users/lingsmbp/Downloads/Status-Trio-Apple-Link-1.4.0-26-Test/Status-Trio-Apple-Link-1.4.0-26.dmg`. The `-Local-Test.dmg` is retained only as the older unstapled artifact. No original app/build-25 artifact was overwritten; no source code changed during notarization recovery, and no CI, commit, push or public release was performed.

## Build 27 interval-value follow-up — 2026-10-08

- User reported the interval row shows arrows but no value. Root cause: localized value Text was inside Stepper's label and `.labelsHidden()` suppressed it. Luna (`ccs-token-unlimited-com/gpt-6-luna`) moved it into a visible sibling Text in HStack, kept 1–10 bounds/binding/gates, matched 13pt numeric styling and added localized accessibility value. Only production change is this row; regression added to AppleDeviceSettingsTests.
- RED: `/tmp/apple-link27-interval-red.log`, new regression failed with 4 issues, exit 1. Focused GREEN: 85 SettingsStoreTests + 11 AppleDeviceSettingsTests, exit 0 (`/tmp/apple-link27-interval-green.log`). This is a source-structure regression, not live screenshot verification.
- Fresh full `swift test` passed: 1201 XCTest cases, 6 skipped, 0 failures; 559 Swift Testing cases in 88 suites. Fresh Release and universal builds passed. Logs: `/tmp/apple-link27-full-test.log`, `/tmp/apple-link27-release-build.log`, `/tmp/apple-link27-universal-build.log`. Local Xcode 27.0 / Swift 6.4 only; no CI, commit, push or publication.
- App notarization accepted `2de9eaa1-35ee-4c76-8776-9e00c9613457`; DMG notarization accepted `67cf167b-06ad-4a21-a671-db58470270c5`. Both stapled and validated; Gatekeeper accepted. Read-only mounted final DMG confirms inner app build 27, arm64/x86_64, minos 15.0 / SDK metadata 26.0; app signature and ticket valid.
- Final artifact: `/Users/lingsmbp/Downloads/Status-Trio-Apple-Link-1.4.0-27-Test/Status-Trio-Apple-Link-1.4.0-27.dmg`. SHA256: `0a870d553e85c720d5756fc14060e13c3da1cfb08ed965945c33b1caec4f98c1`. All original protected apps, build 25 and build 26 SHA manifests matched. User should quit old Apple Link, install 27 and verify the actual displayed minute value changes with the arrows.

### Source-only interval title follow-up — 2026-10-08

- User requested exact Simplified Chinese title “后台更新电量的时间间隔”. Luna updated only settings.appleBackgroundRefresh.interval in all 12 locales, with Simplified Chinese exact wording, Traditional Chinese “背景更新電量的時間間隔”, English “Background battery refresh interval”. Minute-value formats, toggles, UI structure and interval behavior unchanged.
- Regression added to AppleDeviceSettingsTests: appleRefreshIntervalTitleNamesBackgroundBatteryRefreshInChinese. RED exited 1 with 2 assertion issues; GREEN passed. Parent freshly verified 19 localization/parity XCTest cases plus 1 charging localization Swift test (`/tmp/apple-link-label-parent-verification.log`) and the exact new Chinese-label test 1/1 (`/tmp/apple-link-label-exact-parent-verification.log`). `git diff --check` clean.
- No packaging, CI, commit or push for this copy-only follow-up. Existing build-27 notarized DMG SHA256 remains unchanged, so the delivered build 27 still uses its old title; new wording will enter the next package.

### User-requested local commit — 2026-10-08

- User explicitly requested committing the code. Parent performed fresh pre-commit verification: `swift test` exited 0 (1201 XCTest cases, 6 skipped, 0 failures; 560 Swift Testing cases in 88 suites), `swift build -c release` exited 0, `git diff --check` and forbidden-pattern guard passed. Logs: `/tmp/apple-link-precommit-test.log`, `/tmp/apple-link-precommit-release.log`.
- Commit scope is all current related Apple Link source, localization, regression tests and documentation on codex/nearby-ble-allowlist, including the pre-existing BLE integration changes retained throughout this task. No built artifacts or signing credentials are staged.
- Local commit only: no push, merge, CI dispatch or release. CI Xcode 26.6 / Swift 6.3.3 verification remains required before merge/publication; the local Xcode 27.0 / Swift 6.4 checks are not a substitute. Existing notarized build 27 remains unchanged and does not contain the latest interval-title copy.
