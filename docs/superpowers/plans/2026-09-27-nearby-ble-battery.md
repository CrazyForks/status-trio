# Nearby BLE Battery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Use the newest available Luna model for implementation, per `AGENTS.md`.

**Goal:** 在用户显式开启且蓝牙状态面板可见时，短时扫描附近设备，读取公开的 BLE Battery Service，并在独立的 Nearby 分组显示电量。

**Architecture:** 保留 `system_profiler + pmset` 已配对设备链路。新的 scanner 只负责 `CBPeripheral.identifier` 身份域、限时扫描及 GATT 读取；`BluetoothDeviceController` 负责权限、popover 生命周期和数据发布。iPhone/iPad 是必须验证的候选设备，不预设它们暴露标准 Battery Service。

**Tech Stack:** Swift 6.3.3、macOS 26 SDK、CoreBluetooth、SwiftUI、Swift Package Manager。

**Spec:** [原方案](../../status-trio-nearby-ble-battery-plan.md)。本计划的“修改决定”覆盖原方案中冲突或未经验证的部分。

## Global Constraints

- CI 验收环境：`macos-26`、Xcode `26.6`、Swift `6.3.3`；构建 SDK 不低于 macOS 26。
- 不使用 `isolated deinit`、`weak let`，不直接传递 actor-isolated 方法函数值。
- 不增加后台扫描、位置权限、外部二进制依赖或持久化设备名称、UUID、广播包。
- Nearby 不使用 MAC 地址或名称去合并 paired identity；GATT 连接不显示为用户意义上的已连接状态。
- 所有 12 种语言补齐设置、面板和权限说明；变更 `NSBluetoothAlwaysUsageDescription` 时同时检查构建后的 bundle。
- Swift 变更提交前运行 `swift test` 和 `swift build -c release`；涉及 actor 隔离、`deinit` 或 SwiftUI binding，合并前运行 `publish=false` 的 release workflow。
- 原方案为 AGPL 项目的研究材料；实现仅据公开 API/标准及自行采集的观察结果编写，不复制 AirBattery 代码或其 packet classifier。

## 修改决定

1. **把 iPhone 支持改成证据关口。** `180F/2A19` 支持标准 BLE 外设，但 Apple 没有承诺 iPhone 对任意 Mac app 广播并提供该服务。先在目标真机记录发现、连接、`180F`、`2A19` 四项结果。若不成立，按用户已确认的范围继续交付标准 BLE 设备功能；不要以 Apple manufacturer data 猜测 iPhone 电量。
2. **P1 不实现 Apple Continuity 广播分类器。** 原方案没有给出可独立复现的 byte pattern、误报率或连接隐私边界。只有真机证明特定候选能提供 `2A19`，且自采样本足以定义筛选规则，才另开后续设计。P1 扫描明确广播 `180F` 的外设；若真实支持 Battery Service 的设备不广播 UUID，记录该限制再设计窄范围补充来源。
3. **区分手动与自动刷新。** 当前 `BluetoothDeviceController.refresh()` 既用于按钮，也被状态变化和 30 秒 safety-net 调用。新增独立 `refreshFromUser()`，按钮调用它；自动扫描按 60 秒间隔。不能在每次 `refresh()` 里无条件触发 BLE 扫描。
4. **明确重复行语义。** Nearby 和 Paired 无共同可靠身份，不能保证同一实体只显示一行。两个分组分别标注来源，不覆盖 paired 电量/动作；真机检查是否出现重复，并据结果决定是否需要后续显式隐藏功能。不要用名称去重。
5. **预算整个扫描会话。** 5 秒是广播扫描窗口；最多 2 个并发 GATT、每设备 4 秒超时，还需给队列设上限（建议每轮 8 个候选）并在窗口结束时丢弃未发起连接的候选。关闭 popover 时立即停止扫描、清空队列并取消所有连接。不要从电量上升推断充电。

## Review Focus

