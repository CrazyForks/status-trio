# Apple Device Battery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一个“显示苹果设备与电量”总开关，仅苹果设备的显式勾选列表；选择后加入统一蓝牙面板，只有获选且实际可见的设备可读电量。

**Architecture:** 保留现有 BLE scanner、USB/Wi-Fi helper 和普通配对设备路径。新增来源明确的苹果设备选择目录，先生成无电量的获选行，再由统一视口产生各来源读取许可，解决“先读取才能生成行”的循环。可信 helper 新增纯元数据发现接口，读取接口强制携带精确目标，不把现有全量 read() 当成发现。

**Tech Stack:** SwiftPM、Swift/Combine/SwiftUI/AppKit、Objective-C 原生 helper、Swift Testing/XCTest、现有 libimobiledevice 依赖。

**Spec:** `docs/superpowers/specs/2026-10-06-apple-device-battery-design.md`（用户已于 2026-10-06 审阅通过）。

## Global Constraints

- 实现模型使用用户指定的 `gpt-6-luna`；计划未获审阅前不得写产品实现。沿用 `/Users/lingsmbp/.codex/worktrees/nearby-ble-allowlist/status-trio`，不要切换或覆盖主工作树。
- CI acceptance: runner `macos-26`, Xcode `26.6`, Swift `6.3.3`；SDK ≥26；保留 `build-app.sh` SDK 检查与 `verify-platform-version.sh`。不启用 isolated deinit，不把 actor 方法直接传作函数值。
- 全部 12 个语言更新，中文写 Apple Watch，不写 iWatch。BLE 留作内部技术词；面板不恢复来源副标题。普通已配对设备不受新总开关影响。
- `swift test`、`swift build -c release`、原生 helper 测试必须通过；涉及绑定/actor，合并前运行 `publish=false`。失败 Actions 全部登记 `docs/swift-ci-compatibility.md`。
- 不发布、不合并，不替换正式安装。测试包 ID `com.lingsmbp.StatusTrio.BLETest`；沿用现有版本 1.4.0/build 20 仅作本地测试，不代表发布号。预检号读取当时发布状态后明确选定。
- 现有四个未提交文件是本聊天上一项修改，不丢弃：`BluetoothDeviceRow.swift`、`BluetoothDeviceRowLayoutTests.swift`、`docs/nearby-ble-devices.md`、旧 BLE spec。开始前审阅差异，运行测试/build 后单独提交该已验证修改，再实施下面任务；不混入其他改动。

## Review Focus

1. 只选择 Watch 时，父 iPhone 可建立必要会话，但父电池键和其他 Watch 电池键不得被查询（任务 2/3 的原生计数与 executor 参数测试）。
2. 同名 BLE UUID、可信 UDID、系统地址不得串选择、缓存或电量；当前 `MobileBatteryDeviceMerge` 名称匹配是需替换的风险点（任务 4）。
3. 关闭全局电量开关不能移除获选设备行；滚动离开/隐藏必须撤销两条路径并拒绝迟到结果（任务 3/4）。
4. 非 Apple 或 unknown 的旧选择不得在升级/重启时复活为 Apple；迁移档保留，取消选择不会被再次导入（任务 1）。
5. 未信任、失败、空名、重复或损坏 helper JSON、iPad 返回值不能导致全局错误掩盖其他成功设备或自动授予选择（任务 2/3/4）。

## File Map

| Boundary | Files |
|---|---|
| Source-qualified identity, selection, migration | NEW `Sources/StatusTrioCore/Models/AppleDeviceSelection.swift`; NEW `Sources/StatusTrioCore/Settings/AppleDeviceSettingsMigration.swift`; MODIFY `Settings/SettingsStore.swift`, `Models/BluetoothDeviceIdentity.swift` |
| Metadata-only native discovery | MODIFY `Support/MobileBatteryHelper/NativeBatteryClient.{h,m}`, `main.m`, `tests/NativeBatteryClientTests.m` |
| Scoped trusted reads and discovery lifecycle | MODIFY `Models/MobileBatterySnapshot.swift`, `Monitoring/MobileBatteryHelperReader.swift`, `Monitoring/MobileBatteryController.swift`; NEW `Monitoring/AppleDeviceDiscoveryController.swift` |
| Shared catalog, viewport and settings | NEW `Models/AppleDeviceCatalog.swift`, `UI/AppleDevicePanelVisibility.swift`, `UI/Settings/AppleDeviceSelectionView.swift`; MODIFY `UI/Settings/BluetoothSectionView.swift`, `UI/BluetoothStatusView.swift`, `UI/BluetoothDeviceList.swift`, `UI/StatusPopoverView.swift`, `Store/SystemStatusStore.swift`, `Monitoring/BluetoothDeviceController.swift`, `Models/MobileBatteryDeviceMerge.swift` |
| Copy and documentation | `Localization/LocalizationKey.swift`, every `Resources/*.lproj/Localizable.strings`, `docs/nearby-ble-devices.md`, new spec status |

