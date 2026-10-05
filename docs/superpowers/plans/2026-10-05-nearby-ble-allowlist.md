# Nearby BLE Allowlist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The user requires `gpt-6-luna` for implementation; the parent must route implementation to that model before writing product code.

**Goal:** 附近 BLE 设备由用户选择后才显示，设置和面板共用隐藏/排序规则，只有实际可见的获选设备能连接读取电量。

**Architecture:** 分离广播候选与电量结果；SettingsStore 持久化白名单和展示元数据；控制器将设置的发现需求与面板的读数需求合并。纯 BLE 行保留 UUID 身份并独立显示，视图上报实际可见 UUID，扫描器在入队、连接和回调三个边界检查许可。

**Tech Stack:** SwiftPM、Swift 6、SwiftUI、CoreBluetooth、Foundation、Swift Testing / XCTest；不增加依赖。

**Spec:** `docs/superpowers/specs/2026-10-05-nearby-ble-allowlist-design.md`（用户已批准）。

## Global Constraints

- CI runner `macos-26`、Xcode `26.6`、Swift `6.3.3`；构建 macOS 26 SDK 或更新；保留 `scripts/build-app.sh` 与 `scripts/verify-platform-version.sh` 的 SDK 校验。
- 不使用 `isolated deinit`、`IsolatedDeinit`、`weak let`；actor 方法用显式闭包传递；保持最低运行系统 macOS 15。
- 首次/升级白名单为空；关闭功能保留选择；发现无 GATT；苹果优先只用于 BLE 选择列表；同名不授权、不自动合并。
- 保留 5 秒扫描窗口、60 秒刷新/成功冷却、30 秒失败冷却、最多 8 个连接候选、2 个并发、4 秒超时、1800 秒读数有效期。
- 文案覆盖 `en`、`zh-Hans`、`zh-Hant`、`ja`、`ko`、`de`、`fr`、`es`、`it`、`pt-BR`、`ru`、`ar`；不发布版本、不改变菜单栏/Dock 图标设置。
- 每次 Swift 提交前 `swift test` 和 `swift build -c release`；最终 `publish=false` CI 预检通过才允许合并；每个失败 Actions run 记录到 `docs/swift-ci-compatibility.md`。
- 实施前按 using-git-worktrees 创建/复用隔离 checkout；不要修改现有未跟踪 `dist-test/` 和遥测计划。此改动跨多个子系统，最终用 PR 提供审阅记录。

## Review Focus

1. 同名设备及 BLE UUID 与系统地址碰巧相同：选择/隐藏不能串设备；Task 1/4 身份与目录测试。
2. 设备未读到电量或离开房间：获选行仍存在，电量过期后不显示旧数值、不变成 0%；Task 3/4 测试。
3. 设置窗口与面板同时存在：设置只能发现，面板关闭必须撤销 GATT，设置剩余需求不能保活读数；Task 3 测试。
4. 收起列表、滚动离屏、隐藏与回调同一轮发生：及时取消，旧回调不能恢复行或读数；Task 2/3/5 测试。
5. Apple 厂商广播不代表 iPhone、临时 GATT 不代表配对：厂商仅用于排序，不创建可靠映射、不覆盖真实连接状态；Task 1/4 与 Task 6 硬件验证。

## File Map

新文件职责：

- `Models/NearbyBLEDeviceCandidate.swift`：无电量候选、持久化选择元数据、发现排序。
- `Models/BluetoothDeviceIdentity.swift`：BLE 命名空间与兼容普通设备偏好键。
- `Models/NearbyBLEDeviceCatalog.swift`：设置和面板的获选 BLE 目录/展示投影。
- `Monitoring/NearbyBLEReadAuthorization.swift`：允许读取集合及逐设备回调代次。
- `UI/NearbyBLEPanelVisibility.swift`：纯可见集合计算和 macOS 15 兼容的行/滚动视口交集报告。
- `UI/Settings/NearbyBLESelectionView.swift`：设置发现、选择、状态 UI。

以上均位于 `Sources/StatusTrioCore/`。保留原 scanner/controller 文件所在层级，目标是增加有界接口，不搬迁无关代码。

