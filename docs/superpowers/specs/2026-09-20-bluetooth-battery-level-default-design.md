# 蓝牙电量默认开启设计

## 目标

1. 「设置 › 蓝牙 › 显示蓝牙设备电量」（`SettingsStore.showsBluetoothBatteryLevels`）默认开启，新装与升级一致。
2. 默认开启不得给不用 AirPods 的用户带来视觉噪声，也不得带来可感知的额外开销。

## 背景与决策依据

现状：该开关默认关闭（`Sources/StatusTrioCore/Settings/SettingsStore.swift:553`，`as? Bool ?? false`）。

决策：**默认改为开启，不做升级识别**；同时把详情页的行规则改成「有电量才显示」。

依据：

- 电量读取是**视图认领制**，不是常开采样。蓝牙面板关闭时没有任何认领，开关状态完全不起作用；面板开着但没有已连接设备时概要行连认领都不发（`Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift` 的前置条件是 `hasConnectedDevices`）。所以默认开启对这两类用户的边际开销是 0。
- 实测边际开销：多一次 `system_profiler -json SPBluetoothDataType`，每次约 0.07–0.14s wall、0.02–0.03s CPU、7.65 MB 峰值 RSS；只在面板打开且真有 AirPods 连着（或手动进详情页）时发生，折合约单核 0.2%。
- 「蓝牙面板默认关闭」的理由是开启面板会弹系统权限提示（`docs/superpowers/plans/2026-09-15-status-panel-settings.md:18`），而该子开关的描述串自己写明「不会额外请求权限」（`zh-Hans.lproj/Localizable.strings:67`），这条理由不适用于它。
- 同页其他「信息更全」的开关默认开启（`showsBatteryPercentage`、`showsChargingIndicator`、`usesBatteryStatusColors`，`SettingsStore.swift:520-525`）。
- 默认关闭的代价是功能不可发现：`README.zh-Hans.md:78` 已经把「读取 AirPods 电量」当作既有能力介绍给用户。

## 迁移

直接翻转默认回落值，不写迁移代码。

影响：UserDefaults 中从来没有该键的存量用户（`object(forKey:) == nil`）会一并变为开启。接受这一点的理由：纯展示、一键可逆、开销可忽略，且仓库已有的升级识别机制（`SettingsStore.swift:470-485` 用 Sparkle 的 `SUHasLaunchedBefore` 区分升级）成本高于收益。

## 详情页显示规则

- 报告里带了电量 → 显示 `Text(level)`（沿用 `.caption.monospacedDigit()` 与 ` · ` 拼接）。
- 报告里没有该设备的电量 → **不渲染任何文本**，不再逐行显示「暂不可用」。
- 规则提取为纯函数 `BluetoothDevicePresentation.batteryLevelText(for:batteryLevels:) -> String?`，与 `BluetoothSummary.presentation` 一样可脱离 SwiftUI 单测。

概要行同样给每个已连接设备拼上报告里真有的电量（`Sources/StatusTrioCore/Models/WiFiNetworkModels.swift` 的 `BluetoothSummary.entry(for:)`），不再只给 AirPods。

## 读取失败的呈现

改规则后，「报告读不出来」如果不处理就会完全静默。因此：

- `BluetoothBatteryReading.read(completion:)` 的完成回调参数改为 `[String: BluetoothBatteryLevel]?`，`nil` 表示报告读取失败；成功的空报告仍是 `[:]`。
- `BluetoothDeviceController` 新增 `@Published private(set) var batteryLevelsReadFailed`，在读取完成时按 `levels == nil` 置位，在 `clearBatteryLevels()`（释放最后一个 claim、切换 availability、`deactivate()`）时清零。
- 详情页在失败时于列表下方显示**一行** `bluetooth.battery.unavailable`，不再是每行一个占位。该本地化键已存在，本次不新增键、不动 12 个 `.lproj`。

## 测试

- `SettingsStoreTests`：新装（无键）默认 `true`；非布尔脏值回落 `true`；持久化行为不变。
- 新增 `BluetoothDeviceRowBatteryTextTests`：有电量 / 无电量 / 首次读取未完成三种情形。
- `BluetoothBatteryControllerTests`：失败置位且不编造电量；随后的空报告清除失败标志；释放 claim 清除标志。
- `BluetoothSummaryTests` 改为钉住「每个已连接设备显示报告里真有的电量」与「没有电量的设备只显示名字」。

## 不在本次范围内

- 蓝牙面板（`PopupSection.bluetooth`）本身的默认值保持关闭。
- 设置页在蓝牙面板关闭时置灰/收起相关开关（本次明确不做）。
- 合并设备列表与电量两路重复的 `system_profiler` 调用（独立优化）。
- 不改动菜单栏/Dock 图标渲染或图标相关设置。

## 后续修订（2026-09-21，实测后的第 2 轮）

- **概要行改为显示每个已连接设备的电量**（不再只给 AirPods）：`BluetoothSummary.entry(for:)` 去掉 AirPods 白名单，`hasConnectedAirPods` 变成 `hasConnectedDevices`，`.devices` 不再携带该标志。理由：`f416890` 的报告缓存让"摘要行也认领"通常不再多起 `system_profiler`（复用设备列表刚存下的同一份报告），剩下的只是显示取舍，用户明确选择信息更全。
- **删除 `BluetoothDevice.isAirPods` / `isAirPodsSummaryCandidate`**：白名单消失后它们只剩测试消费者。产品 ID → 型号的识别仍在 `AirPodsModel` / `airPodsModel`，图标路径（`BluetoothDeviceRowIcon`）继续使用。
- **修复"开关后不实时更新"**：摘要行的 `.task(id:)` 在 guard 失败时只 `return`、不释放 claim，而 `onDisappear` 要等离开该行才跑 —— 于是关掉开关后读取仍在跑、电量仍显示，直到进详情页再返回。现在 guard 失败即 `releaseBatteryLevels`，由 `BluetoothBatteryLevelHandoffTests.testTurningTheSettingOffReleasesTheSummaryClaimImmediately` 钉住（先失败后修复）。
- **AirPods 无条件排在最前**：`BluetoothDevicePresentation.grouped` 先按 AirPods 再按名称排序（Connected / Not connected 分组内一致）。起因是 CI（英文 collation）与本机（中文 collation）对 `机灵的耳机` 与 `MX Keys` 的先后判断相反，导致只断言拼接结果的新用例在 CI 上失败；现在顺序由规则决定、与名字无关，混合脚本的用例也重新变得可断言。`BluetoothDevice.isAirPods` 因此恢复，但用途只剩排序（产品 ID 命中或名字含 "airpods"），电量认领不再依赖它。