Paths below are repository relative; root is the isolated worktree above. Existing generic BLE primitives stay internal rather than renaming scanner classes throughout the repository.

## Task 1 — Apple identity, opt-in persistence and migration

**Files:** File-map selection/migration boundary; NEW `Tests/StatusTrioCoreTests/AppleDeviceSettingsTests.swift`; UPDATE `NearbyBLESettingsTests.swift`, `SettingsStoreTests.swift` where old UI expectations conflict.

**Interfaces produced:**
```swift
enum AppleDeviceID: Codable, Hashable, Sendable {
    case ble(UUID)
    case trustedDevice(String)
    case trustedWatch(parentID: String, id: String)
    var rowID: String { get }
}
struct AppleDeviceSelection: Codable, Equatable, Identifiable, Sendable {
    let id: AppleDeviceID
    var name: String
    var model: String?
}
struct AppleDeviceCandidate: Equatable, Identifiable, Sendable {
    let id: AppleDeviceID
    var name: String
    var model: String?
    var transports: [MobileBatteryTransport]
    var trustRequired: Bool
}
// SettingsStore additions:
// @Published var showsAppleDevicesAndBattery: Bool
// @Published private(set) var appleDeviceSelections: [AppleDeviceSelection]
// func setAppleDeviceSelected(_ candidate: AppleDeviceCandidate, selected: Bool)
```
Identity rowIDs: BLE retains `ble:<lowercase UUID>`; trusted device produces `MobileBatteryDeviceMerge.externalDeviceID(for: "phone:<UDID>")`, Watch produces `MobileBatteryDeviceMerge.externalDeviceID(for: "watch:<parent>:<id>")`, preserving existing hashed display IDs exactly. The underlying `phone:` identity also remains for iPad for compatibility. Use typed IDs for all lookups; do not parse concatenated trusted IDs. Stored hide/order entries then remain valid without name-based migration. No default bulk selection.

- [ ] **1. RED:** Write source-qualified identity and migration tests. Use existing `TestUserDefaults` fixture pattern; construct a fresh suite inline if needed:
```swift
@Test @MainActor func legacyTrustedOptInDoesNotSelectDevices() throws {
    let name = "AppleDeviceSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removeTestSuite(named: name) }
    defaults.set(true, forKey: SettingsStore.showsMobileDeviceBatteryLevelsDefaultsKey)
    let store = SettingsStore(defaults: defaults)
    #expect(store.showsAppleDevicesAndBattery)
    #expect(store.appleDeviceSelections.isEmpty)
}
@Test func sourceIDsAreDistinct() {
    let uuid = UUID()
    #expect(AppleDeviceID.ble(uuid).rowID != AppleDeviceID.trustedDevice(uuid.uuidString).rowID)
    #expect(AppleDeviceID.trustedWatch(parentID: "a", id: "w") != .trustedWatch(parentID: "b", id: "w"))
}
```
Additional cases: all four legacy toggle combinations; absent keys default off; Apple old selection preserved; `.other`/`.unknown` archived unless trusted model proves Apple; malformed JSON fails closed; duplicate IDs deduplicated; deselect/restart does not reimport; disabled/re-enabled keeps choices and hide/order.
- [ ] **2. Run RED:** `swift test --filter AppleDeviceSettingsTests` — first missing API errors are expected; once interfaces compile, observe assertions failing on old migration behavior before implementing migration.
- [ ] **3. GREEN:** Implement Codable typed IDs, stable row identity mapping and migration helper. New defaults keys are `showsAppleDevicesAndBattery`, `appleDeviceSelections`, `appleDeviceSettingsMigrationVersion`, `archivedLegacyNearbyBLESelections`. Persist snapshot/archive before migration marker. Marker value 1 makes migration idempotent; old keys become migration inputs only. Validate candidates before accepting selection; raw name never proves Apple. Create selectable candidates only via catalog/wire builders that have already validated source evidence; trusted-device IDs alone are insufficient Apple proof. Persist only validated selections; preserve typed provenance for Watch with missing model and Apple BLE with missing model. Explicitly normalize BLE IDs in `BluetoothDeviceIdentity.preferenceKey`, do not normalize trusted IDs as MAC addresses.
- [ ] **4. Verify:** `swift test --filter AppleDeviceSettingsTests`, then `swift test && swift build -c release && git diff --check`.
- [ ] **5. Commit:** stage only task files and `git commit -m 'feat: persist explicit Apple device selection and migrate opt-ins'`.

