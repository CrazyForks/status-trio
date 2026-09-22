# 蓝牙设备列表内联展示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在状态面板的蓝牙行下方内联展示已配对设备列表（已连接组在前、默认开启），并提供「最多显示个数」与「设备顺序」两项设置，语义与控件形态镜像现有音量输出列表。

**Architecture:** 设置值在 `SettingsStore` 持久化，聚合成一个 `BluetoothDeviceListOptions` 值类型传给弹出面板；排序/上限由 `BluetoothDeviceListPresentation` 纯函数决定（分组不可跨越、组内按保存顺序、`prefix(N)`、超出时可展开）；行视图 `BluetoothDeviceRow` 由面板列表与详情页共用，避免两处漂移。

**Tech Stack:** Swift 6、SwiftUI、XCTest + swift-testing、Swift Package Manager。

**Spec:** `docs/superpowers/specs/2026-09-21-bluetooth-device-list-design.md`

## Global Constraints

- CI 验收环境是 `macos-26` 运行器、Xcode 26.6、Swift 6.3.3；代码必须在该工具链下可编译，不得使用更新的语法。
- 必须使用 macOS 26 或更新的 SDK 构建；不得移除 `scripts/build-app.sh` 的 SDK 检查与 `scripts/verify-platform-version.sh` 的断言。
- 不使用 `isolated deinit`，不启用 `IsolatedDeinit`；不写 `weak let`；不把 actor 隔离的方法直接当函数值传递。
- 本次改动涉及 SwiftUI 视图体与 `@MainActor` 状态，除 `swift test` 与 `swift build -c release` 外，还必须跑一次 `publish=false` 的 release workflow 预检；预检需要 ref 已在远端，因此最后一步需要人类伙伴授权后推送分支（见 Task 6）。
- 本地化：新增 10 个键必须 12 种语言齐全（`LocalizationTests` 遍历 `LocalizationKey.allCases` × 全部语言），术语沿用各语言 `.lproj` 既有用法。
- 不改动菜单栏/Dock 图标渲染或图标相关设置，因此不涉及图标 parity；任何任务若意外触及图标路径，必须同时改菜单栏与 Dock 两条路径。
- 不新增系统权限、不新增 `system_profiler` 调用；列表只渲染既有 `controller.devices` 与 `controller.batteryLevels`。
- 本轮**不做**在 app 内连接/断开设备（spec 的「不在本次范围内」）。
- 分支：`feat/bluetooth-device-list`（本特性触及设置、模型、多个视图与 12 语言文案，按仓库规则走短分支 + 推送后跑预检）。

---

## File Structure

- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift` — 三个新设置项、clamp、`moveBluetoothDevices`、`bluetoothDeviceListOptions`、init 载入。
- Create: `Sources/StatusTrioCore/Models/BluetoothDeviceListOptions.swift` — 面板侧的值类型（由 store 派生，视图只吃这一个参数）。
- Create: `Sources/StatusTrioCore/UI/BluetoothDeviceListPresentation.swift` — `BluetoothDeviceListModel`、排序/上限纯函数、列表与副标题的可见性规则。
- Create: `Sources/StatusTrioCore/UI/BluetoothDeviceRow.swift` — 面板列表与详情页共用的行视图。
- Create: `Sources/StatusTrioCore/UI/BluetoothDeviceList.swift` — 面板内的列表 + 展开/收起控件。
- Modify: `Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift` — 概要行插入列表、按规则隐藏副标题、详情页改用共用行视图。
- Modify: `Sources/StatusTrioCore/UI/StatusPopoverView.swift` — 把 `bluetoothDeviceListOptions` 传给概要行。
- Modify: `Sources/StatusTrioCore/UI/Settings/BluetoothSectionView.swift` — 新增「状态面板列表」与「设备顺序」两组。
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift` + `Sources/StatusTrioCore/Resources/*/Localizable.strings`（12 个）— 10 个新键。
- Test: Create `Tests/StatusTrioCoreTests/BluetoothDeviceListPresentationTests.swift`；Modify `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`、`Tests/StatusTrioCoreTests/BluetoothSummaryLayoutTests.swift`。
- Modify: `docs/bluetooth-status.md`、`release-notes/1.3.0/*.md`（12 个）。

## Review Focus

1. 面板高度：默认开启后，已开蓝牙面板的用户会看到最多 N 行，面板明显变高。合理预期是「宽度仍是 330、中英文下都不换行溢出」——布局测试必须覆盖中文与英文两种语言（Task 4）。
2. 已连接设备数 ≥ N 时，未连接设备全部不可见（Task 2 的 `prefix` 语义测试钉住「已连接先占位」）；要确认这不是观感缺陷——详情页仍可看全。
3. 拖动不能跨越分组：把未连接设备拖到最上面，松手后它仍在该组内（Task 2 的分组不可跨越测试）；确认组内顺序确实生效，避免「拖了没反应」。
4. 列表开启但设备全部未连接：副标题仍显示「无已连接设备」，下方却列出已配对设备。这是规则使然还是观感矛盾，由 Task 2 的可见性纯函数测试 + Task 4 的规则接线共同钉住。
5. 12 语言文案的术语一致性：从音频场景迁移措辞时不得残留「输出设备」类用词（Task 5 的术语检查步骤）。

---

### Task 1: 设置模型与顺序持久化

**Files:**
- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift`
- Create: `Sources/StatusTrioCore/Models/BluetoothDeviceListOptions.swift`
- Test: `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `BluetoothDevice`（`id` = 设备地址）、`BluetoothBatteryReader.normalizedAddress(_:)`。
- Produces: `SettingsStore.showsBluetoothDeviceList: Bool`（默认 `true`）、`SettingsStore.maxVisibleBluetoothDevices: Int`（默认 5，clamp 到 `SettingsStore.bluetoothDeviceLimitRange = 1...20`）、`SettingsStore.bluetoothDeviceOrder: [String]`（`private(set)`）、`SettingsStore.clampedBluetoothDeviceLimit(_:)`、`SettingsStore.moveBluetoothDevices(fromOffsets:toOffset:in:)`、`SettingsStore.bluetoothDeviceListOptions: BluetoothDeviceListOptions`、`BluetoothDeviceListOptions`（`showsList` / `maxVisibleDevices` / `order`，含 `.standard`）。

- [ ] **Step 1: 写失败的测试**

`Tests/StatusTrioCoreTests/SettingsStoreTests.swift`，加在 `testMaxVisibleOutputDevicesIsClamped` 之后：