## Task 1: 身份、发现排序与持久化白名单

**Files:** Create 上述两个模型文件；Modify `Sources/StatusTrioCore/Settings/SettingsStore.swift`、`Sources/StatusTrioCore/UI/BluetoothDeviceListPresentation.swift`；Create `Tests/StatusTrioCoreTests/NearbyBLEDeviceCandidateTests.swift`、`Tests/StatusTrioCoreTests/NearbyBLESettingsTests.swift`；Modify `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`。

**Interfaces:**

```swift
enum NearbyBLEVendor: String, Codable, Sendable { case apple, other, unknown }
struct NearbyBLEDeviceCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var vendor: NearbyBLEVendor
    var lastSeen: Date
}
struct NearbyBLEDeviceSelection: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var vendor: NearbyBLEVendor
    var model: String?
}
enum NearbyBLEDiscoveryPresentation {
    static func ordered(_ candidates: [NearbyBLEDeviceCandidate]) -> [NearbyBLEDeviceCandidate]
}
enum BluetoothDeviceIdentity {
    static func bleRowID(_ id: UUID) -> String
    static func bleUUID(from rowID: String) -> UUID?
    static func preferenceKey(_ rowID: String) -> String
}
// SettingsStore, @MainActor, published private(set) selection array:
// var nearbyBLESelections: [NearbyBLEDeviceSelection]
// func setNearbyBLEDeviceSelected(_ candidate: NearbyBLEDeviceCandidate, selected: Bool)
// func updateNearbyBLEMetadata(_ devices: [NearbyBluetoothBatteryDevice])
```

- [ ] Write failing identity, sorting and migration tests. Add fixtures with explicit UUIDs, dates, names and `.apple/.other/.unknown` vendors; no radio dependency. Include these assertions:

```swift
@Test func bleIdentityNeverSharesClassicPreferenceKey() {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let row = BluetoothDeviceIdentity.bleRowID(id)
    #expect(row == "ble:00000000-0000-0000-0000-000000000001")
    #expect(BluetoothDeviceIdentity.bleUUID(from: row) == id)
    #expect(BluetoothDeviceIdentity.preferenceKey(row)
        != BluetoothDeviceIdentity.preferenceKey(id.uuidString))
    #expect(BluetoothDeviceIdentity.preferenceKey("aa:bb:cc:dd:ee:ff") == "AABBCCDDEEFF")
}
```

In `SettingsStoreTests` reuse `makeSuite()`/`clear(_:)`: set old `showsNearbyBluetoothBatteryDevices` to true before constructing store; assert `nearbyBLESelections.isEmpty`. Select two same-name candidates; reconstruct store and assert both UUIDs persist. Hide one using its BLE row ID, deselect it and assert only that row's order/hidden state is removed; reselect and assert visible. Seed malformed persisted JSON and assert empty list without crash; decoded duplicate UUIDs deduplicate without losing valid independent entries.

- [ ] Run `swift test --filter 'NearbyBLEDeviceCandidateTests|NearbyBLESettingsTests|SettingsStoreTests'`; verify failure is missing new behavior/interface.
- [ ] Implement candidate structs and pure ordering: `.apple` first; trimmed names compared with `localizedCaseInsensitiveCompare`, UUID string as tie-break. Blank names have deterministic order; display placeholder belongs to UI. Classify vendor using two-byte Bluetooth company identifier from advertisement, not the name or a model inferred from the name. An Apple advertisement may still be an accessory; do not assign a mobile kind from vendor alone.

```swift
static func preferenceKey(_ rowID: String) -> String {
    if let id = bleUUID(from: rowID) { return bleRowID(id) }
    return BluetoothBatteryReader.normalizedAddress(rowID)
}
```

`bleUUID` parses only the explicit `ble:` namespace. Store selections as encoded JSON Data under `nearbyBLESelections`; a missing/invalid payload yields empty selections, never historical auto-selection. Add the UUID row key to order on selection, remove only that BLE key from order/hidden/revealed state on deselection. Updating metadata must not select a UUID. Use `preferenceKey` for hide/reveal/rank/move in SettingsStore and BluetoothDeviceListPresentation; keep battery address parsing unchanged.

