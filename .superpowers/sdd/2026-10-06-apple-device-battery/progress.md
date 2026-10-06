# SDD ledger — plan: docs/superpowers/plans/2026-10-06-apple-device-battery.md

## Setup
- Worktree: `/Users/lingsmbp/.codex/worktrees/nearby-ble-allowlist/status-trio`, branch `codex/nearby-ble-allowlist`.
- Plan and approved spec read; spec governs any conflict. User explicitly approved all five tasks and Native inline execution.
- Pre-existing approved BLE subtitle changes reviewed and isolated in commit `8bad074`; `swift test` passed (1,159 tests, 6 skipped, 0 failures), `swift build -c release` passed, and `git diff --check` passed before commit.
- Pre-flight interface row: Task 1 produces typed `AppleDeviceID`/selection/candidate; Task 3 consumes those for scoped read authorization; Task 4 consumes them for source-qualified catalog rows. Signatures and row IDs align across plan sections; no conflict found.
- Pre-flight interface row: Task 2 produces metadata-only `MobileBatteryWire.decodeDiscovery` candidates plus helper discovery CLI; Task 3 consumes discovery through `MobileBatteryReading.discover()`. No conflict found.
- Pre-flight interface row: Task 3 produces explicit selected-ID reader/controller permits; Task 4 routes viewport-visible IDs into those permits. No conflict found.
- Existing requested baseline commits: `efd7054`, `d3f8ac7`; no reset or cleanup performed.

## Task 1
- Start base: `d3f8ac7b592019f9b4dfecda9f501efc78bfb580` (task brief generated before the separate approved BLE subtitle commit; rebase task start base to actual task implementation parent as needed).
- Task 1 Ruling: add explicit `AppleDeviceEvidence` to `AppleDeviceCandidate` — the plan's listed candidate fields do not carry the BLE vendor/trusted-model/watch-provenance needed to validate selection without trusting display names, while the approved spec requires source evidence — cost if wrong: candidate API gains one required field and call sites must propagate verified evidence.
- Task 1 Ruling: add `.bluetooth` to `MobileBatteryTransport` — the approved interfaces use this shared transport type for BLE and trusted candidates, but its pre-existing cases were only USB/network — cost if wrong: enum now represents discovery transport as well as helper transport; existing helper behavior remains unchanged.
- Task 1 Ruling: retain the legacy normalized preference key only for pre-hashed `mobile-<digest>` row IDs — changing it to raw row ID broke existing hidden-row filtering; the provider ID is never normalized or exposed, and exact hashed row IDs still authorize identity — cost if wrong: preference compatibility may need a future migration if the hash scheme changes.
- Task 1 RED: `swift test --filter AppleDeviceSettingsTests` failed on missing `AppleDeviceID`, settings, and selection API (expected).
- Task 1 GREEN: focused Apple settings tests passed (5 tests); `MobileBatteryDeviceMergeTests` passed (15 tests).
- Task 1 full verification: `swift test` → 524 tests across 86 suites passed; 6 skipped, 0 failures. `swift build -c release` passed. `git diff --check` passed.
Task 1: complete (commits 8bad074..3296ff3, tests: swift test → ✔ Test run with 524 tests in 86 suites passed after 5.382 seconds.)

## Task 2 — metadata-only trusted discovery
- RED: `bash scripts/test-mobile-battery-helper.sh` failed to compile because `copyPhoneMetadata` and `STMobileBatteryCopyDiscovery` did not exist; `swift test --filter MobileBatterySnapshotTests` failed because `decodeDiscovery` did not exist.
- GREEN: added a dedicated phone metadata callback, companion metadata-only key list, `--discover-device`, schema 1 candidate envelope, scoped trust/session failures and Swift evidence-qualified decoder. Added iPad, malformed arguments, duplicate, battery-key absence, cleanup and no-parent-battery counter coverage.
- Verification: native helper tests passed (24 cases); `swift test --filter MobileBatterySnapshotTests` passed (13); `bash scripts/check-mobile-battery-dependency.sh '@rpath/libimobiledevice-1.0.6.dylib' '.build/mobile-battery/package/Frameworks/MobileBattery'` passed; full suite at end-of-branch passed (1,164 XCTest, 6 skipped, 0 failures; 539 Swift Testing across 88 suites).
Task 2: complete (commit f7416a7; implementation verified again in final full suite).

## Task 3 — selected-ID reads and lifecycle
- RED: new reader tests failed to compile on absent `read(selectedIDs:)`; controller/discovery tests initially failed because the scoped lifecycle did not yet exist. Tests now assert empty IDs make zero executor calls; Watch-only runs `--list` plus only selected `--read-watch`, never `--read-phone`; metadata discovery issues only `--list` and `--discover-device`; cancellation, dismissal, expiry, authorization revocation and late results are covered.
- GREEN: removed zero-argument protocol read, implemented explicit IDs, selected-phone filtering before limits, exact Watch IDs, isolated metadata discovery controller, per-generation revocation and authorized-only cache/failure publication.
- Verification: `swift test --filter MobileBatteryHelperReaderTests` passed (15 after final candidate-cap addition); `swift test --filter MobileBatteryControllerTests` passed (15); `swift test --filter AppleDeviceDiscoveryControllerTests` passed (2); native helper tests passed (24); final fresh suite passed (1,164 XCTest, 6 skipped, 0 failures; 540 Swift Testing / 88 suites); final `swift build -c release` passed on local Swift 6.4/Xcode 27.0/macOS 27 SDK. CI remains the required Xcode 26.6 / Swift 6.3.3 authority.
Task 3: implementation and verification complete; commit is grouped with the unified integration because API consumers span Tasks 4/5.