```swift
    func testBluetoothDeviceListDefaults() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(SettingsStore.bluetoothDeviceLimitRange, 1...20)
        XCTAssertTrue(store.showsBluetoothDeviceList)
        XCTAssertEqual(store.maxVisibleBluetoothDevices, 5)
        XCTAssertEqual(store.bluetoothDeviceOrder, [])
        XCTAssertEqual(
            store.bluetoothDeviceListOptions,
            BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 5, order: [])
        )
    }

    func testBluetoothDeviceListSettingsPersist() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.showsBluetoothDeviceList = false
        first.maxVisibleBluetoothDevices = 8

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(second.showsBluetoothDeviceList)
        XCTAssertEqual(second.maxVisibleBluetoothDevices, 8)
    }

    func testMaxVisibleBluetoothDevicesIsClamped() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        store.maxVisibleBluetoothDevices = 50
        XCTAssertEqual(store.maxVisibleBluetoothDevices, 20)

        store.maxVisibleBluetoothDevices = 0
        XCTAssertEqual(store.maxVisibleBluetoothDevices, 1)
    }

    func testMovingBluetoothDevicesPersistsNormalizedAddressOrder() {
        let suite = makeSuite()
        defer { clear(suite) }

        let devices = [
            makeBluetoothDevice(address: "AC:90:85:C2:9C:1F", name: "AirPods"),
            makeBluetoothDevice(address: "D3:6D:6C:40:A3:2E", name: "MX Keys"),
            makeBluetoothDevice(address: "AA:BB:CC:DD:EE:FF", name: "Mouse")
        ]
        let store = SettingsStore(defaults: suite.defaults)

        store.moveBluetoothDevices(fromOffsets: IndexSet(integer: 2), toOffset: 0, in: devices)

        XCTAssertEqual(
            store.bluetoothDeviceOrder,
            ["AABBCCDDEEFF", "AC9085C29C1F", "D36D6C40A32E"]
        )
        XCTAssertEqual(
            SettingsStore(defaults: suite.defaults).bluetoothDeviceOrder,
            ["AABBCCDDEEFF", "AC9085C29C1F", "D36D6C40A32E"]
        )
    }

    func testMovingBluetoothDevicesIgnoresOutOfRangeOffsets() {
        let store = SettingsStore(defaults: makeSuite().defaults)
        let devices = [makeBluetoothDevice(address: "AC:90:85:C2:9C:1F", name: "AirPods")]

        store.moveBluetoothDevices(fromOffsets: IndexSet(integer: 5), toOffset: 0, in: devices)
        XCTAssertEqual(store.bluetoothDeviceOrder, [])

        store.moveBluetoothDevices(fromOffsets: IndexSet(), toOffset: 0, in: devices)
        XCTAssertEqual(store.bluetoothDeviceOrder, [])
    }
```

在同文件的私有辅助区加：

```swift
    private func makeBluetoothDevice(address: String, name: String) -> BluetoothDevice {
        BluetoothDevice(id: address, name: name, kind: .audio, isConnected: true)
    }
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter SettingsStoreTests`
Expected: FAIL 编译错误 `value of type 'SettingsStore' has no member 'bluetoothDeviceListOptions'`（以及 `bluetoothDeviceLimitRange` 等）。

- [ ] **Step 3: 新增选项值类型**

新建 `Sources/StatusTrioCore/Models/BluetoothDeviceListOptions.swift`：

```swift
import Foundation

/// The status panel's Bluetooth list preferences, derived once in
/// `SettingsStore` so the popover receives a single value instead of reading
/// three separate settings.
struct BluetoothDeviceListOptions: Equatable, Sendable {
    let showsList: Bool
    let maxVisibleDevices: Int
    let order: [String]

    static let standard = BluetoothDeviceListOptions(
        showsList: true,
        maxVisibleDevices: 5,
        order: []
    )
}
```

- [ ] **Step 4: 在 SettingsStore 里加常量、属性、clamp 与顺序重写**

`Sources/StatusTrioCore/Settings/SettingsStore.swift`，在既有 `defaultMaxVisibleOutputDevices` / `outputDeviceOrderDefaultsKey` 一带加常量：

```swift
    static let defaultMaxVisibleBluetoothDevices = 5
    static let maxVisibleBluetoothDevicesDefaultsKey = "maxVisibleBluetoothDevices"
    static let showsBluetoothDeviceListDefaultsKey = "showsBluetoothDeviceList"
    static let bluetoothDeviceOrderDefaultsKey = "bluetoothDeviceOrder"
    static let bluetoothDeviceLimitRange: ClosedRange<Int> = 1...20
```

在 `maxVisibleOutputDevices` / `alwaysShowsAllOutputDevices` / `outputDeviceOrder` 之后加属性（`bluetoothDeviceOrder` 与 `outputDeviceOrder` 一样是 `private(set)`）：

```swift
    @Published var showsBluetoothDeviceList: Bool {
        didSet {
            defaults.set(
                showsBluetoothDeviceList,
                forKey: Self.showsBluetoothDeviceListDefaultsKey
            )
        }
    }

    @Published var maxVisibleBluetoothDevices: Int {
        didSet {
            let clamped = Self.clampedBluetoothDeviceLimit(maxVisibleBluetoothDevices)
            guard clamped == maxVisibleBluetoothDevices else {
                maxVisibleBluetoothDevices = clamped
                return
            }
            defaults.set(clamped, forKey: Self.maxVisibleBluetoothDevicesDefaultsKey)
        }
    }

    @Published private(set) var bluetoothDeviceOrder: [String] {
        didSet {
            defaults.set(bluetoothDeviceOrder, forKey: Self.bluetoothDeviceOrderDefaultsKey)
        }
    }
```

在 `visibleOutputDeviceLimit` 之后加派生选项：

```swift
    var bluetoothDeviceListOptions: BluetoothDeviceListOptions {
        BluetoothDeviceListOptions(
            showsList: showsBluetoothDeviceList,
            maxVisibleDevices: maxVisibleBluetoothDevices,
            order: bluetoothDeviceOrder
        )
    }
```

在 `clampedOutputDeviceLimit` 之后加：

```swift
    static func clampedBluetoothDeviceLimit(_ value: Int) -> Int {
        min(bluetoothDeviceLimitRange.upperBound, max(bluetoothDeviceLimitRange.lowerBound, value))
    }
```

在 `moveOutputDevices` 之后加（越界保护与「以当前顺序整体重写」语义与音频一致；顺序键用规范化地址）：