- [ ] Re-run focused tests and existing Bluetooth list presentation tests. Add vendor parsing tests for empty/truncated Data and `0x4C,0x00` versus non-Apple values; never index short Data.
- [ ] Run `swift test` then `swift build -c release`; stage only Task 1 files and commit `feat(bluetooth): persist nearby BLE device selections`.

## Task 2: 广播发现与获准 GATT 读取分离

**Files:** Modify `Monitoring/BluetoothLEBatteryScanner.swift`、`Monitoring/BluetoothLEBatteryAdvertisement.swift`；Create `Monitoring/NearbyBLEReadAuthorization.swift`；Modify `Tests/StatusTrioCoreTests/BluetoothLEBatteryScannerStateTests.swift`、`BluetoothLEBatteryAdvertisementTests.swift`、`BluetoothNearbyBatteryLifecycleTests.swift`；Create `Tests/StatusTrioCoreTests/NearbyBLEReadAuthorizationTests.swift`。

**Consumes:** Task 1 `NearbyBLEDeviceCandidate` and vendor classification. **Produces:**

```swift
struct NearbyBLEReadAuthorization {
    private(set) var allowedIDs: Set<UUID> = []
    mutating func update(_ ids: Set<UUID>) -> Set<UUID> // removed IDs
    func revision(for id: UUID) -> UInt64
    func accepts(_ id: UUID, revision: UInt64) -> Bool
}
// Add to BluetoothLEBatteryScanning and scanner spies, not protocol defaults:
// var onCandidatesChanged: (([NearbyBLEDeviceCandidate]) -> Void)? { get set }
// var onReadFailures: ((Set<UUID>) -> Void)? { get set }
// var onIsScanningChanged: ((Bool) -> Void)? { get set }
// func setAllowedReadDeviceIDs(_ ids: Set<UUID>)
// start()/refresh()/stop()/onDevicesChanged remain.
```

- [ ] Write revocation tests before production edits, including remove/re-add while a read is pending:

```swift
@Test func reselectingDoesNotAcceptAnOldRead() {
    let id = UUID()
    var gate = NearbyBLEReadAuthorization()
    _ = gate.update([id])
    let revision = gate.revision(for: id)
    #expect(gate.accepts(id, revision: revision))
    #expect(gate.update([]) == [id])
    _ = gate.update([id])
    #expect(!gate.accepts(id, revision: revision))
}
```

Add a second test proving removing A leaves B's revision accepted, and a third proving unchanged permission updates do not invalidate active reads. In scan-policy tests show unauthorized candidates never consume the 8-candidate queue, even after more than 8 broadcast discoveries.

- [ ] Run `swift test --filter 'NearbyBLEReadAuthorizationTests|BluetoothLEBatteryScannerStateTests'`; record expected failure.
- [ ] Implement gate; each removed ID advances its revision, and authorization requires both membership and matching revision. Keep revisions for deselected IDs so reselect cannot reuse an old token. Scanner publishes a deduplicated candidate before considering GATT; discovery results do not require battery or model values.

```swift
// didDiscover, after candidate advertisement validation:
publishCandidate(peripheral, advertisementData: advertisementData)
guard readAuthorization.allowedIDs.contains(peripheral.identifier) else { return }
guard policy.enqueueCandidate(peripheral.identifier, at: Date()) else { return }
// store candidate peripheral/name and run existing bounded queue.
```

Define `publishCandidate(_:advertisementData:)` in scanner to update UUID/name/vendor/lastSeen and emit sorted candidates. Store the authorization revision in each `PeripheralSession`; before `central.connect`, `discoverServices`, `discoverCharacteristics`, `readValue` and result/failure publication check the revision. `setAllowedReadDeviceIDs` removes revoked queued work and cancels revoked sessions without publishing their final battery. Add policy `removeCandidates(_ ids: Set<UUID>)` that removes only the revoked UUIDs from queues/in-flight counts; preserve cooldown rules for unrelated UUIDs. Existing complete-session paths must not re-publish revoked results.

Initial start with empty permit is discovery-only; it never connects. Automatic refresh scheduling is enabled only when permit is nonempty. A discover-only request completes one 5-second window without periodic rescan. Callback scan-state changes allow settings to show the window ending without relying on controller polling. Selected failures publish UUIDs only while still authorized; success removes that UUID from failures.