1. 授权未决定且用户只是打开 popover：不创建 scanner 的 `CBCentralManager`，也不弹权限；Task 3 测试。
2. SwiftUI view claim 未释放但 popover claim 已释放：扫描与 GATT 立即停止，旧回调不重新发布；Task 2、3 测试。
3. 同一 UUID 重复广播或快速手动刷新：不出现重复连接、队列无界增长；Task 2 测试。
4. `2A19` 空值、超过 100、GATT 错误或设备信息读取失败：只在合法电量到达时发布，附加信息失败不阻塞；Task 1、2 测试。
5. iPhone 无标准 Battery Service、AirPods 在 paired 与 Nearby 两侧出现：记录真实能力，paired 电量和动作不变，产品文案不虚称覆盖；Task 0、4、5 验收。

## File Structure

- Create `Sources/StatusTrioCore/Models/NearbyBluetoothBatteryDevice.swift`：Nearby 身份、名称、电量、更新时间。
- Create `Sources/StatusTrioCore/Monitoring/BluetoothLEBatteryScanner.swift`：可注入协议、CoreBluetooth adapter、扫描及 GATT 状态机。
- Create `Sources/StatusTrioCore/Monitoring/BluetoothLEBatteryParsing.swift`：`2A19` 和设备信息字符串的纯解析；不加入 Apple 私有广告分类。
- Modify `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`：scanner 注入、claim、popover gate、缓存、手动/自动刷新分流、teardown。
- Modify `Sources/StatusTrioCore/App/AppEnvironment.swift`：在 `makeStore(...)` 中注入 lazy scanner。
- Modify `Sources/StatusTrioCore/UI/BluetoothStatusView.swift`、`StatusPopoverView.swift`；create `UI/NearbyBluetoothBatteryList.swift`：只读 Nearby 组与 claim。
- Modify `Sources/StatusTrioCore/Settings/SettingsStore.swift`、`UI/Settings/BluetoothSectionView.swift`、`Localization/LocalizationKey.swift`、12 个 `Localizable.strings`、`Support/Info.plist`、12 个 `InfoPlist.strings`。
- Create `Tests/StatusTrioCoreTests/BluetoothLEBatteryParsingTests.swift`、`BluetoothLEBatteryScannerStateTests.swift`、`BluetoothNearbyBatteryLifecycleTests.swift`；modify `BluetoothPermissionTimingTests.swift`、`SettingsStoreTests.swift` 及构造 `BluetoothStatusView` 的现有测试。
- Modify `docs/bluetooth-status.md`；发布时按 `AGENTS.md` 为全部 12 种语言准备 release notes。

---

### Task 0: 验证目标设备暴露什么服务

**Files:** Create `docs/nearby-ble-battery-observations.md`（仅匿名结果）；不修改生产代码。

**Interfaces:** 产出“设备类别 × 条件 × 是否发现 × 是否可连 × `180F` × `2A19`”矩阵，供 Task 2 和文案使用。

- [x] **Step 1: 记录基线。** 运行 `swift test --filter BluetoothPermissionTimingTests` 与 `swift test --filter BluetoothPollingLifetimeTests`；记录本机 macOS/Xcode/Swift 版本和测试结果。
- [ ] **Step 2: 做有界只读 probe。** 使用临时、未并入产品的 CoreBluetooth 探针，在明确已授予蓝牙权限的机器上分别观察一台 iPhone、可获得的蜂窝 iPad、一个已知支持标准 Battery Service 的外设。每个条件只扫描 5 秒；记录广播是否含 `180F`、连接成功与否、服务/characteristic 是否存在及可读。遮盖 UUID、名称、原始 manufacturer data。
- [ ] **Step 3: 改变 iPhone 的 Wi-Fi、热点、锁屏条件各观察一次。** 记录系统版本和条件，避免把“未发现”误写为“从不支持”。不自动连接没有明确 `180F` 广播的手机。
- [x] **Step 4: 写能力结论。** 设备探测尚未进行，矩阵将各设备标为未验证；不推断设备缺少标准服务，也不承诺 iPhone/iPad 电量。按用户确认继续交付标准 BLE 功能；真实标准外设验收仍是合并门槛。

### Task 1: Nearby 数据与纯解析