```swift
    func moveBluetoothDevices(
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        in devices: [BluetoothDevice]
    ) {
        guard !source.isEmpty,
              source.allSatisfy({ devices.indices.contains($0) }),
              (0...devices.count).contains(destination) else {
            return
        }

        let movedDevices = source.map { devices[$0] }
        let remainingDevices = devices.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        let insertionOffset = destination - source.filter { $0 < destination }.count

        var reorderedDevices = remainingDevices
        reorderedDevices.insert(
            contentsOf: movedDevices,
            at: min(insertionOffset, reorderedDevices.count)
        )
        bluetoothDeviceOrder = reorderedDevices.map {
            BluetoothBatteryReader.normalizedAddress($0.id)
        }
    }
```

在 init 的载入区（`storedOutputDeviceLimit`、`storedOutputDeviceOrder` 一带）加：

```swift
        let storedBluetoothDeviceLimit = (defaults.object(
            forKey: Self.maxVisibleBluetoothDevicesDefaultsKey
        ) as? NSNumber)?.intValue
        let storedBluetoothDeviceOrder = defaults.stringArray(
            forKey: Self.bluetoothDeviceOrderDefaultsKey
        ) ?? []
```

并在 `self.maxVisibleOutputDevices = ...` 之后的赋值区加：

```swift
        self.showsBluetoothDeviceList = defaults.object(
            forKey: Self.showsBluetoothDeviceListDefaultsKey
        ) as? Bool ?? true
        self.maxVisibleBluetoothDevices = Self.clampedBluetoothDeviceLimit(
            storedBluetoothDeviceLimit ?? Self.defaultMaxVisibleBluetoothDevices
        )
        self.bluetoothDeviceOrder = storedBluetoothDeviceOrder
```

- [ ] **Step 5: 运行测试确认通过**

Run: `swift test --filter SettingsStoreTests`
Expected: PASS（含 5 个新用例，既有用例不回归）。

- [ ] **Step 6: 提交**

```bash
git add Sources/StatusTrioCore/Settings/SettingsStore.swift \
        Sources/StatusTrioCore/Models/BluetoothDeviceListOptions.swift \
        Tests/StatusTrioCoreTests/SettingsStoreTests.swift
git commit -m "feat(bluetooth): persist the panel list settings and device order"
```

---

### Task 2: 排序、上限与可见性纯函数

**Files:**
- Create: `Sources/StatusTrioCore/UI/BluetoothDeviceListPresentation.swift`
- Test: Create `Tests/StatusTrioCoreTests/BluetoothDeviceListPresentationTests.swift`

**Interfaces:**
- Consumes: `BluetoothDevicePresentation.grouped(_:)`、`BluetoothBatteryReader.normalizedAddress(_:)`、`BluetoothDeviceListOptions`、`BluetoothAvailability`。
- Produces: `BluetoothDeviceListModel.make(devices:order:limit:isExpanded:)`（`orderedDevices` / `visibleDevices` / `canToggleExpansion`）、`BluetoothDeviceListPresentation.orderedDevices(_:using:)`、`.visibleDevices(from:limit:isExpanded:)`、`.canToggleExpansion(for:limit:)`、`BluetoothPanelListVisibility.showsList(availability:devices:options:)`、`.hidesRowSubtitle(availability:devices:options:)`。

- [ ] **Step 1: 写失败的测试**

新建 `Tests/StatusTrioCoreTests/BluetoothDeviceListPresentationTests.swift`：

```swift
import XCTest
@testable import StatusTrioCore

final class BluetoothDeviceListPresentationTests: XCTestCase {
    func testConnectedDevicesLeadAndOrderOnlyAppliesWithinAGroup() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "Mouse", isConnected: false),
            makeDevice(address: "AA:00:00:00:00:02", name: "Keyboard", isConnected: false),
            makeDevice(address: "AA:00:00:00:00:03", name: "AirPods", isConnected: true)
        ]

        // The saved order ranks a disconnected device first, but the group rule
        // wins: a drag can never lift it above a connected device. The stale
        // address matches no device and changes nothing.
        let ordered = BluetoothDeviceListPresentation.orderedDevices(
            devices,
            using: ["AA0000000001", "STALE-ADDRESS", "AA0000000003", "AA0000000002"]
        )

        XCTAssertEqual(ordered.map(\.name), ["AirPods", "Mouse", "Keyboard"])
    }

    func testUnlistedDevicesKeepIncomingOrderAfterRankedOnes() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "First", isConnected: true),
            makeDevice(address: "AA:00:00:00:00:02", name: "Second", isConnected: true),
            makeDevice(address: "AA:00:00:00:00:03", name: "Third", isConnected: true)
        ]

        let ordered = BluetoothDeviceListPresentation.orderedDevices(
            devices,
            using: ["AA0000000002"]
        )

        XCTAssertEqual(ordered.map(\.name), ["Second", "First", "Third"])
    }

    func testEmptyOrderKeepsGroupingOrder() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "Idle", isConnected: false),
            makeDevice(address: "AA:00:00:00:00:02", name: "Live", isConnected: true)
        ]

        XCTAssertEqual(
            BluetoothDeviceListPresentation.orderedDevices(devices, using: []).map(\.name),
            ["Live", "Idle"]
        )
    }

    func testConnectedDevicesFillTheLimitFirst() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "Live", isConnected: true),
            makeDevice(address: "AA:00:00:00:00:02", name: "Idle", isConnected: false),
            makeDevice(address: "AA:00:00:00:00:03", name: "Idle2", isConnected: false)
        ]

        let model = BluetoothDeviceListModel.make(
            devices: devices,
            order: [],
            limit: 2,
            isExpanded: false
        )

        XCTAssertEqual(model.visibleDevices.map(\.name), ["Live", "Idle"])
        XCTAssertTrue(model.canToggleExpansion)
    }

    func testExpansionShowsEveryDeviceAndDisappearsWhenEverythingFits() {
        let devices = (1...3).map {
            makeDevice(address: "AA:00:00:00:00:0\($0)", name: "Device \($0)", isConnected: true)
        }

        XCTAssertEqual(
            BluetoothDeviceListPresentation.visibleDevices(from: devices, limit: 1, isExpanded: true)
                .map(\.name),
            ["Device 1", "Device 2", "Device 3"]
        )
        XCTAssertFalse(
            BluetoothDeviceListPresentation.canToggleExpansion(for: devices, limit: 3)
        )
        XCTAssertTrue(
            BluetoothDeviceListPresentation.canToggleExpansion(for: devices, limit: 2)
        )
        XCTAssertEqual(
            BluetoothDeviceListPresentation.visibleDevices(from: [], limit: 5, isExpanded: false),
            []
        )
    }

    func testListVisibilityFollowsAvailabilityAndEmptyState() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "Idle", isConnected: false)
        ]
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 5, order: [])

        XCTAssertTrue(
            BluetoothPanelListVisibility.showsList(
                availability: .available,
                devices: devices,
                options: options
            )
        )
        XCTAssertFalse(
            BluetoothPanelListVisibility.showsList(
                availability: .poweredOff,
                devices: devices,
                options: options
            )
        )
        XCTAssertFalse(
            BluetoothPanelListVisibility.showsList(
                availability: .available,
                devices: [],
                options: options
            )
        )
        XCTAssertFalse(
            BluetoothPanelListVisibility.showsList(
                availability: .available,
                devices: devices,
                options: BluetoothDeviceListOptions(showsList: false, maxVisibleDevices: 5, order: [])
            )
        )
    }

    func testSubtitleIsReplacedOnlyWhenTheListCarriesConnectedNames() {
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 5, order: [])
        let connected = [makeDevice(address: "AA:00:00:00:00:01", name: "Live", isConnected: true)]
        let idle = [makeDevice(address: "AA:00:00:00:00:02", name: "Idle", isConnected: false)]

        XCTAssertTrue(
            BluetoothPanelListVisibility.hidesRowSubtitle(
                availability: .available,
                devices: connected,
                options: options
            )
        )
        // Nothing connected: the row keeps saying so, and the list still shows
        // the paired devices underneath.
        XCTAssertFalse(
            BluetoothPanelListVisibility.hidesRowSubtitle(
                availability: .available,
                devices: idle,
                options: options
            )
        )
        XCTAssertFalse(
            BluetoothPanelListVisibility.hidesRowSubtitle(
                availability: .available,
                devices: connected,
                options: BluetoothDeviceListOptions(showsList: false, maxVisibleDevices: 5, order: [])
            )
        )
    }

    private func makeDevice(
        address: String,
        name: String,
        isConnected: Bool
    ) -> BluetoothDevice {
        BluetoothDevice(id: address, name: name, kind: .audio, isConnected: isConnected)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter BluetoothDeviceListPresentationTests`