- [ ] Extend lifecycle scanner spy with all new members, tracking `allowedIDs` and permitted connection/read attempts. Keep legacy tests compiling; they will acquire explicit permitted IDs once Task 3 applies the actual controller gate. Verify pure gate/policy tests and advertisement tests. Inspect all production `central.connect` / `readValue` call sites to ensure they pass permission checks; policy tests alone are not proof of production wiring.
- [ ] Run `swift test` and `swift build -c release`; commit `feat(bluetooth): separate BLE discovery from authorized reads`.

## Task 3: 控制器发现需求、可见读数需求与撤销

**Files:** Modify `Monitoring/BluetoothDeviceController.swift`、`Tests/StatusTrioCoreTests/BluetoothNearbyBatteryLifecycleTests.swift`；Create `Tests/StatusTrioCoreTests/NearbyBLEControllerDemandTests.swift`。

**Consumes:** scanner callbacks/permit setter from Task 2. **Produces (controller @MainActor):**

```swift
// @Published private(set):
// var nearbyBLECandidates: [NearbyBLEDeviceCandidate]
// var nearbyBLEReadFailures: Set<UUID>
// var isDiscoveringNearbyBLEDevices: Bool
// Configuration without settings UI lifetime dependence:
// func configureNearbyBLEDevices(enabled: Bool, selectedIDs: Set<UUID>, hiddenIDs: Set<UUID>)
// func requestNearbyBLEDiscovery(_ token: String)
// func refreshNearbyBLEDiscovery(_ token: String)
// func releaseNearbyBLEDiscovery(_ token: String)
// func setVisibleNearbyBLEDevices(_ ids: Set<UUID>, for token: String)
// func releaseVisibleNearbyBLEDevices(_ token: String)
```

- [ ] Write tests using injected state monitor and scanner spy from existing lifecycle tests (extract fixtures to test support if access is private). Set explicit authorization/powered state and surface tokens. Test matrix: settings discovery without popover, configured selection without visible panel, popover alone without summary, selected/visible/permitted, hidden while active, feature off, panel closed with settings still discovering, Bluetooth powered off, deselect/reselect plus old callback.

```swift
// In a ready controller test with both surface tokens held:
controller.configureNearbyBLEDevices(enabled: true, selectedIDs: [id], hiddenIDs: [])
controller.requestNearbyBLEDiscovery("settings")
XCTAssertTrue(scanner.allowedIDs.isEmpty)
controller.setVisibleNearbyBLEDevices([id], for: "panel")
XCTAssertEqual(scanner.allowedIDs, [id])
controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
XCTAssertTrue(scanner.allowedIDs.isEmpty)
XCTAssertTrue(scanner.isRunning) // settings discovery can finish; no GATT
```

- [ ] Run `swift test --filter 'NearbyBLEControllerDemandTests|BluetoothNearbyBatteryLifecycleTests'`; ensure new tests fail before adding demand logic.
- [ ] Keep discovery token set and per-token visible UUID sets separate. Compute the scanner permit as below, not from the scanner results:

```swift
let visible = visibleNearbyBLERequests.values.reduce(into: Set<UUID>()) { $0.formUnion($1) }
let panelAvailable = isActive && availability == .available
    && hasVisibleSurface && hasBluetoothSummarySurface
let permit: Set<UUID> = nearbyBLEEnabled && panelAvailable
    ? visible.intersection(selectedNearbyBLEIDs).subtracting(hiddenNearbyBLEIDs)
    : []
nearbyBatteryScanner?.setAllowedReadDeviceIDs(permit)
```

The scanner starts only for an authorized/available discovery request or nonempty permit. A settings discovery request can work without the popover token and cannot bypass permit. Avoid continuously restarting a finished discover-only window: start once per new discovery request, explicit refresh calls scanner.refresh; don't rescan on every unrelated published state change.

Modify `releaseVisibleSurface` too: its current no-popover branch unconditionally calls `stopNearbyBatteryScanner`. Replace this with demand recomputation, which sets permission empty immediately and only stops the scanner if no settings discovery remains. Otherwise the test with simultaneous settings/panel cannot pass even if `updateNearbyBatteryScanner` has the correct gate.