## Task 2 — Metadata discovery without any battery access

**Files:** Native helper boundary; Swift discovery wire decoding in `Models/MobileBatterySnapshot.swift`; tests `NativeBatteryClientTests.m`, `MobileBatterySnapshotTests.swift`.

**Interfaces produced:** Add native API callback `copyPhoneMetadata` parallel to `copyPhoneValues` but queries only DeviceName, ProductType, DeviceClass. New exported C function:
```objc
FOUNDATION_EXPORT NSDictionary *STMobileBatteryCopyDiscovery(
    STMobileBatteryNativeAPI api, NSString *identifier, NSString *transport,
    STMobileBatteryError * _Nullable error);
```
CLI `--discover-device <id> --transport usb|network` returns schemaVersion 1, candidates, failures, no battery fields. Candidate object: `{id,parentID?,name?,model?,transport,trustRequired}`; parentID required only for Watch. Phone metadata from lockdown session; companion identifiers/names/ProductType via existing companion API with explicit metadata-only key array. Trust failure is a scoped failure and actionable hint, not automatically classified Apple by display name. Enumerated routes with unverified model may show a separate trust hint but cannot become selectable Apple devices until verified. Watch identifier plus trusted companion provenance supplies Apple evidence even if model/name missing; never infer watch from arbitrary USB UDID.

- [ ] **1. RED:** Extend FakeNativeState with `phoneMetadataReads`, `phoneBatteryReads`, per-companion requested keys and explicit metadata callback. Add native `TestDiscoveryDoesNotReadBattery`, `TestWatchOnlyDoesNotReadParentBattery`, `TestDiscoveryReleasesResourcesOnTrustFailure`. The first test constructs BaseState with iPhone model/name and a Watch, calls STMobileBatteryCopyDiscovery, then:
```objc
CHECK(state.phoneBatteryReads == 0, "discovery must not read phone battery");
CHECK(state.phoneMetadataReads == 1, "metadata discovery uses the dedicated callback");
for (NSArray *keys in state.requestedCompanionKeys) {
    CHECK(![keys containsObject:@"BatteryCurrentCapacity"], "discovery must not read Watch battery");
    CHECK(![keys containsObject:@"BatteryIsCharging"], "discovery must not read charging state");
}
CHECK([result[@"candidates"] count] == 2, "phone and Watch discovered without battery");
```
Include iPad metadata, denied session, missing pair record, malformed IDs/transport, duplicate Watch IDs and cleanup counts. In Swift add `MobileBatteryWire.decodeDiscovery(_ data: Data, expectedParentID: String) throws -> [AppleDeviceCandidate]`; fixture valid iPad, foreign parent Watch, unsupported schema, duplicate entries. Require no battery fields for decode.
- [ ] **2. Run RED:** `bash scripts/test-mobile-battery-helper.sh`; `swift test --filter MobileBatterySnapshotTests`. Add signatures first only to resolve compile errors, then observe counter/decoder failures.
- [ ] **3. GREEN:** Implement separate metadata-only native path, bounded discovery response and CLI validation; extend production callback initialization. Keep --read-phone battery path separate. Audit STMobileBatteryCopyWatch: its parent session must never call copyPhoneValues; add regression counter even if already correct. Share explicit session cleanup functions only where existing structure permits; do not broad-refactor native helper.
- [ ] **4. Verify:** native tests, `bash scripts/check-mobile-battery-dependency.sh`, `swift test && swift build -c release && git diff --check`.
- [ ] **5. Commit:** `git commit -m 'feat: discover trusted Apple device metadata without battery reads'` with only this task's files staged.