Expected: FAIL 编译错误 `cannot find 'BluetoothDeviceListPresentation' in scope`。

- [ ] **Step 3: 实现**

新建 `Sources/StatusTrioCore/UI/BluetoothDeviceListPresentation.swift`：

```swift
/// The list the status panel renders, derived once per body evaluation so the
/// view never re-derives the order or the limit itself.
struct BluetoothDeviceListModel: Equatable {
    let orderedDevices: [BluetoothDevice]
    let visibleDevices: [BluetoothDevice]
    let canToggleExpansion: Bool

    static func make(
        devices: [BluetoothDevice],
        order: [String],
        limit: Int,
        isExpanded: Bool
    ) -> BluetoothDeviceListModel {
        let orderedDevices = BluetoothDeviceListPresentation.orderedDevices(devices, using: order)
        return BluetoothDeviceListModel(
            orderedDevices: orderedDevices,
            visibleDevices: BluetoothDeviceListPresentation.visibleDevices(
                from: orderedDevices,
                limit: limit,
                isExpanded: isExpanded
            ),
            canToggleExpansion: BluetoothDeviceListPresentation.canToggleExpansion(
                for: orderedDevices,
                limit: limit
            )
        )
    }
}

enum BluetoothDeviceListPresentation {
    /// Connected devices always lead; the saved order only reorders devices
    /// **within** their own group, so a drag can never lift a disconnected
    /// device above a connected one. Devices with no saved rank keep the
    /// group's own order and land after the ranked ones.
    static func orderedDevices(
        _ devices: [BluetoothDevice],
        using order: [String]
    ) -> [BluetoothDevice] {
        let groups = BluetoothDevicePresentation.grouped(devices)
        return ranked(groups.connected, using: order) + ranked(groups.disconnected, using: order)
    }

    static func visibleDevices(
        from devices: [BluetoothDevice],
        limit: Int,
        isExpanded: Bool
    ) -> [BluetoothDevice] {
        guard !isExpanded else { return devices }
        return Array(devices.prefix(max(0, limit)))
    }

    static func canToggleExpansion(for devices: [BluetoothDevice], limit: Int) -> Bool {
        devices.count > max(0, limit)
    }

    private static func ranked(
        _ devices: [BluetoothDevice],
        using order: [String]
    ) -> [BluetoothDevice] {
        guard !order.isEmpty else { return devices }

        var ranks: [String: Int] = [:]
        for (index, address) in order.enumerated() where ranks[address] == nil {
            ranks[address] = index
        }

        return devices.enumerated()
            .sorted { lhs, rhs in
                let leftRank = ranks[BluetoothBatteryReader.normalizedAddress(lhs.element.id)] ?? Int.max
                let rightRank = ranks[BluetoothBatteryReader.normalizedAddress(rhs.element.id)] ?? Int.max
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

/// Whether the panel's Bluetooth section shows the list at all, and whether the
/// row's own subtitle gives way to it. Both rules live here so the view body
/// stays a straight rendering of decisions that are unit-tested.
enum BluetoothPanelListVisibility {
    static func showsList(
        availability: BluetoothAvailability,
        devices: [BluetoothDevice],
        options: BluetoothDeviceListOptions
    ) -> Bool {
        guard options.showsList, availability == .available else { return false }
        return !devices.isEmpty
    }

    /// The list carries the connected names, so the subtitle that would repeat
    /// them is dropped. States only the row can explain — nothing connected, no
    /// permission, powered off, read failure — keep it.
    static func hidesRowSubtitle(
        availability: BluetoothAvailability,
        devices: [BluetoothDevice],
        options: BluetoothDeviceListOptions
    ) -> Bool {
        guard showsList(availability: availability, devices: devices, options: options) else {
            return false
        }
        return !BluetoothDevicePresentation.grouped(devices).connected.isEmpty
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter BluetoothDeviceListPresentationTests`
Expected: PASS（7 个用例）。

- [ ] **Step 5: 提交**

```bash
git add Sources/StatusTrioCore/UI/BluetoothDeviceListPresentation.swift \
        Tests/StatusTrioCoreTests/BluetoothDeviceListPresentationTests.swift
git commit -m "feat(bluetooth): derive panel list order, limit, and visibility"
```

---

### Task 3: 抽出共用设备行视图