**Files:** Create `Models/NearbyBluetoothBatteryDevice.swift`、`Monitoring/BluetoothLEBatteryParsing.swift`、`Tests/StatusTrioCoreTests/BluetoothLEBatteryParsingTests.swift`。

**Interfaces:** `NearbyBluetoothBatteryDevice.id: UUID`；`BluetoothLEBatteryParsing.percentage(_ data: Data) -> Int?`；`BluetoothLEBatteryParsing.deviceInfo(_ data: Data) -> String?`。模型包含 `name`、`batteryLevel`、`model`、`manufacturer`、`lastUpdated`；不含推断的 `isCharging`。

- [x] **Step 1: 写失败测试。** `percentage` 对空、`0`、`100`、`101`、`255`、多字节值给出明确结果（多字节拒绝）；`deviceInfo` 对 UTF-8、末尾 NUL、全空白、非法 UTF-8 给出明确结果；名称为空时使用本地化的通用名称。
- [x] **Step 2: 运行 `swift test --filter BluetoothLEBatteryParsingTests`，确认新测试因接口未实现而失败。**
- [x] **Step 3: 实现最小解析与模型。** 只接受恰好 1 字节且范围 `0...100` 的 `2A19`；设备信息按 UTF-8 解码并去掉 NUL/首尾空白，不接受不可解码的内容。保持数据结构 `Sendable`。
- [x] **Step 4: 重跑针对性测试。** 预期全部通过；提交本任务代码。

### Task 2: 有界 CoreBluetooth scanner

**Files:** Create `Monitoring/BluetoothLEBatteryScanner.swift`、`Tests/StatusTrioCoreTests/BluetoothLEBatteryScannerStateTests.swift`。

**Interfaces:** `@MainActor protocol BluetoothLEBatteryScanning: AnyObject`，包含 `var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)? { get set }`、`var isRunning: Bool { get }`、`func start()`、`func refresh()`、`func stop()`。`CoreBluetoothLEBatteryScanner.init()` 不创建 `CBCentralManager`。

- [x] **Step 1: 写可注入时钟/状态测试。** 覆盖 5 秒窗口、60 秒自动间隔、每 UUID 成功 60 秒/失败 30 秒 cooldown、8 个候选队列上限、2 个并发 GATT、每设备 4 秒超时、同 UUID 只入队一次、stop 后旧 generation 回调被忽略。状态决策可放同文件的纯 helper；不 mock `CBPeripheral` 层级。
- [x] **Step 2: 运行 `swift test --filter BluetoothLEBatteryScannerStateTests`，确认新测试因接口未实现而失败。**
- [x] **Step 3: 实现 adapter。** 首次 `start()` 且已授权时创建 central；`poweredOn` 后用 `scanForPeripherals(withServices: [CBUUID(string: "180F")])` 开始窗口。发现候选后立即启动可用 GATT 槽位，并在连接完成后于窗口内补充候选；窗口结束时停止广播扫描并丢弃尚未发起连接的候选。只发现 `180F` 及可选 `180A`，分别只读取 `2A19`、`2A24`、`2A29`。电量成功即可发布，设备信息不得拖住发布；查询完成或超时均取消连接。
- [x] **Step 4: 实现完整 teardown。** `stop()` 取消窗口/超时任务、`stopScan()`、清空队列、取消所有连接、清除 delegates、递增 generation；central 状态变为非 `poweredOn` 时走同样清理。`deinit` 按项目现有主 actor teardown 模式处理，不使用 `isolated deinit`。
- [x] **Step 5: 跑自动状态测试。** 队列测试确认并发连接不超过 2、窗口结束丢弃尚未开始的候选，生命周期测试确认 popover 关闭会停止 scanner；标准 BLE 外设真机短测未完成，仍是合并门槛。

### Task 3: Controller 的权限与可见性边界

**Files:** Modify `Monitoring/BluetoothDeviceController.swift`、`App/AppEnvironment.swift`；create `Tests/StatusTrioCoreTests/BluetoothNearbyBatteryLifecycleTests.swift`；modify `BluetoothPermissionTimingTests.swift`。