Install candidate/read/failure/scanning callbacks together and clear all in stop/deinit. Keep controller generation checks, plus per-ID callback acceptance for changes while scanner stays running. Scanner callback payload can be filtered against current selected/nonhidden permit and its scanner authorization revisions; avoid treating an aggregate snapshot of cached old results as a fresh callback. Cache fresh selected readings for reopen; preserve candidate/selection identities independently of result expiration. Deselect removes corresponding cached reading/failure; hide prevents its publication and display while optionally retaining still-fresh cache internally. Closing panel always empties permit even if settings request remains.

- [ ] Migrate `requestNearbyBatteryDevices` call sites/tests to explicit visible demand, then remove the old unscoped opt-in API when no production references remain. Update existing reopen/expiry tests to seed selected UUIDs and visible rows. Add test that metadata updates/candidate callbacks cannot add an unselected UUID to permit.
- [ ] Run focused lifecycle/demand tests, then `swift test` and `swift build -c release`; commit `feat(bluetooth): gate BLE reads on panel visibility`.

## Task 4: 设置与面板共用目录，BLE 独立来源与连接状态

**Files:** Create `Models/NearbyBLEDeviceCatalog.swift`；Modify `UI/BluetoothNearbyBatteryListPresentation.swift`、`UI/BluetoothStatusView.swift`、`Models/MobileBatteryDeviceMerge.swift` only if required to preserve trusted mobile behavior; Create `Tests/StatusTrioCoreTests/NearbyBLEDeviceCatalogTests.swift`；Modify `BluetoothNearbyBatteryPresentationTests.swift`、`MobileBatteryDeviceMergeTests.swift` where a production input contract changes.

**Consumes:** selection metadata, namespace identity, optional live readings, current options. **Produces:**

```swift
struct NearbyBLEPanelRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let device: BluetoothDevice
    let batteryLevel: Int?
    let wasSeenRecently: Bool
    let readFailed: Bool
}
enum NearbyBLEDeviceCatalog {
    static func settingsDevices(selections: [NearbyBLEDeviceSelection]) -> [BluetoothDevice]
    static func panelRows(selections: [NearbyBLEDeviceSelection],
        candidates: [NearbyBLEDeviceCandidate], readings: [NearbyBluetoothBatteryDevice],
        failures: Set<UUID>, options: BluetoothDeviceListOptions, now: Date) -> [NearbyBLEPanelRow]
}
```

- [ ] Write fixture tests for selected phone with no reading, 0% versus missing, expired reading, hidden BLE row, user order overriding Apple order, same-name UUID pair, and system same-name connected device. Test expired battery preserves selected row with `batteryLevel == nil`; unknown model keeps generic icon, Apple vendor alone does not identify a phone.

```swift
let selection = NearbyBLEDeviceSelection(id: id, name: "My Phone", vendor: .apple, model: nil)
let rows = NearbyBLEDeviceCatalog.panelRows(selections: [selection], candidates: [],
    readings: [], failures: [], options: .standard, now: Date())
#expect(rows.count == 1)
#expect(rows[0].batteryLevel == nil)
#expect(!rows[0].device.isConnected)
#expect(rows[0].device.id == BluetoothDeviceIdentity.bleRowID(id))
```

- [ ] Run `swift test --filter 'NearbyBLEDeviceCatalogTests|BluetoothNearbyBatteryPresentationTests'` and confirm expected failure.
- [ ] Build BLE row devices as `isConnected: false`, `isReadOverTheAir: true`, `isUnpairedGhost: false`, kind from trusted previously read model or `.unknown`. Use `BluetoothDeviceIdentity.preferenceKey` to hide/rank, and rank BLE settings/panel rows identically. Do not use the old `leading` behavior to push a BLE read ahead of saved order. Avoid introducing BLE rows to icon-source menus that accept actionable system devices only.

