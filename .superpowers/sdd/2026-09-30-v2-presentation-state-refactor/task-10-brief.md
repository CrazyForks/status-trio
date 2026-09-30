### Task 10：蓝牙／详情展示和可见性动作契约

**Files:** Create `Presentation/Panel/BluetoothPanelState.swift`、`BluetoothPanelMapper.swift`、`PanelDetailState.swift`、`PanelDetailMapper.swift`；Modify `StatusPanelActions.swift`；Modify／复用 `UI/BluetoothDeviceListPresentation.swift`、`BluetoothNearbyBatteryListPresentation.swift`、`BluetoothBatteryLevelText.swift`；Create `Tests/StatusTrioCoreTests/BluetoothPanelMapperTests.swift`、`PanelDetailMapperTests.swift`；Modify `BluetoothDeviceActionTargetingTests.swift`、`BluetoothPermissionTimingTests.swift`、`BluetoothListeningModeControllerLifecycleTests.swift`、`BluetoothNearbyBatteryLifecycleTests.swift`。

**Interfaces:**

```swift
struct PanelDetailRow: Equatable, Sendable {
    let id: String; let label: String; let value: String
    let accessibilityValue: String; let tint: PanelTint
    let isCopyable: Bool = false
}
struct PanelDetailState: Equatable, Sendable {
    let title: String; let rows: [PanelDetailRow]
    let isLoading: Bool; let errorText: String?; let explanation: String?
}
struct PanelBluetoothDeviceRow: Equatable, Sendable {
    let address: String; let title: String; let subtitle: String?
    let icon: IconSymbolSource; let batteryText: String?
    let batteryLayout: BluetoothBatteryLayout; let batterySegments: [BluetoothBatterySegment]?
    let isConnected: Bool; let status: BluetoothDeviceRowStatus
    let statusText: String?; let statusTint: PanelTint
    let requiresConfirmation: Bool
    let actionTitle: String; let actionEnabled: Bool; let isBusy: Bool
    let accessibilityLabel: String; let accessibilityValue: String
}
struct BluetoothPanelState: Equatable, Sendable {
    let summary: PanelSummaryState
    let pairedRows: [PanelBluetoothDeviceRow]
    let nearbyRows: [PanelBluetoothDeviceRow]
    let errorText: String?; let showsPairedHeading: Bool
    let canExpand: Bool; let confirmationAddress: String?
}
```

每种 detail Mapper 明确接收现有 controller 的值快照，不把 controller 保存到 state。battery／Wi-Fi／wired 的行集合沿用当前 details view 中已存在字段，按现有顺序生成稳定 row id；技术地址保持只在详情页显示。

`@MainActor PanelDetailMapper.battery(status: BatteryStatus, details: BatteryDetails?, localization: Localization) -> PanelDetailState`、`wired(details: PrimaryLinkDetails?, localization: Localization) -> PanelDetailState`。Wi-Fi 需要列表和控制，不能仅用文本详情行代替：新增 `WiFiPanelState`，含 `detail: PanelDetailState`、`knownRows`／`otherRows: [PanelWiFiNetworkRow]`、`powerIsOn`、`canSetPower`、`canRefresh`、`isScanning`、`message`、`messageIntent: PanelSummaryIntent`；row 含稳定 `key: WiFiNetworkIdentity`、已解析 name／signal symbol／security marker／selected／accessibilityLabel 及 `opensSettings`。identity 只是稳定动作标识，不能让 view 再解释 SSID 或 security。

对应 Mapper 接口为 `PanelDetailMapper.wifi(status: WiFiStatus, networks: [WiFiNetwork], details: WiFiConnectionDetails, listState: WiFiListState, localization: Localization) -> WiFiPanelState`。保留原已知／其他网络分组及 SSID 空白身份，不 trim SSID；当前未连接行打开系统设置，不能趁重构新增 app 内 join 行为。

`WiFiPanelState` 暴露完整的已解析无线详情行、默认 collapsed row count、`visibleDetailRows(expanded:)` 及现有本地化 More／Less 文案。 collapsed count 只控制显示切片，剩余八行仍在 state 中；展开状态保持 view-local。