**Files:**
- Create: `Sources/StatusTrioCore/UI/BluetoothDeviceRow.swift`
- Modify: `Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift:220-250`

**Interfaces:**
- Consumes: `BluetoothDeviceRowIcon.symbolName(for:)`、`BluetoothDevicePresentation.batteryLevelText(for:batteryLevels:)`、`BluetoothDevice`、`[String: BluetoothBatteryLevel]`。
- Produces: `BluetoothDeviceRow(device:batteryLevels:)` — 面板列表（Task 4）与详情页共用的行视图，样式与文案与今天完全一致。

- [ ] **Step 1: 建共用行视图（内容逐字搬自详情页）**

新建 `Sources/StatusTrioCore/UI/BluetoothDeviceRow.swift`：

```swift
import SwiftUI

/// One paired-device row. The status panel's list and the detail page share it
/// so the two surfaces cannot drift, and a device the report carries no level
/// for simply draws no battery text.
struct BluetoothDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let device: BluetoothDevice
    let batteryLevels: [String: BluetoothBatteryLevel]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: BluetoothDeviceRowIcon.symbolName(for: device))
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(device.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if let level = BluetoothDevicePresentation.batteryLevelText(
                for: device,
                batteryLevels: batteryLevels
            ) {
                Text(level)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(
                device.isConnected
                    ? localization.string(.bluetoothConnected)
                    : localization.string(.bluetoothNotConnected)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 2: 详情页改用该行视图**

`Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift` 的 `section(_:devices:)`，把整段 `ForEach` 内容替换为：

```swift
            ForEach(devices) { device in
                BluetoothDeviceRow(device: device, batteryLevels: controller.batteryLevels)
            }
```

（原来那段内联 `HStack` 逐字搬进了 Task 3 Step 1 的新文件，样式与文案不变；`batteryLevelText` 的调用点因此只剩一处。）

- [ ] **Step 3: 运行完整测试确认没有回归**

Run: `swift test`
Expected: PASS，0 failures（180 个既有用例 + Task 1/2 新增用例）。

Run: `swift build -c release`
Expected: 构建成功，0 errors。

- [ ] **Step 4: 提交**

```bash
git add Sources/StatusTrioCore/UI/BluetoothDeviceRow.swift \
        Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift
git commit -m "refactor(bluetooth): share one device row between the panel and detail page"
```

---

### Task 4: 面板内联列表

**Files:**
- Create: `Sources/StatusTrioCore/UI/BluetoothDeviceList.swift`
- Modify: `Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift:6-63`（概要行）
- Modify: `Sources/StatusTrioCore/UI/StatusPopoverView.swift`（构造概要行处）
- Test: `Tests/StatusTrioCoreTests/BluetoothSummaryLayoutTests.swift`

**Interfaces:**
- Consumes: Task 2 的 `BluetoothDeviceListModel` / `BluetoothPanelListVisibility`、Task 3 的 `BluetoothDeviceRow`、`BluetoothDeviceListOptions`。
- Produces: `BluetoothStatusView(controller:showsBatteryLevels:listOptions:onOpenDetails:onRequestAuthorization:onOpenBluetoothSettings:)`（`listOptions` 带默认值 `.standard`）；`BluetoothDeviceList(devices:batteryLevels:options:)`。

- [ ] **Step 1: 写失败的布局测试**

`Tests/StatusTrioCoreTests/BluetoothSummaryLayoutTests.swift`：给 `render` 加参数并补两个用例。

`render` 签名与视图构造改为：

```swift
    private func render(
        language: AppLanguage,
        authorization: BluetoothAuthorizationStatus,
        devices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel] = [:],
        listOptions: BluetoothDeviceListOptions = .standard,
        named name: String
    ) async throws -> NSSize {
```

```swift
        let view = BluetoothStatusView(
            controller: controller,
            showsBatteryLevels: true,
            listOptions: listOptions,
            onOpenDetails: {},
            onRequestAuthorization: {},
            onOpenBluetoothSettings: {}
        )
```

既有 `testSummaryStatesFitThePopover` 调用 `render` 时显式传 `listOptions: BluetoothDeviceListOptions(showsList: false, maxVisibleDevices: 5, order: [])`，保持它今天断言的形态（`height < 120`）。

新增两个用例：

```swift
    /// With the list on, the row grows by the visible device rows and the
    /// expansion control — in both a narrow-glyph and a wide-glyph language.
    func testDeviceListGrowsTheRowWithoutWideningIt() async throws {
        let devices = (1...6).map { index in
            BluetoothDevice(
                id: "AA:00:00:00:00:0\(index)",
                name: "Device \(index)",
                kind: .audio,
                isConnected: index <= 2
            )
        }
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 3, order: [])

        for language in [AppLanguage.english, .simplifiedChinese] {
            let withList = try await render(
                language: language,
                authorization: .allowed,
                devices: devices,
                listOptions: options,
                named: "bluetooth-list-\(language.rawValue)"
            )
            let withoutList = try await render(
                language: language,
                authorization: .allowed,
                devices: devices,
                listOptions: BluetoothDeviceListOptions(showsList: false, maxVisibleDevices: 3, order: []),
                named: "bluetooth-nolist-\(language.rawValue)"
            )

            XCTAssertEqual(withList.width, 330, accuracy: 0.5)
            XCTAssertGreaterThan(
                withList.height,
                withoutList.height,
                "the list must add the device rows in \(language.rawValue)"
            )
        }
    }

    /// No paired devices means no list: the row keeps its own message and its
    /// original height.
    func testEmptyDeviceListDoesNotChangeTheRow() async throws {
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 3, order: [])

        let withSettingOn = try await render(
            language: .english,
            authorization: .allowed,
            devices: [],
            listOptions: options,
            named: "bluetooth-list-empty"
        )

        XCTAssertEqual(withSettingOn.width, 330, accuracy: 0.5)
        XCTAssertLessThan(withSettingOn.height, 120)
    }
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter BluetoothSummaryLayoutTests`
Expected: FAIL 编译错误：`BluetoothStatusView` 没有 `listOptions` 参数。

- [ ] **Step 3: 列表视图**

新建 `Sources/StatusTrioCore/UI/BluetoothDeviceList.swift`：

```swift
import SwiftUI

/// The paired-device list shown inside the status panel, under the Bluetooth
/// row. It mirrors the volume output list: the first `limit` devices are always
/// visible and anything beyond them is revealed by an expansion control. Rows
/// are display-only — this release does not connect or disconnect devices from
/// the app.
struct BluetoothDeviceList: View {
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let devices: [BluetoothDevice]
    let batteryLevels: [String: BluetoothBatteryLevel]
    let options: BluetoothDeviceListOptions