```swift
// BluetoothStatusView trusted/system merge:
MobileBatteryDeviceMerge.merged(
    devices: controller.devices,
    batteryLevels: controller.batteryLevels,
    nearbyDevices: [], // selected BLE rows rendered separately with UUID identity
    mobileSnapshots: showsMobileBatteryFeature ? mobileBatteryController.snapshots : [],
    fallbackWatchName: localization.string(.mobileBatteryWatchFallbackName)
)
```

No automatic UUID/address link can be proven from current broadcast fields. Thus pure BLE rows stay separate and never become connected; duplicate-looking names retain source labels. Keep existing trusted mobile merge behavior, including helper snapshots, unchanged; do not delete legacy tested merge functions merely because BLE production input becomes empty. Reliable external association is absent, so do not implement speculative name-based connection suppression. Record any remaining system-row transient-state behavior in Task 6 hardware results rather than claiming it solved.

- [ ] Re-run trusted mobile merge, device action targeting, ghost visibility and nearby catalog suites. Verify no nearby result bypasses catalog selection/hidden filtering.
- [ ] Run `swift test` and `swift build -c release`; commit `fix(bluetooth): share BLE visibility and ordering across settings and panel`.

## Task 5: 设置选择 UI、可见行上报与全部本地化

**Files:** Create `UI/Settings/NearbyBLESelectionView.swift`、`UI/NearbyBLEPanelVisibility.swift`；Modify `UI/Settings/BluetoothSectionView.swift`、`UI/BluetoothStatusView.swift`、`UI/NearbyBluetoothBatteryList.swift`、`UI/NearbyBluetoothBatteryRows.swift`、`UI/StatusPopoverView.swift`、`Localization/LocalizationKey.swift`；Modify all 12 `Resources/<language>.lproj/Localizable.strings`；Create `Tests/StatusTrioCoreTests/NearbyBLEPanelVisibilityTests.swift` and Modify `LocalizationParityTests.swift` if necessary.

**Consumes:** Tasks 1–4 interfaces. **Produces:** settings discovered/saved row union, selected catalog as order-list input, panel visibility report independent of battery success.

```swift
enum NearbyBLEPanelVisibility {
    static func eligibleIDs(rows: [NearbyBLEPanelRow], showsList: Bool,
        limit: Int, expanded: Bool) -> Set<UUID>
    static func intersectingIDs(frames: [UUID: CGRect], viewport: CGRect) -> Set<UUID>
}
// NearbyBluetoothBatteryList receives [NearbyBLEPanelRow], options,
// and onVisibleIDsChanged: (Set<UUID>) -> Void.
// NearbyBluetoothBatteryRows receives the resulting selected row slice.
```

- [ ] Write failing visibility tests: no list => empty; limit zero => empty; collapsed first N only; expanded all; scroll rectangles outside viewport excluded; positive intersection included; zero-height viewport yields empty. A row with no battery participates just like one with a reading, preventing circular permission. Add catalog settings-union test proving saved but not discovered selections remain cancellable without duplicate UUIDs.

```swift
@Test func offscreenAndEmptyViewportDoNotAuthorizeReads() {
    let on = UUID(), off = UUID()
    let frames: [UUID: CGRect] = [
        on: CGRect(x: 0, y: 0, width: 100, height: 30),
        off: CGRect(x: 0, y: 300, width: 100, height: 30)
    ]
    #expect(NearbyBLEPanelVisibility.intersectingIDs(frames: frames,
        viewport: CGRect(x: 0, y: 0, width: 100, height: 168)) == [on])
    #expect(NearbyBLEPanelVisibility.intersectingIDs(frames: frames,
        viewport: .zero).isEmpty)
}
```

- [ ] Run `swift test --filter 'NearbyBLEPanelVisibilityTests|NearbyBLEDeviceCatalogTests'`; confirm expected failure.
- [ ] Implement BLE settings union (live candidates plus saved selections), discovery-state banner, scan button and Toggle rows. Use `SettingsGroup`, existing row typography and accessibility patterns; don't add explanatory implementation jargon to product UI. On appear/open enabled group configure selections/hidden IDs then request discovery; on disappear release discovery; feature off releases immediately. Candidate/name changes update saved metadata only for selected UUIDs. While settings remains visible, permission becoming available may fulfill the existing discovery request without prompting unexpectedly.

