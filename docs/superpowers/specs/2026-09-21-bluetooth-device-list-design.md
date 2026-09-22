# 蓝牙设备列表内联展示设计

## 目标

1. 在状态面板的蓝牙行下方**内联展示已配对设备列表**（已连接组在前，其次未连接），默认开启。
2. 提供「最多显示个数」与「设备顺序」两项设置，语义与控件形态**镜像现有的音量输出列表**。
3. 本轮只做展示与排序；**不在 app 内连接或断开设备**。

## 背景与参照

参照物（音量输出列表，全部已存在）：

- `Sources/StatusTrioCore/UI/OutputDeviceListPresentation.swift` — `orderedDevices`（保存顺序优先、未记录的新设备接在原顺序之后）、`visibleDevices`（`prefix(limit)`）、`canToggleExpansion`（设备数超过上限时才给展开控件）。
- `Sources/StatusTrioCore/UI/OutputDeviceList.swift` — 渲染前 N 行；超出时在列表下方渲染「展开/收起」chevron，展开状态是视图内 `@State`。
- `Sources/StatusTrioCore/UI/Settings/AudioSectionView.swift:55-140` — 设置侧形态：`SettingsRow` + `Stepper`（`in: SettingsStore.outputDeviceLimitRange`）与 `List` + `.onMove` 拖动排序。
- `SettingsStore.outputDeviceLimitRange = 1...20`、`defaultMaxVisibleOutputDevices = 5`、`moveOutputDevices(fromOffsets:toOffset:in:)`。

现状：

- 概要行的蓝牙行副标题拼接**已连接**设备名，AirPods 会带上 `L/R/Case` 电量（`BluetoothSummary.presentation`）。
- 详情页（点蓝牙行）已经列出全部配对设备，分「已连接 / 未连接」两组，并把每个设备的电量交给 `BluetoothDevicePresentation.batteryLevelText(for:batteryLevels:)`。
- **概要面板没有滚动容器、也没有高度上限**（只有 Wi-Fi 与蓝牙详情页有 `ScrollView().frame(maxHeight: 330)`）。因此默认铺开 N 行会让面板变高；这与「音量列表展开」是同类行为，本设计沿用该约定。

## 可行性调研结论（本轮不实现，记录以备后续）

关于「能否用 app 开关某个蓝牙设备」，只读调研（本机 SDK = MacOSX27.0）结论：

- **公开 API 存在**：`IOBluetoothDevice` 提供 `openConnection`、`openConnection:withPageTimeout:authenticationRequired:`、`closeConnection`、`isConnected`、`performSDPQuery`；这些方法上**没有** `DEPRECATED` / `API_AVAILABLE` 标注。仓库已链接 IOBluetooth，`IOBluetoothConnectionEventMonitor` 已在用它注册连接/断开通知，无需新依赖。
- **CoreBluetooth 不可用**：macOS SDK 的 CoreBluetooth 头文件**完全不出现** `Classic` / `BR/EDR`，只有 LE API。AirPods、音箱这类经典蓝牙设备不能用 `CBCentralManager.connect` 连接。
- **整机 radio 开关只有私有 API**：公开 API 无法开关蓝牙，第三方工具（如 blueutil）用的是 `IOBluetoothPreference*()` 私有接口，随系统更新易碎，不作为产品能力。
- **音频设备的受支持间接路径**：把设备设为默认输出（CoreAudio）会让 macOS 自行建立链路——仓库已实现输出设备切换；但「断开」没有受支持的对应能力。
- **未实测项**：`openConnection` 对 AirPods 这类由音频栈接管的设备是否可靠；`closeConnection` 后系统音频栈是否立即重连。若未来要做，先写一次性 probe 在真实设备上实测，再决定是否作为正式能力。

## 默认值

`showsBluetoothDeviceList` 默认 **true**。理由：该开关只对已经开启蓝牙面板的用户生效；列表复用既有的配对库读数（`system_profiler`）与电量字典，不新增任何采样；与「显示蓝牙设备电量默认开启」同理。