**Interfaces:** `requestNearbyBatteryDevices(_ token: String)`、`releaseNearbyBatteryDevices(_ token: String)`、`refreshFromUser()`、`@Published private(set) var nearbyBatteryDevices: [NearbyBluetoothBatteryDevice]`。`refresh()` 保持 paired-device 语义；只有自动节流通过时才触发 Nearby，手动入口明确调用 scanner `refresh()`。

- [x] **Step 1: 用 scanner spy 写失败测试。** 断言默认、只有 request、只有 view claim、授权未定、蓝牙关闭均不启动；`isActive && availability == .available && hasVisibleSurface && hasBluetoothSummarySurface && request 非空` 才启动；释放 `popoverSurfaceToken` 立即 stop，即使 view claim 还在；关闭功能/deactivate 清空结果；旧 callback 不重发；手动按钮触发一次独立刷新。
- [x] **Step 2: 运行 `swift test --filter BluetoothNearbyBatteryLifecycleTests` 和 `swift test --filter BluetoothPermissionTimingTests`，确认新增测试因接口缺失而失败。**
- [x] **Step 3: 实现 claim 与缓存。** 对 scanner callback 使用 controller generation gate；结果仅在条件仍成立时发布；缓存只在内存中保留 2 分钟，过期前重新打开可先显示旧结果，关闭设置/deactivate 时清空。popover 关闭与离开 Bluetooth summary 时 stop 并清理 GATT，不依赖 SwiftUI `onDisappear`。
- [x] **Step 4: 在 `AppEnvironment.makeStore(...)` 注入 scanner。** 仅构造对象，确认构造过程不触发 CoreBluetooth 授权。
- [x] **Step 5: 跑两组目标测试与 `BluetoothPollingLifetimeTests`。** 预期既有权限触发时机和 safety-net 语义保持；提交本任务代码。

### Task 4: 设置、面板、文案

**Files:** Modify `SettingsStore.swift`、`BluetoothSectionView.swift`、`BluetoothStatusView.swift`、`StatusPopoverView.swift`、`LocalizationKey.swift`、`Support/Info.plist`、全部 12 种语言的 `Localizable.strings` 与 `InfoPlist.strings`；create `UI/NearbyBluetoothBatteryList.swift`；modify `SettingsStoreTests.swift`、`BluetoothBatteryLevelHandoffTests.swift`、`BluetoothSummaryLayoutTests.swift`。

**Interfaces:** `SettingsStore.showsNearbyBluetoothBatteryDevices`，defaults key 同名，默认 `false`；`BluetoothStatusView` 增加 `showsNearbyBatteryDevices: Bool` 输入，只有它与 `showsBatteryLevels` 同为 true 时提出 Nearby claim。

- [x] **Step 1: 写设置与 UI 行为测试。** 默认关闭、持久化恢复、上层 battery toggle 关闭时不扫描、Nearby 行仅显示合法电量且没有连接/断开动作；带同名 paired/Nearby 数据时保持不同分组，不按名称合并。
- [x] **Step 2: 运行对应过滤测试，确认新增断言先失败。**
- [x] **Step 3: 添加设置和 UI。** Nearby 组仅有非空有效结果时出现，行只读、一行布局、通用名称 fallback 与 VoiceOver 电量值；刷新按钮改为 `refreshFromUser()`。不新增 Dock/菜单栏图标设置，因此不触及 icon parity 路径。
- [x] **Step 4: 补齐 12 种语言及权限用途。** 英文权限文案写明“启用附近扫描后读取附近设备电量”，其余语言语义一致；不声称支持全部 iPhone/iPad。设置描述只提标准 BLE 设备。
- [x] **Step 5: 运行设置、布局、权限测试；构建 app 后用 `plutil` 检查主 `Info.plist` 与每个 `.lproj/InfoPlist.strings` 的 `NSBluetoothAlwaysUsageDescription`。** 提交本任务代码。

### Task 5: 验收、CI、文档

**Files:** Modify `docs/bluetooth-status.md`；若安排发布，按届时确定的版本号在 `release-notes/` 内创建该版本的 12 个语言文件。