## Task 3 — Explicit trusted read targets and discovery controller

**Files:** Reader/controller boundary and SystemStatusStore initialization as necessary; NEW `Tests/StatusTrioCoreTests/AppleDeviceDiscoveryControllerTests.swift`; UPDATE `MobileBatteryHelperReaderTests.swift`, `MobileBatteryControllerTests.swift`, all test fakes implementing MobileBatteryReading.

**Consumes:** Task 1 IDs/candidates and Task 2 discovery decoder/CLI.
**Produces:**
```swift
protocol MobileBatteryReading: Sendable {
    func discover() async throws -> [AppleDeviceCandidate]
    func read(selectedIDs: Set<AppleDeviceID>) async throws -> MobileBatteryReadResult
}
// No zero-argument production read() and no default implementation that reads all.
// MobileBatteryController:
// func setAuthorizedDeviceIDs(_ ids: Set<AppleDeviceID>)
// AppleDeviceDiscoveryController, @MainActor ObservableObject:
// @Published private(set) var candidates: [AppleDeviceCandidate]
// @Published private(set) var isDiscovering: Bool
// func request(_ token: String); func release(_ token: String); func refresh(); func stop()
```
Discovery lifecycle is separate from battery claims. It starts only with total opt-in and active settings picker, not merely because app launches. Use existing bounded executor (3s listing, per-call limits, 25s cycle) and dedup USB before network; cap device/Watch candidates at existing 8 per cycle and two concurrent reads, but filter selected IDs before limiting so an unselected first eight never starve selected targets.

- [ ] **1. RED:** Extend existing recording executor tests with exact command assertions. Empty selectedIDs yields empty result and zero executor calls. For selected Watch `parent p/watch w` plus unselected phone q:
```swift
// In existing recorder fixture, supply --list p/q and --read-watch response for w.
let selected: Set<AppleDeviceID> = [.trustedWatch(parentID: "p", id: "w")]
let result = try await reader.read(selectedIDs: selected)
#expect(result.snapshots.map(\.identity) == ["watch:p:w"])
// Assert recorded read commands equal only:
// ["--list"], ["--read-watch", "p", "--watch-id", "w", "--transport", "usb"]
// No --read-phone, --discover-device or calls for q during this read.
```
Discovery calls --list + --discover-device, never --read-phone/--read-watch. Add controller revocation, hidden/offscreen targets, cancellation-ignoring fake, expiry, per-ID scoped failures, retained successful other IDs, empty claims, settings dismissal. iPad decode accepts iPhone or iPad for parentless trusted snapshots, rejects iPod/other models and invalid percentages; Watch requires validated parent.
- [ ] **2. Run RED:** `swift test --filter MobileBatteryHelperReaderTests`, `swift test --filter MobileBatteryControllerTests`, `swift test --filter AppleDeviceDiscoveryControllerTests`.
- [ ] **3. GREEN:** Thread selectedIDs through readCycle/readPhones/readWatches. Selected Watch route derives from typed parentID/id and live parent transports, not a --read-phone side effect. Scope phone calls to `.trustedDevice`; do not read unselected candidates to discover children. Gate publication to current IDs/generation, cancel and restart on authorization change, remove revoked cache entries and failures. Use union of scoped visible claims only if multiple surfaces need claims; no boolean “surface visible” substitution for row visibility. Add dedicated discovery controller using reader.discover(); update fakes explicitly, no permissive fallback.
- [ ] **4. Verify:** all targeted tests, native helper tests, `swift test && swift build -c release && git diff --check`.
- [ ] **5. Commit:** `git commit -m 'feat: authorize trusted battery reads by selected visible Apple IDs'` with scoped files.

## Task 4 — Shared Apple picker and one panel projection

**Files:** Shared catalog/UI boundary; UPDATE existing BLE demand/catalog/visibility tests and `MobileBatteryDeviceMergeTests.swift`, `BluetoothDeviceRowLayoutTests.swift`; NEW `AppleDeviceCatalogTests.swift`, `AppleDevicePanelVisibilityTests.swift`.