存量用户：UserDefaults 中不存在该键的人**同样变为开启**（不写迁移，与上一次默认值变更保持一致的做法）。

## 数据模型

`SettingsStore` 新增三项（沿用现有 `@Published` + `didSet` 持久化写法）：

| 属性 | 默认值 | key | 约束 |
| --- | --- | --- | --- |
| `showsBluetoothDeviceList` | `true` | `showsBluetoothDeviceList` | — |
| `maxVisibleBluetoothDevices` | `5` | `maxVisibleBluetoothDevices` | clamp 到 `1...20` |
| `bluetoothDeviceOrder` | `[]` | `bluetoothDeviceOrder` | 元素是设备地址的规范化形式 `BluetoothBatteryReader.normalizedAddress(device.id)`，与电量字典同一套键，避免大小写/分隔符差异导致匹配失败 |

另新增：

- `static let bluetoothDeviceLimitRange: ClosedRange<Int> = 1...20`。**不改名复用**音频的 `outputDeviceLimitRange`：共用虽少一个常量，但要改音频设置 UI 与 `SettingsStoreTests:411` 的既有断言，收益不抵波及面。
- `func moveBluetoothDevices(fromOffsets:toOffset:in devices: [BluetoothDevice])`，镜像 `moveOutputDevices` 的越界保护与「移动后以当前可见顺序整体重写顺序数组」语义。

## 排序与上限语义

1. **分组固定**：先取 `BluetoothDevicePresentation.grouped(_:)`——已连接组在前，组内保持既有规则（AirPods 领先、其余按名称）。**拖动不能跨越分组**。
2. **组内按保存顺序**：有记录的设备按 `bluetoothDeviceOrder` 的秩排在前，未记录的保持第 1 步的顺序接在该组末尾。
3. **上限 N 是总行数**（不是每组 N）：已连接先占位，因此已连接设备数量 ≥ N 时，未连接设备会被完全挤出面板（详情页仍可看全）。
4. **渲染**：`visibleDevices = prefix(N)`；`orderedDevices.count > N` 时在列表下方渲染「展开/收起」chevron，展开状态是视图内 `@State`，面板关闭即重置。

## 视图结构

- 新增 `BluetoothDeviceListPresentation`（纯函数）与 `BluetoothDeviceListModel`（`orderedDevices` / `visibleDevices` / `canToggleExpansion`），镜像 `OutputDeviceListPresentation` / `OutputDeviceListModel`，可脱离 SwiftUI 单测。
- 新增 `BluetoothDeviceList` 视图：渲染可见行 + chevron。**行不可点**（本轮只展示）。
- 抽出共用行视图 `BluetoothDeviceRow`：图标（`BluetoothDeviceRowIcon.symbolName(for:)`）+ 名称 + 电量文本（`BluetoothDevicePresentation.batteryLevelText(for:batteryLevels:)`）+ 连接状态，并保留详情页现有的 `.accessibilityElement(children: .combine)` 处理。**面板列表与详情页共用**，避免两处漂移；电量文本继续受既有 `showsBluetoothBatteryLevels` 控制。
- **详情页的分组与顺序不变**：`bluetoothDeviceOrder` 只影响状态面板里的内联列表；详情页继续按 `BluetoothDevicePresentation.grouped(_:)` 的既有顺序展示全部设备。
- 列表挂在 `BluetoothStatusView` 内部（蓝牙行下方），以便沿用它的 `holdVisibleSurface` / `requestBatteryLevels` 生命周期。
- **副标题**：列表开启且状态为 `.devices`（有已连接设备）时**不渲染副标题**；列表关闭时完全保持今天的行为；`.requestAuthorization` / 初始化 / 关闭 / 不可用 / 读取失败 / 无已连接设备这些状态一律不变。

## 设置界面（设置 › 蓝牙）

新增两组：

1. 「状态面板列表」：`SettingsToggleRow`（显示开关）+ 仅当开启时出现的 `SettingsRow` + `Stepper`（`in: SettingsStore.bluetoothDeviceLimitRange`，左侧等宽显示当前值），布局照搬 `AudioSectionView`。
2. 「设备顺序」：`SettingsCustomRow` + `List` + `.onMove` → `moveBluetoothDevices`，含空态文案与「已连接设备始终排在最前」的脚注。