```swift
Toggle(name, isOn: Binding(
    get: { store.nearbyBLESelections.contains { $0.id == candidate.id } },
    set: { store.setNearbyBLEDeviceSelected(candidate, selected: $0) }
))
```

`BluetoothSectionView.orderedBluetoothDevices` concatenates system devices with catalog settings devices and applies shared ranking; use catalog/identity helpers for hidden state and source labels. Display selection rows even without battery. Keep BLE discovery enabled independently of “show battery levels,” but both battery toggles must be true to authorize panel reads.

Pass `nearbyBLESelections` to `BluetoothStatusView` from `StatusPopoverView`; configure controller from panel settings changes too, so closing settings doesn't freeze its configuration. Add stable `.task(id:)`/`onChange` inputs covering selections, hidden state, both battery feature switches and list enabled state; use Equatable configuration values, not an unordered Set string. Build BLE catalog rows before requesting reads, then the view reports visible IDs after layout. Close/feature/list-off immediately releases its demand; retain controller popover gating because cached SwiftUI views may not disappear on close.

For macOS 15 compatibility, use named coordinate space and geometry/preferences rather than macOS 18+/26-only scroll visibility APIs. Both row frames and viewport must be measured in the same coordinate space. Aggregate positive intersections and apply `eligibleIDs`; set state only when the set changes. Use a normal VStack for the small non-scrolling layout; bounded scrolling follows existing 168-point height. An `onAppear` alone is insufficient: non-lazy stacks instantiate offscreen rows. Use identity `.onChange` to re-report retained geometry when selection changes; revoke on disappearance and on zero viewport. Initial no-reading rows produce nonzero frame, authorize, then accept battery.

Add own BLE expand/collapse button for more than `maxVisibleDevices`; pure BLE and ordinary device sections each apply the existing configured limit within their source group. Preserve regular system-list expansion behavior. Display optional battery value, “temporarily unavailable” after a read failure and “not nearby” for a saved selection lacking current discovery; never fabricate model from name or missing battery as zero.

- [ ] Add localization keys and translations in the same edit. English/Chinese intended copy:

```text
settings.bluetooth.nearbyBLE.title = Nearby BLE devices / 附近 BLE 设备
settings.bluetooth.nearbyBLE.scan = Scan nearby devices / 扫描附近设备
settings.bluetooth.nearbyBLE.scanning = Scanning… / 正在扫描…
settings.bluetooth.nearbyBLE.description = Select devices to show in the status panel. / 勾选要在状态面板中显示的设备。
settings.bluetooth.nearbyBLE.empty = No nearby devices found. Scan again with your device nearby. / 未发现附近设备。请将设备放在附近后重新扫描。
bluetooth.nearbyBLE.notNearby = Not nearby / 当前不在附近
bluetooth.nearbyBLE.unavailable = Temporarily unavailable / 暂时无法读取
bluetooth.nearbyBLE.source = Nearby BLE / 附近 BLE
```

Each key maps to a new `LocalizationKey` case. Supply equivalent complete translations for the other ten existing locales and update existing nearby-feature description to clarify opt-in rather than automatic display. Reuse current permission/empty-selection and fallback-name strings where accurate; if no empty-selection key exists, add `settings.bluetooth.nearbyBLE.noneSelected` with “Select a device to show its battery in the status panel.” / “勾选设备后，可在状态面板中显示其电量。” and all ten equivalents.

- [ ] Run visibility, localization parity, Bluetooth layout and trusted mobile presentation suites, then `swift test` and `swift build -c release`. Manually inspect Settings and panel on macOS 15-compatible layout and current macOS; record screenshot/UI observations in Task 6 verification notes. Commit `feat(settings): add nearby BLE device selection and visible-only battery reads`.

## Task 6: 完整回归、硬件记录与 CI 预检

**Files:** Create `docs/nearby-ble-devices.md` (user behavior and verification limits); Modify `docs/swift-ci-compatibility.md` only for failed Actions runs; update this plan's checkboxes. No product scope expansion.