    @State private var isExpanded = false

    var body: some View {
        let model = BluetoothDeviceListModel.make(
            devices: devices,
            order: options.order,
            limit: options.maxVisibleDevices,
            isExpanded: isExpanded
        )

        VStack(spacing: 2) {
            ForEach(model.visibleDevices) { device in
                BluetoothDeviceRow(device: device, batteryLevels: batteryLevels)
            }

            if model.canToggleExpansion {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))

                        Text(
                            localization.string(
                                isExpanded ? .bluetoothListCollapse : .bluetoothListExpand
                            )
                        )
                        .font(.callout)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 4: 概要行接入列表并隐藏副标题**

`Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift`：

`BluetoothStatusView` 加参数（默认值让其它调用点与测试无需立刻改）：

```swift
    let showsBatteryLevels: Bool
    var listOptions: BluetoothDeviceListOptions = .standard
```

`body` 由 `HStack { ... }` 改为外层 `VStack`，`HStack` 内容保持不变：

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: onOpenDetails) {
                    HStack(spacing: 10) {
                        BluetoothIcon(size: 24)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localization.string(.bluetoothTitle))
                                .font(.headline)
                            subtitle
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(localization.string(.bluetoothTitle)), \(accessibilitySummary)")

                Button(localization.string(.bluetoothActionOpenSettings), systemImage: "gearshape", action: onOpenBluetoothSettings)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(localization.string(.bluetoothActionOpenSettings))
                    .frame(width: 24, height: 24)
            }
            if showsDeviceList {
                BluetoothDeviceList(
                    devices: controller.devices,
                    batteryLevels: controller.batteryLevels,
                    options: listOptions
                )
            }
        }
        .onAppear {
            controller.holdVisibleSurface(Self.summarySurfaceToken)
        }
        .task(id: batteryReadTaskID) {
            // Reading levels launches system_profiler, so the claim is held only
            // while the summary actually wants them. The row stays on screen
            // while the setting changes, so the release has to happen here and
            // not only in `onDisappear`: otherwise switching the setting off
            // leaves the read running and the level it published on screen until
            // the row disappears and comes back. A claim rather than a toggle
            // keeps this correct whichever order SwiftUI runs it in against the
            // detail page's own claim.
            guard showsBatteryLevels, summaryPresentation.hasConnectedDevices else {
                controller.releaseBatteryLevels(Self.summaryBatteryLevelsToken)
                return
            }
            controller.requestBatteryLevels(Self.summaryBatteryLevelsToken)
        }
        .onDisappear {
            controller.releaseVisibleSurface(Self.summarySurfaceToken)
            controller.releaseBatteryLevels(Self.summaryBatteryLevelsToken)
        }
    }

    private var showsDeviceList: Bool {
        BluetoothPanelListVisibility.showsList(
            availability: controller.availability,
            devices: controller.devices,
            options: listOptions
        )
    }

    private var hidesSubtitle: Bool {
        BluetoothPanelListVisibility.hidesRowSubtitle(
            availability: controller.availability,
            devices: controller.devices,
            options: listOptions
        )
    }