`StatusPanelActions` 扩展 `refreshBluetooth()`、`rowTapped(address:)`、`performBluetoothAction(address:)`、`requestDisconnect(address:)`、`confirmBluetoothDisconnect(address:)`、`cancelDisconnect()`、`setListeningMode(address:mode:)`，`mode` 使用现有 `BluetoothListeningMode`。普通 row tap 复用 `BluetoothDeviceActionPolicy`：键盘／鼠标断开先请求确认，确认动作验证当前 pending address；view 不解释设备类型。摘要 permission intent 区分 request authorization 与 open permission settings，由独立 action closures 执行。扩展 `batteryDetailsAppeared()`／`batteryDetailsClosed()`、`wifiDetailsOpened()`／`wifiDetailsClosed()`、`wiredDetailsOpened()`／`wiredDetailsClosed()`、`bluetoothSummaryAppeared()`／`bluetoothSummaryDisappeared()`、`volumeListAppeared()`／`volumeListDisappeared()`。summary disappear 释放可见 surface 和 paired battery claim，但保持 Nearby opt-in，直到偏好显式关闭；Settings 和 popover claim 保持独立。

补齐 `setWiFiPower(_ enabled: Bool)`、`refreshWiFi()`，直接调用现有 `wifiNetworks.setPower`／`refreshNow(nameAccess:)`；网络行由解析后的 `opensSettings` 决定 callback。`batteryDetailsAppeared()` 从当前 battery 构造 `BatteryPowerState` 再 activate，电源状态变化由协调器更新激活状态。新增 `moveOutputDevices(from: IndexSet, to: Int)` 和 `moveBluetoothDevices(from: IndexSet, to: Int, displayedAddresses: [String])`；Task 11 必须传当前实际显示的 pairedRows 地址切片（包含 collapsed limit），offsets 对应该切片；collapsed destination `count` 表示插入可见 slice 尾端、未显示行之前。生产协调器用当前过滤／saved order 重新验证显示前缀，过期前缀无操作，再合并到全量 Settings order，保留 hidden／ghost／collapsed 行的 saved ranks；Settings 原始列表不改旧 move 语义。无参数的方法均返回 Void。

- [ ] 新失败 Mapper tests 覆盖连接组排序、saved order、ghost／hidden filter、battery display 开关、nearby 开关、refresh 失败及 disconnect confirmation；与原 helper 输出比较，不重新定义规则。
- [ ] detail tests 覆盖 battery power 行 tint／timestamp／解释文字，wired 不可用仍显示既有五行；Wi-Fi poweredOff／noInterface／denied／failed／scanning／empty、power toggle、refresh capability、known grouping 和系统设置 action。听音模式优先复用已有 `BluetoothListeningModePresentation`；如将文案移入新状态，新增 `PanelListeningModeState`，含每个 mode 的原 action value、title、selected／target／enabled、group accessibility label 和 failure text，不能丢失 enabled selected capsule 语义。
- [ ] Run `swift test --filter 'BluetoothPanelMapperTests|PanelDetailMapperTests|PanelActionRoutingTests'`。从当前 view 解出设备行和 details 的最终文字、符号、能力，原控制器不改所有权。
- [ ] 动作按 normalized address 查找当前设备并执行现有 action targeting，未找到不发出命令；听音模式在当前 controller control 仍存在时调用 `setMode`。预览 synthetic devices 的现有规则由 Mapper／协调器复用 `ListeningModePreview`，不让真实设备被 preview language 覆盖。
- [ ] 将原 `.onAppear`、`.task(id:)`、`.onDisappear` 的 claim／refresh 逻辑逐条搬进 actions 的具名方法：

```swift
func bluetoothSummaryAppeared() {
    bluetoothDevices.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
}
func bluetoothSummaryDisappeared() {
    bluetoothDevices.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
}
```

controller 保存到 actions 可以，保存到展示 state 不可以。battery／nearby 的单独 claim 和 test task id 规则照旧；volume listening mode discovery 只在设备集合或 preview config 改变时 refresh，不增加 timer。

- [ ] 保留并扩展既有 lifecycle tests：popover 关后 late result 丢弃，隐藏蓝牙区域释放自己的 token 但不释放 Settings token；volume disappear 停听音模式，不重启硬件。details 失败／加载／返回文案和动作一致。
- [ ] 完整门槛后提交：`refactor: present bluetooth and detail panels through value state`。