**Consumes:** Settings selections, discovery candidates, snapshots, BLE readings, both controllers.
**Produces:**
```swift
struct AppleDevicePanelRow: Identifiable, Equatable, Sendable {
    let id: AppleDeviceID
    let device: BluetoothDevice
    let batteryLevel: Int?
    let status: NearbyBLEPanelRowStatus
}
enum AppleDeviceCatalog {
    static func candidates(ble: [NearbyBLEDeviceCandidate], trusted: [AppleDeviceCandidate],
                           selections: [AppleDeviceSelection]) -> [AppleDeviceCandidate]
    static func panelRows(selections: [AppleDeviceSelection],
                          candidates: [AppleDeviceCandidate],
                          nearbyReadings: [NearbyBluetoothBatteryDevice],
                          trustedSnapshots: [MobileBatterySnapshot],
                          failures: Set<AppleDeviceID>,
                          options: BluetoothDeviceListOptions, now: Date) -> [AppleDevicePanelRow]
}
enum AppleDevicePanelVisibility {
    static func visibleIDs(in devices: [BluetoothDevice],
                           rowIDs: [String: AppleDeviceID],
                           frames: [String: CGRect], viewport: CGRect) -> Set<AppleDeviceID>
}
```
One row map feeds settings and panel; only Apple evidence admitted. BLE discovery carries vendor evidence from scanner, saved typed selection was validated at selection/migration. Source-qualified trusted IDs retain original model for glyph. Remove name-based mobile merge for new opt-in rows: use exact rowIDs/explicit existing identity association only. Existing unpaired BLE ghost suppression may remain as documented presentation shadow, never a trusted read authorization or system paired-state override.

- [ ] **1. RED:** Tests build a BLE Apple candidate named “Phone”, other vendor also “iPhone”, same-name trusted candidate. Assert only Apple evidence admitted, names do not deduplicate identities or authorize reads. Saved selections with no readings still generate rows. Global battery off still generates row with no battery text and zero permits. Exact UUID/trusted IDs supply only own readings. One failure cannot overwrite another success. Ordinary paired AirPods stays present with total opt-in off. Add geometry tests for collapse, zero viewport reducer, hidden row, offscreen, scroll into view and mixed BLE/trusted rows; use actual list maxVisibleDevices policy.
```swift
@Test func viewportEmptyGrantsNoReadTargets() {
    #expect(AppleDevicePanelVisibility.visibleIDs(in: [], rowIDs: [:],
                                                frames: [:], viewport: .zero).isEmpty)
}
```
Extend hosted row layout tests: no BLE source subtitle, selected no-reading row stays visible/read-only, successful percentage stays rendered. Test source-qualified options order with identical names, including a real paired peer not shadow-suppressed.
- [ ] **2. Run RED:** `swift test --filter AppleDeviceCatalogTests`; `swift test --filter AppleDevicePanelVisibilityTests`; existing `MobileBatteryDeviceMergeTests` and `BluetoothDeviceRowLayoutTests`.
- [ ] **3. GREEN:** Implement catalog and string-row-ID geometry preference with nonempty viewport reducer. Add AppleDeviceSelectionView replacing rendered NearbyBLESelectionView; discovery surface asks both controllers for metadata only. Total opt-in presents one toggle and one chooser; SettingsStore binding is the only live opt-in. Route visible `.ble` IDs to scanner's existing selected/hidden demand and trusted IDs to setAuthorizedDeviceIDs. SystemStatusStore subscribers and StatusPopoverView pass new settings; old toggles have no production subscribers. Release both read/detection claims on close/disabled. Existing global battery flag suppresses reads/text, not catalog rows. Preserve hide/order/reopen behavior, shared 330pt viewport, ordinary paired list and model glyphs.
- [ ] **4. Verify:** all targeted tests, native tests, `swift test && swift build -c release && git diff --check`. Search runtime old toggles: `rg -n 'showsMobileDeviceBatteryLevels|showsNearbyBluetoothBatteryDevices' Sources` — results allowed only legacy migration/constants, not binding/subscription gates.
- [ ] **5. Commit:** `git commit -m 'feat: unify Apple device selection and visible panel read permits'` with task files only.

## Task 5 — Localized explanation, acceptance, test-app restart

**Files:** Localization keys/resources; tests `LocalizationTests.swift` (find exact existing localization test file via `rg --files Tests | grep Localization` before edit), docs `nearby-ble-devices.md`, both specs' supersession/status; failure ledger only if CI fails. Do not edit release notes unless required to supply an explicit nonpublishing preflight version.

**Consumes:** Complete unified feature. **Produces:** localized working UI, recorded verification evidence and restarted isolated test app; no release.