- [ ] Add final regression tests before any bug fix discovered during verification. Run `swift test` and `swift build -c release`, preserving exact output/result. Inspect `git diff --check` and all scanner GATT call sites. Compare tests against spec and update any changed production call site not protected by permission.
- [ ] Build the runnable app with `bash scripts/build-app.sh release no-open`; this script already calls `scripts/verify-platform-version.sh <binary> <expected-minos> [minimum-sdk-major]` with the packaged executable and declared deployment target. Confirm that check passes; keep the SDK guard. Hardware checks: own iPhone/Watch discovered without GATT, unknown device unselected and never connected, Apple-first ordering, selected row before read, read success/failure, hide, restore, deselect, same-name peers, collapse, scroll offscreen, settings-only discovery, close/reopen panel, Bluetooth off/on. If hardware is unavailable, explicitly record unverified steps and do not claim observed behavior.
- [ ] Capture system profiler report before/during/after authorized GATT and compare connected classification. Write `docs/nearby-ble-devices.md`: white list empty after upgrade, resettable selection, UUID-change requires new selection, vendor≠mobile family, same names may remain separate, pure BLE row always nearby, whether system-reported temporary connections could be reproduced. If false-connected system rows remain, document concrete reproducer and identity-mapping limitation; stop completion claims for that symptom rather than adding an unsafe name-based workaround.
- [ ] Run final local checks, push isolated feature branch and perform non-publishing workflow. Choose explicit preflight version/build from repository release state at execution time; resolve with `gh release list --repo lingyired/status-trio --limit 5`, `gh api repos/lingyired/status-trio/contents/appcast.xml`, and `Support/Info.plist`. Use a version with valid existing `release-notes/<version>/en.md` and `zh-Hans.md`; verify `bash scripts/validate-appcast-notes.sh` first. Do not invent a publishing version or dispatch `publish=true`.

```bash
gh workflow run release.yml --repo lingyired/status-trio --ref "$BLE_PREFLIGHT_BRANCH" -f version="$BLE_PREFLIGHT_VERSION" -f build="$BLE_PREFLIGHT_BUILD" -f publish=false
gh run list --repo lingyired/status-trio --workflow release.yml --branch "$BLE_PREFLIGHT_BRANCH" --event workflow_dispatch --limit 5
gh run watch "$BLE_PREFLIGHT_RUN_ID" --repo lingyired/status-trio --exit-status
```

Set these task-specific variables to concrete reviewed values in execution, record values/run ID in verification notes, and identify the dispatched run by time and head SHA instead of watching an unrelated run. Execute watch in a yielding tool cell so progress can be reported while waiting. For every failure append run ID, stage, root cause, fix and verification result to `docs/swift-ci-compatibility.md`; fix and repeat. Three failed fixes trigger reassessment of the doubtful assumption, per project instructions.

- [ ] After CI success, obtain whole-branch code review, resolve findings with regression coverage and repeat affected checks only. Create PR describing whitelist behavior, display/read parity, sorting, validation and any hardware limitation; attach it to this chat with `attach_artifact`. Do not merge or release without further user instruction. For `publish=false`, verify tests, release build/SDK checks and DMG artifacts; Release/appcast upload should be skipped, not described as published. Record ad-hoc signing when describing artifacts.

## Plan Self-Review

The six tasks cover all approved spec sections: discovery and persistent preference (1/2), demand and cancellation (2/3), shared catalog and source separation (4), visible-row controls and multilingual UX (5), toolchain and hardware validation (6). Interfaces above are shared by later tasks; production API changes require updating every scanner spy, not default protocol no-ops. Candidate updates never select, battery metadata never authorizes, and view geometry cannot bypass controller surface gates.

Known concrete limit: current inputs provide no reliable classic-address↔BLE-UUID association. Task 4 therefore separates sources; Task 6 must report whether any remaining system-row temporary-connection symptom needs further reliable identity data. No test or assumption about matching names can establish that association.

## Execution Handoff

Review this plan before implementation. Recommended method: one `gpt-6-luna` implementer works sequentially in an isolated worktree using executing-plans, preserving scanner/controller/interface context, then an independent whole-branch review. The parent coordinates and verifies; it does not write implementation code on its current model. If the user prefers fresh implementer/reviewer per task, use subagent-driven-development with `gpt-6-luna` implementers instead.