```

`subtitle` 加一个分支（可访问性标签仍用 `summaryText`，所以 VoiceOver 依旧念出设备名）：

```swift
    @ViewBuilder
    private var subtitle: some View {
        if case .requestAuthorization = summaryPresentation {
            Button(
                localization.string(.bluetoothActionRequestAuthorization),
                action: onRequestAuthorization
            )
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else if hidesSubtitle {
            EmptyView()
        } else {
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
```

- [ ] **Step 5: 弹出面板传入设置**

`Sources/StatusTrioCore/UI/StatusPopoverView.swift` 里构造概要行处：

```swift
            BluetoothStatusView(
                controller: store.bluetoothDevices,
                showsBatteryLevels: settings.showsBluetoothBatteryLevels,
                listOptions: settings.bluetoothDeviceListOptions,
                onOpenDetails: {
                    store.openBluetoothDetails()
                    panel = .bluetooth
                },
                onRequestAuthorization: requestBluetoothAuthorization,
                onOpenBluetoothSettings: openBluetoothSettings
            )
```

（详情页那处 `BluetoothDeviceListView(...)` 构造不需要 `listOptions`，它的顺序不受设置影响。）

- [ ] **Step 6: 运行测试确认通过**

Run: `swift test --filter BluetoothSummaryLayoutTests`
Expected: PASS（既有用例 + 2 个新用例）。

Run: `swift test`
Expected: PASS，0 failures。

- [ ] **Step 7: 提交**

```bash
git add Sources/StatusTrioCore/UI/BluetoothDeviceList.swift \
        Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift \
        Sources/StatusTrioCore/UI/StatusPopoverView.swift \
        Tests/StatusTrioCoreTests/BluetoothSummaryLayoutTests.swift
git commit -m "feat(bluetooth): list paired devices inside the status panel"
```

---

### Task 5: 设置界面与 12 语言文案

**Files:**
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift:108-120`
- Modify: `Sources/StatusTrioCore/Resources/{ar,de,en,es,fr,it,ja,ko,pt-BR,ru,zh-Hans,zh-Hant}.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/UI/Settings/BluetoothSectionView.swift`

**Interfaces:**
- Consumes: Task 1 的 `showsBluetoothDeviceList` / `maxVisibleBluetoothDevices` / `bluetoothDeviceLimitRange` / `moveBluetoothDevices` / `bluetoothDeviceOrder`，Task 3 的 `BluetoothDeviceRowIcon`（顺序列表里的图标）。
- Produces: 10 个新本地化键；设置页两组新 UI。

- [ ] **Step 1: 加本地化键（先写英文，让测试失败）**

`Sources/StatusTrioCore/Localization/LocalizationKey.swift`，在 `settingsBluetoothSymbolScaleDescription` 之后加：

```swift
    case settingsBluetoothShowDeviceList = "settings.bluetooth.showDeviceList"
    case settingsBluetoothShowDeviceListDescription = "settings.bluetooth.showDeviceListDescription"
    case settingsBluetoothMaximumVisible = "settings.bluetooth.maximumVisible"
    case settingsBluetoothMaximumVisibleDescription = "settings.bluetooth.maximumVisibleDescription"
    case settingsBluetoothOrderTitle = "settings.bluetooth.orderTitle"
    case settingsBluetoothOrderDescription = "settings.bluetooth.orderDescription"
    case settingsBluetoothOrderEmpty = "settings.bluetooth.orderEmpty"
    case settingsBluetoothOrderFootnote = "settings.bluetooth.orderFootnote"
    case bluetoothListExpand = "bluetooth.list.expand"
    case bluetoothListCollapse = "bluetooth.list.collapse"
```

Run: `swift test --filter LocalizationTests`
Expected: FAIL —— 新键在 12 个语言里都还没有对应字符串。

- [ ] **Step 2: 写 12 语言文案**

英文（`en.lproj`）与两种中文的完整文案：

| key | en | zh-Hans | zh-Hant |
| --- | --- | --- | --- |
| `settings.bluetooth.showDeviceList` | Show the Bluetooth device list | 显示蓝牙设备列表 | 顯示藍牙裝置列表 |
| `settings.bluetooth.showDeviceListDescription` | Lists paired devices under the Bluetooth entry in the status panel. Connected devices come first. | 在状态面板的蓝牙行下方列出已配对设备，已连接的排在前面。 | 在狀態面板的藍牙列下方列出已配對裝置，已連接的排在前面。 |
| `settings.bluetooth.maximumVisible` | Maximum visible Bluetooth devices | 最多显示设备数 | 最多顯示裝置數 |
| `settings.bluetooth.maximumVisibleDescription` | How many devices appear before the Expand control. | 超出这个数量的设备需要点击「展开」查看。 | 超出這個數量的裝置需要點按「展開」查看。 |
| `settings.bluetooth.orderTitle` | Bluetooth Device Order | 蓝牙设备顺序 | 藍牙裝置順序 |
| `settings.bluetooth.orderDescription` | Drag devices to change the order shown in the status panel. Connected devices always come first, and new devices appear at the end. | 拖动可以调整设备在状态面板中的顺序。已连接设备始终排在最前，新设备会出现在末尾。 | 拖曳可以調整裝置在狀態面板中的順序。已連接裝置一律排在最前，新裝置會出現在最後。 |
| `settings.bluetooth.orderEmpty` | No paired devices available. | 暂无可排序的已配对设备。 | 暫無可排序的已配對裝置。 |
| `settings.bluetooth.orderFootnote` | Connected devices are always listed first. | 已连接的设备始终排在最前。 | 已連接的裝置一律排在最前。 |
| `bluetooth.list.expand` | Expand | 展开 | 展開 |
| `bluetooth.list.collapse` | Collapse | 收起 | 收合 |

其余 9 种语言按同语言的音频同类串迁移措辞——每个新键都有一个 1:1 的现有参照串，术语必须与参照串保持一致（「输出设备」类用词不得残留）：

| 新键 | 参照的现有键 |
| --- | --- |
| `settings.bluetooth.showDeviceList` | `settings.audio.showAll` |
| `settings.bluetooth.showDeviceListDescription` | `settings.audio.showAllDescription` |
| `settings.bluetooth.maximumVisible` | `settings.audio.maximumVisible` |
| `settings.bluetooth.maximumVisibleDescription` | `settings.audio.maximumVisibleDescription` |
| `settings.bluetooth.orderTitle` | `settings.audio.orderTitle` |
| `settings.bluetooth.orderDescription` | `settings.audio.orderDescription` |
| `settings.bluetooth.orderEmpty` | `settings.audio.orderEmpty` |
| `settings.bluetooth.orderFootnote` | `settings.audio.activeDeviceFootnote` |
| `bluetooth.list.expand` | `volume.output.expand` |
| `bluetooth.list.collapse` | `volume.output.collapse` |

后两个键的文案**直接取同语言 `volume.output.expand` / `volume.output.collapse` 的文本**（同一个控件、同一个词），不要另行翻译。

插入位置：每个 `.lproj` 里紧跟 `"settings.bluetooth.symbolScaleDescription"` 那一行之后插入 8 条 `settings.bluetooth.*`，再在蓝牙区块末尾插入 2 条 `bluetooth.list.*`。

- [ ] **Step 3: 术语检查**

Run: `for l in ar de en es fr it ja ko pt-BR ru zh-Hans zh-Hant; do printf '%s ' "$l"; grep -c '^"settings.bluetooth.\(showDeviceList\|maximumVisible\|order\)' Sources/StatusTrioCore/Resources/$l.lproj/Localizable.strings; done`
Expected: 12 行，每行都是 `8`（showDeviceList、showDeviceListDescription、maximumVisible、maximumVisibleDescription、orderTitle、orderDescription、orderEmpty、orderFootnote）。

Run: `grep -n "Ausgabegerät\|output device\|sortie audio\|dispositivo de salida\|dispositivi di output\|출력 장치\|出力デバイス\|设备输出\|輸出裝置" Sources/StatusTrioCore/Resources/*/Localizable.strings | grep -i bluetooth`
Expected: 无匹配（迁移过来的蓝牙文案里不残留音频用词）。

- [ ] **Step 4: 运行本地化测试确认通过**

Run: `swift test --filter Localization`
Expected: PASS（`LocalizationTests` / `LocalizationParityTests` 覆盖 12 语言与键齐全）。

- [ ] **Step 5: 设置页两组**

`Sources/StatusTrioCore/UI/Settings/BluetoothSectionView.swift`：在既有那个 `SettingsGroup` 之后追加两组（`SettingsPage` 的尾随闭包里按顺序加 `deviceListGroup`、`deviceOrderGroup`）：

```swift
    private var deviceListGroup: some View {
        SettingsGroup(localization.string(.settingsBluetoothShowDeviceList)) {
            SettingsToggleRow(
                symbol: "list.bullet.rectangle",
                tint: .purple,
                title: localization.string(.settingsBluetoothShowDeviceList),
                subtitle: localization.string(.settingsBluetoothShowDeviceListDescription),
                isOn: $store.showsBluetoothDeviceList
            )

            if store.showsBluetoothDeviceList {
                SettingsDivider()

                SettingsRow(
                    title: localization.string(.settingsBluetoothMaximumVisible),
                    subtitle: localization.string(.settingsBluetoothMaximumVisibleDescription),
                    leading: { SettingsIcon(symbol: "number", tint: .teal) },
                    trailing: {
                        HStack(spacing: 10) {
                            Text("\(store.maxVisibleBluetoothDevices)")
                                .font(.system(size: 13, design: .monospaced))
                                .frame(minWidth: 22, alignment: .trailing)

                            Stepper(
                                localization.string(.settingsBluetoothMaximumVisible),
                                value: $store.maxVisibleBluetoothDevices,
                                in: SettingsStore.bluetoothDeviceLimitRange
                            )
                            .labelsHidden()
                        }
                    }
                )
            }
        }
    }

    private var deviceOrderGroup: some View {
        SettingsGroup(
            localization.string(.settingsBluetoothOrderTitle),
            footnote: localization.string(.settingsBluetoothOrderFootnote)
        ) {
            SettingsCustomRow(
                "slider.horizontal.3",
                tint: .blue,
                title: localization.string(.settingsBluetoothOrderTitle),
                subtitle: localization.string(.settingsBluetoothOrderDescription)
            ) {
                if orderedBluetoothDevices.isEmpty {
                    Label(
                        localization.string(.settingsBluetoothOrderEmpty),
                        systemImage: "questionmark.circle"
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                } else {
                    List {
                        ForEach(orderedBluetoothDevices) { device in
                            HStack(spacing: 10) {
                                Image(systemName: BluetoothDeviceRowIcon.symbolName(for: device))
                                    .foregroundStyle(device.isConnected ? Color.accentColor : Color.secondary)
                                    .frame(width: 18)

                                Text(device.name)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: "line.3.horizontal")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 3)
                        }
                        .onMove { source, destination in
                            store.moveBluetoothDevices(
                                fromOffsets: source,
                                toOffset: destination,
                                in: orderedBluetoothDevices
                            )
                        }
                    }
                    .listStyle(.inset)
                    .frame(height: orderListHeight)
                }
            }
        }
    }

    /// The order list shows the same sequence the panel renders, so dragging in
    /// Settings moves the row the user is looking at.
    private var orderedBluetoothDevices: [BluetoothDevice] {
        BluetoothDeviceListPresentation.orderedDevices(
            statusStore.bluetoothDevices.devices,
            using: store.bluetoothDeviceOrder
        )
    }

    private var orderListHeight: CGFloat {
        min(max(CGFloat(orderedBluetoothDevices.count) * 32 + 12, 48), 180)
    }
```

并在 `body` 的 `SettingsPage { ... }` 里把这两个 group 加到既有 group 之后。

- [ ] **Step 6: 构建并运行测试**

Run: `swift build -c release`
Expected: 构建成功，0 errors。

Run: `swift test`
Expected: PASS，0 failures。

- [ ] **Step 7: 提交**

```bash
git add Sources/StatusTrioCore/Localization/LocalizationKey.swift \
        Sources/StatusTrioCore/Resources \
        Sources/StatusTrioCore/UI/Settings/BluetoothSectionView.swift
git commit -m "feat(settings): add the Bluetooth panel list and order controls"
```

---

### Task 6: 文档、发布说明与完整验证

**Files:**
- Modify: `docs/bluetooth-status.md`
- Modify: `release-notes/1.3.0/{ar,de,en,es,fr,it,ja,ko,pt-BR,ru,zh-Hans,zh-Hant}.md`

**Interfaces:**
- Consumes: Task 1-5 的最终行为。
- Produces: 行为文档与 12 语言发布说明；本地验证证据。

- [ ] **Step 1: 行为文档补一节**

`docs/bluetooth-status.md` 末尾追加：

```markdown
## The device list in the status panel

`Settings › Bluetooth` can list paired devices under the Bluetooth row. The
connected group always leads; the saved order only reorders devices inside
their own group, so a drag can never lift a disconnected device above a
connected one, and devices with no saved rank land after the ranked ones in
their group. The limit is a total row count, which means a long connected
group can push every disconnected device out of the panel — the detail page
still lists them all.

The list is display-only: this release does not connect or disconnect devices
from the app. Rows render the same shared view as the detail page, so a device
whose report carries no level draws no battery text in either place. Nothing
here starts a new read: the list renders the paired-device report and the level
map the row already claims.
```

- [ ] **Step 2: 12 语言发布说明**

`release-notes/1.3.0/en.md` 末尾追加：

```markdown
## Paired devices in the status panel
- **Settings › Bluetooth** can now list paired devices under the Bluetooth row: the first few are always visible, the rest appear behind an Expand control, and the maximum is yours to set. Connected devices are always listed first.
- Drag devices in Settings to set the order shown in the panel. New devices appear at the end.
```

`release-notes/1.3.0/zh-Hans.md` 末尾追加：

```markdown
## 状态面板里的已配对设备
- **设置 › 蓝牙**现在可以在蓝牙行下方列出已配对设备：默认显示前几台，其余通过「展开」查看，最多显示多少个由你设定。已连接的设备始终排在最前。
- 在设置里拖动设备即可决定面板中的顺序，新设备会出现在末尾。
```

其余 10 种语言按英文段落翻译，术语取各自 `.lproj`（`settings.bluetooth.showDeviceList` 等 Task 5 新键）与同文件既有小节；每语言只追加一个 `##` 小节，首行 `%VERSION%` / `%BUILD%` 占位标题不得改动。

- [ ] **Step 3: 校验说明与 appcast**

Run: `VERSION=1.3.0 BUILD=25 PUBLISH=false bash scripts/validate-appcast-notes.sh`
Expected: PASS，`12 titles and 12 descriptions, en first`。

- [ ] **Step 4: 本地完整验证**

Run: `swift test`
Expected: PASS，0 failures。

Run: `swift build -c release`
Expected: 构建成功，0 errors。

- [ ] **Step 5: 提交**

```bash
git add docs/bluetooth-status.md release-notes/1.3.0
git commit -m "docs: describe the status panel device list in the 1.3.0 notes"
```

- [ ] **Step 6: 请求授权后推送并跑非发布预检**

本次改动触及 SwiftUI 视图体与 `@MainActor` 状态，按仓库规则必须预检；预检要求 ref 已在远端，所以这一步**必须先得到人类伙伴的推送授权**。

```bash
branch=$(git rev-parse --abbrev-ref HEAD)
git push -u origin "$branch"

gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref "$branch" \
  -f version=1.3.0 \
  -f build=25 \
  -f publish=false

run_id=$(gh run list --repo lingyired/status-trio --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run_id" --repo lingyired/status-trio --exit-status
```

Expected: 成功，`publish=false` 不产生 Release、不改 `appcast.xml`。

- [ ] **Step 7: 失败时补 CI 兼容性记录**

若 Step 6 失败，把 run ID、失败阶段、根因、修复与验证结果按既有格式写进 `docs/swift-ci-compatibility.md`，重跑 Step 6，再提交该文件。