## Task 4 — one catalog, picker and panel projection
- RED: initial `AppleDeviceCatalogTests` / `AppleDevicePanelVisibilityTests` did not compile before catalog and viewport APIs. Layout migration first failed where tests expected old Nearby-only initializer and when battery-off rows were expected to disappear; those expectations were updated to the approved keep-row/no-level behavior.
- GREEN: source-qualified candidate union, stable typed row projection, exact battery projection, common list order/hide/limit, actual viewport row frames, visible-ID permits, settings discovery claim and single master toggle wired through `SystemStatusStore`. Ordinary paired devices remain fed directly from the paired controller, not gated by the Apple toggle.
- Verification: `swift test --filter AppleDeviceCatalogTests` passed (4); `swift test --filter AppleDevicePanelVisibilityTests` passed (2); `swift test --filter BluetoothSummaryLayoutTests` passed (11); `NearbyBLEPanelVisibilityTests` (7), `NearbyBLEDeviceCatalogTests` (6), `MobileBatteryDeviceMergeTests` (15), `BluetoothDeviceRowLayoutTests` (9), and `SystemStatusStoreTests` (61) passed. Final fresh suite passed after Apple status rendering changes (1,164 XCTest, 6 skipped, 0 failures; 540 Swift Testing / 88 suites).
Task 4: complete (commit ad1c336).

## Task 5 — localization, documentation and acceptance
- RED: `LocalizationTests.testEveryLanguageHasEveryNonEmptyKey` initially failed for the five new Apple picker keys across all 12 localizations; new semantic assertions cover iPhone/iPad/Apple Watch, no “iWatch”, USB trust and nearby Bluetooth wording.
- GREEN: added all five strings in 12 locales, unified Bluetooth settings toggle/picker, source label “Nearby Bluetooth” / “附近蓝牙”, user documentation on migration, identity, trust, Watch parent session and hardware limits; spec status records approved implementation and pending external acceptance.
- Verification: `swift test --filter LocalizationTests` passed (15); `swift test --filter LocalizationParityTests` passed (4); `swift test --filter AppleDeviceSettingsTests` passed (5); `bash scripts/check-forbidden-patterns.sh` passed; native helper tests passed (24); rpath parser and dependency path checks passed; `VERSION=1.4.0 BUILD=18 PUBLISH=false bash scripts/validate-appcast-notes.sh` passed (12/12 notes); final fresh `swift test` passed (1,164 XCTest, 6 skipped, 0 failures; 540 Swift Testing / 88 suites); final `swift build -c release` passed.
- Environment: local toolchain is Swift 6.4 / Xcode 27.0 / SDK 27. CI-required Xcode 26.6 / Swift 6.3.3 preflight has not been run yet. Published version is 1.4.0/build 17; validation-only appcast check used build 18 and did not publish. Physical iPhone/iPad/Apple Watch hardware is unavailable/unverified in this run.
- Repository's vendored SDD scripts do not include `task-start` or `task-done`; task briefs and ledger were read/updated directly.
Task 5: implementation committed in f1d05e1; external CI preflight, PR #93 push/body update, test-app package/restart and hardware report remain.

Final review: self-review (no subagent tool); parent session will perform a fresh independent review before merge.

## Fresh parent-review follow-up — master switch projection gate
- Finding: `BluetoothStatusView.appleProjection` always received persistent selections. Since the catalog intentionally synthesizes candidates for saved/offline selections, master-off still displayed opt-in Apple rows.
- RED: hosted `BluetoothSummaryLayoutTests.testAppleMasterOffHidesOptInRowsButKeepsPairedRowsAndSelectionCanReturn` failed: master-off layout height was 117pt vs paired-only 91pt.
- GREEN: gate catalog selections/candidates/readings/snapshots/failures at projection input with `showsAppleDevicesAndBattery`; do not mutate SettingsStore selections. Paired system rows stay outside this gate. Re-enabling reprojects retained selection.
- Verification after fix: hosted regression passed; full `swift test` passed (1,165 XCTest, 6 skipped, 0 failures; 540 Swift Testing across 88 suites); `swift build -c release` passed (26.37s); native helper tests passed (24); rpath/dependency checks, appcast notes 12/12, forbidden-pattern guard and `git diff --check` passed.

## Historical failed CI record
- Run `37416172832`, head `27cc07cadbcae8a969b1140508a6899d7a06fbde`, failed at `Run tests`: `DDCVolumePresentationTests.testTopologyChangeClearsConfirmedDDCVolumeAndSelectedRowImmediately` observed stale DDC scalar `0.75` in four post-topology invalidation assertions. This is a test/product event-order failure, not compilation, signature, or runner setup. That head was not modified in response and is not claimed fixed.
- A subsequent `db2bdb4` preflight `37490195329` passed the same test in `Run tests` and completed macOS 26/Xcode 26.6 build/sign/DMG and artifact upload with `publish=false`. Full details are recorded in `docs/swift-ci-compatibility.md`.