**不加**音频那个「显示全部设备」设置开关：面板里的「展开」chevron 已覆盖「这次想全看」的需求。

## 本地化

新增 10 个键，12 种语言必须齐全（`LocalizationTests` 会遍历 `LocalizationKey.allCases` × 全部语言）：

| key | 英文文案（其余语言按各自 `.lproj` 术语翻译） |
| --- | --- |
| `settings.bluetooth.showDeviceList` | Show the Bluetooth device list |
| `settings.bluetooth.showDeviceListDescription` | Lists paired devices under the Bluetooth entry in the status panel. Connected devices come first. |
| `settings.bluetooth.maximumVisible` | Maximum visible Bluetooth devices |
| `settings.bluetooth.maximumVisibleDescription` | How many devices appear before the Expand control. |
| `settings.bluetooth.orderTitle` | Bluetooth Device Order |
| `settings.bluetooth.orderDescription` | Drag devices to change the order shown in the status panel. Connected devices always come first, and new devices appear at the end. |
| `settings.bluetooth.orderEmpty` | No paired devices available. |
| `settings.bluetooth.orderFootnote` | Connected devices are always listed first. |
| `bluetooth.list.expand` | Expand |
| `bluetooth.list.collapse` | Collapse |

复用既有键：`bluetoothTitle`、`bluetoothActionOpenSettings`、`bluetoothConnected`、`bluetoothNotConnected`、`settingsBluetoothBatteryLevels`。

副标题采用「隐藏」方案，因此**不新增**条数摘要键——本地化层只有 `Localization.format(_:_:)`（`String(format:locale:)`）、没有 ICU 复数，避免 "1 devices" 这类瑕疵。

## 边界与错误处理

- 设备数为 0：不渲染列表区，只保留蓝牙行与既有状态文案。
- 设备数 == N：不出现 chevron。`N = 1` 正常。`N` 被 clamp 在 `1...20`。
- 已连接数量 ≥ N：未连接设备不可见（见「上限语义」第 3 条）。
- `bluetoothDeviceOrder` 含已不存在/已改名的地址：忽略该条目，无副作用；设备换地址后按「新设备」接在组尾。
- 视图状态（是否展开）在面板关闭后重置，与音量列表一致。
- 面板关闭 / 蓝牙关闭 / 未授权 / 读取失败：**不渲染列表**，由既有状态文案单独表达，避免「空列表 + 错误提示」重复表达。
- **读取策略不变**：列表只渲染既有 `controller.batteryLevels`，不新增任何 `system_profiler` 调用；电量 claim 的触发条件仍是 `showsBatteryLevels && hasConnectedDevices`。

## 测试

- 新增 `BluetoothDeviceListPresentationTests`：分组不可跨越、保存顺序优先、未记录设备接组尾、`prefix(N)`、`canToggleExpansion`、`N = 1`、空数组。
- `SettingsStoreTests`：三个新键的默认值、持久化、clamp、脏值回落；`moveBluetoothDevices` 的越界保护与顺序重写。
- `BluetoothSummaryLayoutTests`：更新现有 `height < 120` 断言，覆盖「列表开 / 列表关 / 超出上限」三种情形。
- 详情页测试保持绿：抽出 `BluetoothDeviceRow` 后，详情页的视觉与文案不得改变。
- 12 语言由 `LocalizationTests` / `LocalizationParityTests` 自动覆盖。

## 不在本次范围内

- 在 app 内连接 / 断开蓝牙设备（含 IOBluetooth 方案与 CoreAudio「设为默认输出」方案）。调研结论见上，留待后续单独决策。
- 音频那种「显示全部设备」设置开关。
- 菜单栏 / Dock 图标与图标相关设置的任何改动（因此图标 parity 规则不触发）。
- 新增系统权限或新的后台采样。
- 把设备列表塞进 Wi-Fi 面板或电池面板。