- [ ] **1. RED:** Add localization test for `.settingsAppleDevicesAndBattery`, `.settingsAppleDevicesAndBatteryDescription`, `.settingsAppleDeviceSelectionTitle`, `.settingsAppleDeviceTrustRequired`, `.settingsAppleDeviceSelectionRequired` in all shipped languages. Chinese explanation must contain iPhone/iPad/Apple Watch/USB/信任 and state nearby Bluetooth does not require USB trust. English counterpart uses Apple Watch, not iWatch. Pin exactly one total feature toggle via actual settings rendering/harness where available, otherwise verify actual extracted settings section; no source regex pretending to be rendered interaction evidence.
- [ ] **2. Run RED:** Run existing localization suite plus new copy test; distinguish missing keys from actual assertion failures.
- [ ] **3. GREEN:** Implement all 12 languages based on spec. Chinese title: “显示苹果设备与电量”; chooser: “选择苹果设备”. Description follows approved spec with per-path trust and Watch availability qualifications. Source label: “附近蓝牙”, not “附近 BLE”. Retire unused old UI keys only if all references removed; keep migration defaults keys. Update user doc for Apple-only selection, migration archive, selected Watch parent-session exception, no name-based identity, unavailable-vs-trust distinction and actual hardware coverage.
- [ ] **4. Acceptance:**
```bash
swift test
swift build -c release
bash scripts/test-mobile-battery-helper.sh
bash scripts/test-mobile-battery-rpaths.sh
bash scripts/validate-appcast-notes.sh
git diff --check
```
Read every result and report failure names, skipped tests and hardware gaps. Review whole diff against all spec requirements (especially no-read discovery and revocation) before committing. If scoped review agent execution selected, reviewers must independently inspect native read-key counters and viewport controller integration, not rely on worker summary.
- [ ] **5. Commit/push after checks:** stage scoped final changes, `git commit -m 'feat: localize unified Apple device battery settings'`; push same branch to update existing PR #93, attach PR to current chat. Inspect release workflow input and latest published version/build using `gh release list --repo lingyired/status-trio --limit 5` plus appcast, choose and explicitly report preflight version/build above published build. Then use real values (not these explanatory shell names left unset):
```bash
gh workflow run release.yml --repo lingyired/status-trio --ref codex/nearby-ble-allowlist \
  -f version="$PREFLIGHT_VERSION" -f build="$PREFLIGHT_BUILD" -f publish=false
```
Resolve the run whose head SHA equals pushed HEAD; `gh run watch "$RUN_ID" --repo lingyired/status-trio --exit-status`. Check tests, DMG/artifact upload and publication skipped. Every failed run enters compatibility ledger with run ID/stage/root cause/fix/reverification. Do not merge or publish. No assertion of CI support until current HEAD passes.
- [ ] **6. Test application:**
```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.BLETest APP_NAME='Status Trio BLE Test' \
APP_VERSION=1.4.0 BUILD_NUMBER=20 bash scripts/build-app.sh release open
pgrep -fl 'StatusTrio.app/Contents/MacOS/StatusTrio'
```
This script restarts only isolated test ID and retains preferences. Confirm new PID/path; don't claim visual or radio success from process start. If dependency download fails, diagnose and retry without removing SDK/signature/helper guards. No modifications to /Applications.
- [ ] **7. Hardware smoke:** own iPhone discover → select → row/pct → hide → no reads → unhide → scroll off → revoked → close/reopen; confirm deselect removes only selected source row, normal paired devices remain. Test USB-trusted route independently with BLE disabled at runtime test harness, then untrusted state/hint. Watch-only test requires real Watch if available; iPad also hardware-dependent. Don't wipe user trust records to simulate failure; use fakes for destructive scenarios. No hardware available means explicitly unverified, not failed or silently “passed”. Update PR body with exact tested SHA and commands, CI run and limitations. Final reply states what now works and offers one under-two-minute verification action.

## Execution handoff

Five dependent tasks; recommended **Native** execution by `gpt-6-luna` with one whole-branch review because identity, native protocol and view authorization share interfaces. Subagent-driven execution is an alternative, serial task workers/review gates, not parallel code writes across these coupled files. Existing written-plan model preference is preserved whichever method the user chooses. Plan must first be reviewed and execution method confirmed; do not treat prior design approval as plan approval.