- [ ] **Step 1: 真机矩阵。** 按 Task 0 同样条件重测 iPhone、蜂窝 iPad（可获得时）、标准 BLE 外设、AirPods；记录读数、失败原因、扫描/连接耗时、关闭 popover 后资源状态、同一物理设备是否跨分组重复。未获得的设备标“未验证”，不能写成通过。
- [x] **Step 2: 回归测试。** 运行 `swift test` 和 `swift build -c release`；确认现有 paired、AirPods 左/右/盒、权限与 popover 生命周期测试通过。最后一轮本机测试：953 XCTest（6 skipped、0 failures）及 373 Swift Testing tests / 63 suites 通过。
- [x] **Step 3: 非发布 CI 预检。** 因本改动涉及 CoreBluetooth delegate、actor 隔离、`deinit` 和 SwiftUI binding，先准备满足脚本要求的版本注释文件。在实施时从当时已发布版本确定明确且更高的 version/build（当前基线 v1.3.3/build 16，下一组是 1.3.4/build 17），在开发分支执行 `gh workflow run release.yml --repo lingyired/status-trio --ref codex/nearby-ble-battery -f version=1.3.4 -f build=17 -f publish=false`；若期间已有新版本发布，先替换命令中的两个数字。用 `gh run list --repo lingyired/status-trio --workflow release.yml --limit 5` 取得 run ID，再执行 `gh run watch RUN_ID --repo lingyired/status-trio --exit-status`（`RUN_ID` 替换为刚取得的数字）。任何失败按 `docs/swift-ci-compatibility.md` 记录 run ID、stage、根因、修复与复验结果。复验通过：Actions run [36296327089](https://github.com/lingyired/status-trio/actions/runs/36296327089) 在 macOS 26.6.2 / Xcode 26.6 / Swift 6.3.3 上成功；953 XCTest（6 skipped、0 failures）及 373 Swift Testing tests / 63 suites 通过，macOS 26.5 SDK 构建通过 `LC_BUILD_VERSION` 校验，生成并上传 DMG（artifact `StatusTrio-183`），`publish=false` 未发布。
- [x] **Step 4: 更新用户文档与 release notes。** 只描述真机证实的能力和限制；如发布，遵守双语 GitHub Release、12 语言 appcast、Ad-hoc 签名说明及项目 release workflow。已更新 `docs/bluetooth-status.md` 与仅供 `publish=false` 预检的 `release-notes/1.3.4/{en,zh-Hans}.md`；文档明确标准 BLE 服务限制，未声称 iPhone/iPad/AirPods 支持。没有发布版本或 appcast。
- [ ] **Step 5: 最终验收。** 自动化、静态审阅和 CI 已核对默认关闭、无后台扫描、5 秒窗口、2 个并发上限、4 秒设备超时、popover 关闭即断开、合法 `0...100` 电量、不会改变 paired 数据及权限文案。只读代码复核未发现新问题。仍需用真实标准 BLE Battery Service 外设验证发现、连接、`180F/2A19` 读取与 popover 关闭后的资源状态；Task 0 Step 2 与 Task 5 Step 1 未完成，因此此最终验收和合并门槛保持未完成。变更跨监控、设置、UI、本地化，使用 draft PR 留下审阅记录。

## Completion Boundary

用户已确认：即使 iPhone/iPad 没有可读的标准 BLE 电量，本轮仍交付“附近标准 BLE 设备电量”。若 Task 0 没观察到 iPhone/iPad 的 `180F/2A19` 路径，不能以“iPhone 电量”验收，也不要在本计划中临时加入未经验证的 Continuity packet 解析。

## 技术依据

- [Apple CoreBluetooth 扫描 API](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals%28withservices%3Aoptions%3A%29)：指定服务 UUID 只返回广播该服务的外设；因此“未发现”只能说明当前扫描策略未发现，不能证明设备绝不提供服务。
- [Apple Peripheral Manager 文档](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager)：GATT 服务由设备端显式发布，不能根据设备类别推定必有 Battery Service。
- [AirBattery README](https://github.com/lihaoyun6/AirBattery#qa)：其蓝牙 iPhone 路径仅声称支持 iPhone/蜂窝版 iPad，不能据此推断标准 `180F` 在所有目标设备上可读。
