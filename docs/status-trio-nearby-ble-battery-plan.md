# Status Trio — Nearby BLE Battery / iPhone Battery Implementation Plan

> 基于 Status Trio 当前 `main`（2026-09-27）设计。
>
> 本计划的目标不是复制 AirBattery，而是在 Status Trio 现有的 Bluetooth 生命周期、权限、claim、watchdog 和 UI 架构之上，独立实现一套 **Nearby BLE Battery** 数据源。第一阶段重点支持标准 BLE Battery Service，并把 iPhone / 蜂窝版 iPad 作为重点验证对象。

---

## 1. 目标

为 Status Trio 的 Bluetooth 面板增加一个新的、按需工作的 BLE 电量来源：

- 发现附近可提供标准 BLE Battery Service 的设备。
- 读取标准 GATT Battery Service：
  - Service `180F` — Battery Service
  - Characteristic `2A19` — Battery Level
- 可选读取 Device Information Service：
  - Service `180A`
  - `2A24` — Model Number String
  - `2A29` — Manufacturer Name String
- 尝试覆盖 AirBattery 当前的 “通过蓝牙发现 iPhone / iPad” 能力。
- 在 Bluetooth 面板中将这些设备显示为独立的 **Nearby** 分组。
- 不改变现有已配对设备的 `system_profiler + pmset` 电量链路。
- 不增加后台常驻扫描；扫描只在用户明确开启功能且 Bluetooth UI 可见时运行。

最终体验示例：

```text
Bluetooth

Connected
  AirPods Pro               L 85% · R 88% · [Case] 62%
  MX Keys                                           73%

Nearby
  iPhone                                            61%
  BLE Mouse                                         48%
```

第一阶段的 Nearby 行只展示信息，不承担连接 / 断开动作。

---

## 2. 当前架构基线

Status Trio 当前 Bluetooth 实现已经具备以下能力，**本轮必须复用而不是重写**：

### 2.1 已配对设备来源

`Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`

- `SystemProfilerBluetoothPairedDeviceWorker`
- `/usr/sbin/system_profiler -json SPBluetoothDataType`
- 已连接 / 未连接设备列表
- 地址规范化
- 设备类型识别
- I/O Registry HID 修正
- IOBluetooth 连接 / 断开动作

### 2.2 已配对设备电量

`Sources/StatusTrioCore/Monitoring/BluetoothBatteryReader.swift`

当前已解析：

```text
device_batteryLevelMain
device_batteryLevel
device_batteryLevelLeft
device_batteryLevelRight
device_batteryLevelCase
```

所以 AirPods 的主电量、左右耳和充电盒电量已经存在，不需要重新实现。

### 2.3 accessory fallback

`Sources/StatusTrioCore/Monitoring/BluetoothAccessoryBatteryReader.swift`

使用：

```bash
/usr/bin/pmset -g accps -xml
```

只补充 profiler 缺失的 accessory level，不覆盖 profiler 已有结果。

本轮必须保持这个优先级：

```text
system_profiler
      ↓ primary
paired-device battery
      ↓ missing only
pmset accessory source
```

Nearby BLE 是第三条**独立数据源**，不要参与以上两个 source 的 merge。

### 2.4 生命周期机制

当前 `BluetoothDeviceController` 已经有：

- `activate()` / `deactivate()`
- `visibleSurfaces`
- `popoverSurfaceToken`
- battery level claim token
- 30 秒 safety-net poll
- IOBluetooth connection notification
- accessory battery notification
- async request gate
- watchdog
- late completion invalidation
- popover 关闭时的资源释放

Nearby BLE 必须遵循同一原则：

> UI 不可见时，不扫描。

不要采用 AirBattery 启动 App 后常驻 `CBCentralManager.scanForPeripherals` 的模式。

---

## 3. 第一阶段明确范围

### In Scope

1. 标准 BLE Battery Service `180F / 2A19`。
2. Device Information `180A / 2A24 / 2A29`。
3. Apple BLE advertisement candidate 分类，用于提高发现 iPhone / iPad 的概率。
4. iPhone / 蜂窝版 iPad 真机验证。
5. Nearby 独立列表。
6. Nearby 开关、生命周期、权限文案和本地化。
7. 单元测试 + 真机验证。
8. 扫描 / GATT 连接的限流、超时与清理。

### Out of Scope

以下内容本轮**明确不实现**：

- `libimobiledevice`
- USB / Wi-Fi iPhone battery
- Apple Watch battery
- Apple Pencil battery
- `idevicesyslog`
- `/usr/bin/log show` 蓝牙日志解析
- `IOBluetoothDevice` 私有 KVC：
  - `batteryPercentSingle`
  - `batteryPercentLeft`
  - `batteryPercentRight`
  - `batteryPercentCase`
- AirPods raw BLE packet 电量解析
- AirPods open / close 广播解析
- Magic Mouse / Keyboard IORegistry fallback
- 后台持续 BLE scanning
- 根据电量上升推断 Charging
- 用设备名称强行把 BLE peripheral 和现有 paired device 合并

这些能力以后按独立 phase 评估。

---

## 4. 设计原则

### 4.1 Nearby 和 Paired 是两个身份域

现有 `BluetoothDevice` 使用 Bluetooth address，例如：

```text
AC:90:85:C2:9C:1F
```

CoreBluetooth 只提供：

```text
CBPeripheral.identifier
UUID
```

普通 App 无法稳定取得 BLE MAC address。

因此禁止做：

```text
CBPeripheral UUID → 猜 MAC → BluetoothDevice
```

也禁止仅根据名字自动 merge：

```text
"MX Master 3S" == "MX Master 3S"
```

名字不是身份凭证。

第一阶段使用独立 model：

```swift
struct NearbyBluetoothBatteryDevice: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var kind: NearbyBluetoothDeviceKind
    var manufacturer: String?
    var model: String?
    var batteryLevel: Int
    var lastSeen: Date
    var lastUpdated: Date
}
```

建议：

```swift
enum NearbyBluetoothDeviceKind: Equatable, Sendable {
    case iPhone
    case iPad
    case appleDevice
    case peripheral
    case unknown
}
```

不要直接复用 `BluetoothDevice`，因为：

- 它的 `id` 当前隐含 Bluetooth address 语义。
- 现有行支持 classic Bluetooth connect / disconnect。
- Nearby device 的连接只是一段内部 GATT 查询，不是用户意义上的“连接设备”。

---

## 5. 新增 Scanner 抽象

新增：

```text
Sources/StatusTrioCore/Monitoring/BluetoothLEBatteryScanner.swift
```

首先定义可注入协议：

```swift
@MainActor
protocol BluetoothLEBatteryScanning: AnyObject {
    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)? { get set }

    var isRunning: Bool { get }
    var isScanning: Bool { get }

    func start()
    func refresh()
    func stop()
}
```

生产实现：

```swift
@MainActor
final class CoreBluetoothLEBatteryScanner:
    NSObject,
    BluetoothLEBatteryScanning,
    CBCentralManagerDelegate,
    CBPeripheralDelegate
```

### 关键要求

`CoreBluetoothLEBatteryScanner.init()` **不得创建 `CBCentralManager`**。

必须 lazy：

```text
init
  ↓
manager == nil

start()
  ↓
create CBCentralManager
```

原因：

Status Trio 当前有一条已经被测试锁住的产品契约：

> 打开 popover 本身不能主动触发 Bluetooth permission prompt。

新 scanner 不能破坏 `BluetoothPermissionTimingTests` 的语义。

---

## 6. BLE 扫描候选规则

不要连接扫描到的所有 BLE peripheral。

AirBattery 对非 Apple 设备比较激进，而 Status Trio 应该更克制。

### Candidate A — 明确广播 Battery Service

读取：

```swift
CBAdvertisementDataServiceUUIDsKey
```

如果含：

```text
180F
```

进入 GATT 查询。

### Candidate B — Apple iOS / Continuity candidate

读取：

```swift
CBAdvertisementDataManufacturerDataKey
```

首先验证 Apple Company Identifier：

```text
0x004C
```

然后由新的纯函数 classifier 判断是否属于本轮允许 probe 的 iOS candidate。

新增：

```text
Sources/StatusTrioCore/Monitoring/AppleBLEAdvertisementClassifier.swift
```

接口建议：

```swift
enum AppleBLEAdvertisementClassifier {
    static func candidate(from manufacturerData: Data) -> AppleBLECandidate?
}
```

候选类型至少：

```swift
enum AppleBLECandidate: Equatable {
    case mobileDevice
}
```

第一版只需要识别 AirBattery 所利用的 iOS / Personal Hotspot / Continuity 类型，并且把这些 byte pattern 当成**候选条件**，不能直接当作最终身份。

也就是说：

```text
Apple advertisement
      ↓
mobile candidate
      ↓
尝试连接
      ↓
180A / 180F
      ↓
读取真实 model / manufacturer / battery
      ↓
最终分类
```

不要：

```text
某个 byte == 0x10
→ 直接显示为 iPhone
```

### Candidate C — 本 session 已成功读取过的 peripheral

如果某 UUID 在本进程中已经成功提供过 `2A19`，后续 refresh 可以重新 probe，即使它这一次 advertisement 没带 `180F`。

这样可以提高重复刷新稳定性，同时避免连接所有未知设备。

---

## 7. GATT 查询流程

对 candidate：

```text
didDiscover
   ↓
rate limit
   ↓
connection queue
   ↓
central.connect(peripheral)
   ↓
didConnect
   ↓
discoverServices([180F, 180A])
   ↓
180F → discover [2A19]
180A → discover [2A24, 2A29]
   ↓
readValue
   ↓
publish / disconnect
```

### Battery Level

`2A19`：

```swift
guard let first = data.first, first <= 100 else { reject }
```

只接受：

```text
0...100
```

### Model / Manufacturer

`2A24` / `2A29`：

- UTF-8 优先。
- 必要时 ASCII fallback。
- trim `\0`、空格和换行。
- 读取失败不能影响 battery publication。

### 完成条件

Battery 是唯一必需字段。

只要成功获得 `2A19`，该 peripheral 就有资格进入 Nearby 列表。

Model / manufacturer 属于 enhancement：

```text
battery success + device info success
→ publish rich device

battery success + device info timeout/failure
→ publish generic device
```

---

## 8. 连接并发与超时

Nearby discovery 不能一口气连接几十个设备。

默认：

```text
maxConcurrentConnections = 2
```

每个 peripheral：

```text
connection / GATT timeout = 4 seconds
```

扫描 window：

```text
5 seconds
```

扫描结束不代表已发起的最多两个 GATT 查询立刻被取消；只要 UI 仍可见，可允许其完成。

但 `stop()` 必须立即：

1. `stopScan()`
2. cancel scan stop task
3. cancel pending candidate queue
4. `cancelPeripheralConnection()` 所有 in-flight peripheral
5. 清理 peripheral delegates / session state
6. invalidates generation token
7. 阻止 late callback 再 publish

必须设计类似现有 `AsyncRequestGate` 的 generation：

```text
sessionGeneration
```

任何来自旧 session 的 callback 都必须被丢弃。

---

## 9. Refresh 限流

同一个 peripheral 不要反复连。

建议：

```text
成功读取 cooldown: 60 s
失败 cooldown:   30 s
```

同一扫描 session 内同一 UUID 只入队一次。

`refresh()`：

- 如果当前正在 scan：不重复启动。
- 如果 scanner 已 start 但不在 scan：开始新的 5 秒窗口。
- 手动 refresh 可以绕过 session-level refresh interval，但仍遵守 per-device connection cooldown；如果希望手动按钮完全强制刷新，可以单独加 `forceRefresh()`，第一版没必要。

---

## 10. Cache / Stale 策略

Controller 对外发布：

```swift
@Published private(set)
var nearbyBatteryDevices: [NearbyBluetoothBatteryDevice] = []
```

建议只在内存缓存，不落磁盘。

TTL：

```text
2 minutes
```

行为：

- popover 关闭时停止 scanner，但不一定立刻清空 cache。
- 两分钟内重新打开可以先显示最近一次结果，同时立即 refresh。
- refresh 后更新 `lastSeen` / `lastUpdated`。
- 超过 TTL 的设备在发布前 prune。
- `deactivate()` 或用户关闭 Nearby 功能时清空。

这样可以避免每次重新打开 popover 出现明显的“列表先空、几秒后跳出来”。

---

## 11. iPhone / iPad 最终分类

广告只能定义 candidate，最终类型从已读信息推导。

优先级：

### 1. Model Number

如果：

```text
model begins with "iPhone"
```

→ `.iPhone`

如果：

```text
model begins with "iPad"
```

→ `.iPad`

### 2. Peripheral name

Model 不可用时，如果 name 明确包含：

```text
iPhone
iPad
```

可以用作 UI kind fallback。

### 3. Apple manufacturer

如果：

```text
Manufacturer == "Apple Inc."
```

但无法进一步判断，则：

```text
.appleDevice
```

不要仅凭 Apple company ID 就显示为 iPhone。

### 4. Generic

其他成功提供 `2A19` 的设备：

```text
.peripheral / .unknown
```

第一版不要做复杂 name-based 鼠标 / 键盘类型推断；避免复制现有 paired device classifier 的语义到一个信息明显更少的数据源。

---

## 12. Charging 状态

第一版 Nearby model **不要包含推断出来的 `isCharging`**。

不要采用：

```text
60% → 61%
所以正在充电
```

这种 AirBattery 式推断。

标准 `2A19` 只提供 Battery Level，并不能可靠给出 charging 状态。

UI 第一版只显示：

```text
61%
```

只有未来获得可靠 source 后再增加 charging state。

---

## 13. Controller 集成

修改：

```text
Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift
```

新增 init dependency：

```swift
nearbyBatteryScanner: (any BluetoothLEBatteryScanning)? = nil
```

生产环境注入，测试默认 nil。

新增：

```swift
@Published private(set)
var nearbyBatteryDevices: [NearbyBluetoothBatteryDevice] = []
```

新增 claim：

```swift
private var nearbyBatteryRequests: Set<String> = []
```

API：

```swift
func requestNearbyBatteryDevices(_ token: String)
func releaseNearbyBatteryDevices(_ token: String)
```

状态判断集中到：

```swift
private func updateNearbyBatteryScanner()
```

启动条件必须全部满足：

```text
isActive
AND availability == .available
AND hasVisibleSurface
AND nearbyBatteryRequests is not empty
```

否则：

```text
scanner.stop()
```

这里 `hasVisibleSurface` 必须使用现有 `popoverSurfaceToken` 规则，而不能只检查 SwiftUI view claim。

原因：当前 popover content controller 会保留一段时间，`onDisappear` 不一定在 popover 关闭时发生。现有 Bluetooth 代码已经为这个问题专门做过修复。

### Controller lifecycle 修改点

`activate()`：

- 不直接启动 nearby scanner。
- 等 availability + surface + request 满足时才启动。

`receiveSystemState(...)`：

- `.available` → `updateNearbyBatteryScanner()`
- powered off / denied / restricted / unavailable → stop scanner

`holdVisibleSurface(...)`：

- 原逻辑后调用 `updateNearbyBatteryScanner()`。

`releaseVisibleSurface(...)`：

- 原逻辑后调用 `updateNearbyBatteryScanner()`。
- popover token 被释放时必须立即停 scan。

`deactivate()`：

- clear `nearbyBatteryRequests`
- stop scanner
- clear `nearbyBatteryDevices`

`refresh()` / 手动 refresh：

当 scanner 当前满足运行条件时：

```swift
nearbyBatteryScanner?.refresh()
```

但不要让 Nearby scan 的 completion 阻塞 `system_profiler` 的 paired-device refresh。

两条链独立并行。

---

## 14. 和现有 safety-net poll 的关系

不要新增永久 Timer。

推荐复用现有 Bluetooth surface 生命周期，但 Nearby scanner 自己维护 5 秒 scan window。

第一版：

- 首次 request → `start()` → 立即 scan 5 秒。
- 用户点击现有 refresh button → paired refresh + BLE refresh。
- 现有 30 秒 Bluetooth safety-net refresh 执行时，如果 nearby scanner 正在 requested 状态，可调用 `refresh()`。

由于 scanner 自己有 cooldown：

- 已成功设备不会每 30 秒重新连接。
- scan window 可以发现新出现设备。

如果实测 30 秒 × 5 秒 scanning duty 太高，再把 BLE 内部最小 scan interval 调到 60 秒；不要改变整个 Bluetooth safety-net cadence。

建议先提供：

```swift
minimumAutomaticRefreshInterval = 60 seconds
```

手动 refresh 不受这个 automatic interval 限制。

---

## 15. Settings

修改：

```text
Sources/StatusTrioCore/Settings/SettingsStore.swift
Sources/StatusTrioCore/UI/Settings/BluetoothSectionView.swift
```

新增：

```swift
@Published var showsNearbyBluetoothBatteryDevices: Bool
```

Defaults key：

```text
showsNearbyBluetoothBatteryDevices
```

默认：

```text
false
```

原因：

- 会产生真实 BLE scan。
- 会主动短暂连接 nearby GATT peripheral。
- 会增加 Bluetooth 功耗。
- 会展示之前 Status Trio 不展示的附近设备。

用户应该显式 opt in。

### Settings UI

放在当前：

```text
显示蓝牙设备电量
```

附近，作为从属能力。

建议文案：

中文：

```text
显示附近设备电量
仅在状态面板打开时扫描附近支持 BLE 电量服务的设备。部分设备可能不会提供电量信息。
```

英文：

```text
Show nearby device batteries
Scans nearby Bluetooth LE devices only while the status panel is open. Some devices may not expose battery information.
```

当：

```text
showsBluetoothBatteryLevels == false
```

Nearby toggle 可以：

- disabled，但保留用户值；或
- UI 隐藏。

建议 **disabled + 保留用户值**，行为更可预期。

实际 scanner claim 需要：

```text
showsBluetoothBatteryLevels
AND showsNearbyBluetoothBatteryDevices
```

---

## 16. Bluetooth permission 文案必须更新

当前：

```text
NSBluetoothAlwaysUsageDescription
```

文案语义只提到：

```text
show paired-device connection status
```

新增 BLE scan 后已经不准确。

修改：

```text
Support/Info.plist
Sources/StatusTrioCore/Resources/*/InfoPlist.strings
```

建议英文：

```text
Used to show Bluetooth device status and, when you enable nearby battery scanning, read battery information exposed by nearby Bluetooth LE devices.
```

简中：

```text
用于显示蓝牙设备状态，并在你开启附近设备电量扫描后读取附近蓝牙低功耗设备提供的电量信息。
```

繁中：

```text
用於顯示藍牙裝置狀態，並在你開啟附近裝置電量掃描後讀取附近低功耗藍牙裝置提供的電量資訊。
```

其他本地化同步更新。

非常重要：

> 更新权限说明 ≠ 改变权限触发时机。

必须继续保持：

```text
notDetermined + merely opening popover
→ NO CBCentralManager start
→ NO permission prompt
```

只有已有授权，或者用户明确执行现有“启用 Bluetooth / 请求授权”动作后，Nearby scanner 才允许工作。

---

## 17. UI

新增：

```text
Sources/StatusTrioCore/UI/NearbyBluetoothBatteryList.swift
Sources/StatusTrioCore/UI/NearbyBluetoothBatteryRow.swift
```

不要复用 `BluetoothDeviceRow`。

原因：

`BluetoothDeviceRow` 当前是一条 action row：

- paired / connected state
- connect
- disconnect
- input device disconnect confirmation
- action states

Nearby row 没有这些语义。

### NearbyBluetoothBatteryRow

建议：

```text
[icon] Device Name                      61%
       Model / Manufacturer (optional)
```

但为了保持 Status Trio popover 紧凑，第一版建议只显示一行：

```text
[icon] Device Name                      61%
```

tooltip / accessibility 可以包含 model / manufacturer。

图标：

```text
iPhone       iphone
iPad         ipad
AppleDevice  apple.logo 或 dot.radiowaves.left.and.right
Peripheral   dot.radiowaves.left.and.right
Unknown      dot.radiowaves.left.and.right
```

如果项目现有 icon style 不接受 `apple.logo`，统一 generic wireless glyph。

### Nearby group

在 `BluetoothStatusView` 中：

```text
paired BluetoothDeviceList
↓
Nearby header
↓
NearbyBluetoothBatteryList
```

只在：

```text
showsNearbyBluetoothBatteryDevices
AND !nearbyBatteryDevices.isEmpty
```

时显示。

不要在没有结果时常驻一个空的 “Nearby” 标题。

第一版不显示 spinner；现有 refresh button 已足够表达刷新动作。

如果后续用户反馈“不知道是否正在搜”，再加入轻量 scanning indicator。

---

## 18. BluetoothStatusView claim

修改：

```text
Sources/StatusTrioCore/UI/BluetoothStatusView.swift
```

新增 input：

```swift
let showsNearbyBatteryDevices: Bool
```

新增 token：

```swift
private static let nearbyBatteryToken = "bluetooth.summary.nearby-battery"
```

增加 task：

```text
if showsBatteryLevels && showsNearbyBatteryDevices
    requestNearbyBatteryDevices(token)
else
    releaseNearbyBatteryDevices(token)
```

`onDisappear` 继续 release。

但 controller 的 `updateNearbyBatteryScanner()` 必须额外依赖 `hasVisibleSurface`，因此即使 SwiftUI 因 popover retention 漏掉 `onDisappear`，popover-level token 释放后 scanner 仍然会停止。

这是必须单测的行为。

---

## 19. StatusPopoverView

修改：

```text
Sources/StatusTrioCore/UI/StatusPopoverView.swift
```

调用：

```swift
BluetoothStatusView(
    ...,
    showsBatteryLevels: settings.showsBluetoothBatteryLevels,
    showsNearbyBatteryDevices: settings.showsNearbyBluetoothBatteryDevices,
    ...
)
```

不需要增加新的 page / navigation。

---

## 20. AppEnvironment 注入

修改：

```text
Sources/StatusTrioCore/App/AppEnvironment.swift
```

生产：

```swift
BluetoothDeviceController(
    accessoryBatteryReader: PmsetAccessoryBatteryWorker(),
    nearbyBatteryScanner: CoreBluetoothLEBatteryScanner(),
    connectionEvents: IOBluetoothConnectionEventMonitor(),
    accessoryBatteryEvents: AccessoryPowerNotifyEventMonitor()
)
```

注意：

`CoreBluetoothLEBatteryScanner()` 构造本身不能创建 manager，因此这个注入不会在 App launch 时申请权限或开始扫描。

---

## 21. Localizations

修改：

```text
Sources/StatusTrioCore/Localization/LocalizationKey.swift
Sources/StatusTrioCore/Resources/*/Localizable.strings
Sources/StatusTrioCore/Resources/*/InfoPlist.strings
```

新增至少：

```text
settings.bluetooth.nearbyBatteryDevices
settings.bluetooth.nearbyBatteryDevicesDescription
bluetooth.nearby.title
```

英文：

```text
Show nearby device batteries
Scans nearby Bluetooth LE devices only while the status panel is open. Some devices may not expose battery information.
Nearby
```

简中：

```text
显示附近设备电量
仅在状态面板打开时扫描附近支持 BLE 电量服务的设备。部分设备可能不会提供电量信息。
附近设备
```

繁中：

```text
顯示附近裝置電量
僅在狀態面板開啟時掃描附近支援 BLE 電量服務的裝置。部分裝置可能不會提供電量資訊。
附近裝置
```

其余语言沿现有 localization 流程补齐。

---

## 22. Pure helper 测试优先

不要一开始就在测试里 mock `CBPeripheral`。

CoreBluetooth 对象很难直接构造，第一阶段把可测试逻辑提成纯函数。

新增：

```text
Tests/StatusTrioCoreTests/AppleBLEAdvertisementClassifierTests.swift
Tests/StatusTrioCoreTests/BluetoothLEBatteryValueTests.swift
```

### AppleBLEAdvertisementClassifierTests

覆盖：

- empty data → nil
- truncated data → nil
- non-Apple company id → nil
- Apple unrelated packet → nil
- supported iOS candidate → `.mobileDevice`
- malformed packet 不 crash

不要在测试里复制 AirBattery 的实现代码；fixture 是协议数据样本。

### Battery parser

抽成：

```swift
enum BluetoothLEBatteryValue {
    static func percentage(from data: Data) -> Int?
}
```

测试：

```text
[]       → nil
[0]      → 0
[1]      → 1
[50]     → 50
[100]    → 100
[101]    → nil
[255]    → nil
```

Device info string parser 同样做纯函数测试。

---

## 23. Controller lifecycle tests

新增：

```text
Tests/StatusTrioCoreTests/BluetoothNearbyBatteryLifecycleTests.swift
```

使用：

```swift
final class BluetoothLEBatteryScannerSpy: BluetoothLEBatteryScanning
```

至少覆盖：

### Case 1 — 默认不扫描

```text
controller init
→ scanner.startCount == 0
```

### Case 2 — 只有 request，不可见

```text
requestNearbyBatteryDevices
→ scanner.startCount == 0
```

### Case 3 — 可见但没有 request

```text
hold popover surface
→ scanner.startCount == 0
```

### Case 4 — available + visible + request

```text
→ scanner.startCount == 1
```

### Case 5 — popover close

即使 view token 没有 release：

```text
release popoverSurfaceToken
→ scanner.stopCount == 1
```

这是本轮最重要的 lifecycle regression test。

### Case 6 — powered off

```text
running
→ Bluetooth manager poweredOff
→ scanner.stop
```

### Case 7 — deactivate

```text
→ scanner.stop
→ nearbyBatteryDevices == []
```

### Case 8 — late scanner callback

```text
stop/deactivate
→ old session emits devices
→ controller ignores
```

如果 scanner protocol 本身只在 scanner 内部解决 generation，则 controller test 至少确认 stop 后 spy 不再能改变公开状态。

### Case 9 — manual refresh

```text
running nearby scanner
controller.refresh()
→ scanner.refreshCount += 1
```

### Case 10 — no permission prompt regression

扩展：

```text
BluetoothPermissionTimingTests
```

`authorization == .notDetermined`：

```text
open popover
→ stateMonitor.startCount == 0
→ nearbyScanner.startCount == 0
```

---

## 24. Settings tests

修改：

```text
Tests/StatusTrioCoreTests/SettingsStoreTests.swift
```

覆盖：

```text
new install default == false
persist false → true
reload == true
```

如果 UI 有 disabled rule，把规则抽为纯函数，不做脆弱的 SwiftUI snapshot 测试。

---

## 25. UI presentation tests

建议新增纯 presentation：

```text
Sources/StatusTrioCore/UI/NearbyBluetoothBatteryPresentation.swift
```

处理：

- TTL prune 后排序
- iPhone / iPad 优先级（可选）
- name fallback
- battery formatting
- accessibility value

建议排序：

```text
1. iPhone / iPad / Apple mobile
2. 其他设备按 localizedStandardCompare(name)
```

如果不希望 Apple 特殊优先，第一版全部按 name 即可；关键是排序必须 deterministic，避免 CI locale 漂移。

测试：

```text
stable order
expired devices hidden
0% shown
100% shown
unknown name fallback
```

---

## 26. Scanner state tests

真实 `CBCentralManager` 不适合普通单测。

不要为了测试生产 scanner 去建立一整套 Objective-C CoreBluetooth fake hierarchy。

应把以下部分抽离为可测 state / helper：

- advertisement candidate classification
- `2A19` parsing
- string parsing
- device classification
- cooldown decision
- TTL decision

生产 `CoreBluetoothLEBatteryScanner` 重点靠：

- controller-level spy tests
- manual integration test
- small amount lifecycle logging during development

完成后移除 debug logs 或走项目现有 Logger 策略，不能 `print` device names / identifiers。

---

## 27. Privacy / Logging

不要 log：

- peripheral UUID
- 用户设备名称
- iPhone 名称
- manufacturer data raw payload

生产日志只能记录聚合状态，例如：

```text
BLE nearby scan started
BLE nearby scan stopped
BLE nearby scan discovered candidate count=2
BLE nearby battery read succeeded count=1
```

如果项目当前坚持无 debug Logger，则保持现状即可。

不要持久化：

```text
CBPeripheral.identifier
raw advertisement data
battery history
```

---

## 28. Info.plist / entitlement 检查

当前项目已经链接 `CoreBluetooth` 并存在：

```text
NSBluetoothAlwaysUsageDescription
```

因此本轮通常不需要新增 entitlement。

但实现前必须确认 build 产物的最终 Info.plist 确实包含更新后的 Bluetooth usage string。

不要因为 Nearby feature 再增加位置权限。

BLE battery scanning 本身不应该依赖 CoreLocation。

---

## 29. Performance budget

Nearby feature 默认关闭，所以正常用户：

```text
additional CPU ≈ 0
additional scan = 0
additional CBCentralManager = 0
```

开启后：

```text
popover closed
→ scanner stopped
→ no BLE scan
→ no GATT connection
```

popover open：

```text
initial 5 s scan
+ bounded GATT queries
```

不允许：

```text
5 s scan / 5 s stop / forever
```

也不允许 App launch 就创建第二个长期活动的 `CBCentralManager`。

### 验收性能标准

菜单栏冷启动、从未打开 Settings / popover：

- 不应出现 Nearby scanner activity。
- 不应因为本功能产生新的 periodic task。
- 不应有额外 child process。

关闭 popover 后：

- `CBCentralManager.isScanning == false`
- no outstanding GATT sessions
- no recurring BLE timer/task

---

## 30. 真机验证矩阵

至少使用以下环境验证。

### A. iPhone

条件：

- Bluetooth on
- iPhone 在附近
- Wi-Fi 状态分别测试 on/off
- Personal Hotspot 分别测试 on/off（用于验证 candidate availability）

验证：

```text
能否发现
能否 connect GATT
是否存在 180F
是否能读 2A19
是否存在 180A
2A24 返回什么
2A29 返回什么
锁屏前后差异
闲置几分钟后的差异
```

不要在完成真机测试之前把产品文案写成：

```text
“支持所有 iPhone”
```

应该写：

```text
“支持附近提供 BLE 电量信息的设备，包括部分 iPhone / iPad”
```

直到验证覆盖足够设备型号 / iOS 版本。

### B. iPad

分别验证：

- Wi-Fi only iPad
- cellular iPad（如果有条件）

AirBattery 自己提示 BLE 路径主要适用于 iPhone / 蜂窝版 iPad，所以 Wi-Fi-only iPad 失败不能视为 Status Trio regression。

### C. 普通 BLE peripheral

至少一个真正提供 standard Battery Service 的设备。

验证：

```text
0~100 level
重复 refresh
设备离开范围
重新进入范围
关机
```

### D. 现有 AirPods

确保 Nearby 功能不会：

- 让现有 paired AirPods 行重复。
- 覆盖现有 L/R/Case 数据。
- 改变 AirPods connect/disconnect 行为。

### E. Permission

全新 TCC 状态：

```text
launch
→ no prompt

open popover
→ no prompt if current product contract says no prompt

explicit Bluetooth enable / authorization action
→ prompt

after allowed + nearby toggle enabled + popover visible
→ BLE scan
```

---

## 31. Regression 测试

实现完成后至少运行：

```bash
swift test --filter BluetoothPermissionTimingTests
swift test --filter BluetoothPollingLifetimeTests
swift test --filter BluetoothBatteryReaderTests
swift test --filter BluetoothBatteryLevelHandoffTests
swift test --filter BluetoothDeviceListPresentationTests
swift test --filter SettingsStoreTests
swift test --filter BluetoothNearbyBatteryLifecycleTests
swift test --filter AppleBLEAdvertisementClassifierTests
swift test --filter BluetoothLEBatteryValueTests
```

然后：

```bash
swift test
```

再运行项目已有 forbidden-pattern / CI preflight 流程。

尤其注意 Swift 6 当前项目已有约束：

- 不把 actor-isolated method 直接当 function value。
- 新 async callback 要明确 actor hop。
- teardown 必须完整。
- 新定时 / polling 必须 bounded、有 lifecycle owner。

---

## 32. 文件改动清单

### 新增

```text
Sources/StatusTrioCore/Models/NearbyBluetoothBatteryDevice.swift
Sources/StatusTrioCore/Monitoring/BluetoothLEBatteryScanner.swift
Sources/StatusTrioCore/Monitoring/AppleBLEAdvertisementClassifier.swift
Sources/StatusTrioCore/UI/NearbyBluetoothBatteryList.swift
Sources/StatusTrioCore/UI/NearbyBluetoothBatteryRow.swift
Sources/StatusTrioCore/UI/NearbyBluetoothBatteryPresentation.swift

Tests/StatusTrioCoreTests/AppleBLEAdvertisementClassifierTests.swift
Tests/StatusTrioCoreTests/BluetoothLEBatteryValueTests.swift
Tests/StatusTrioCoreTests/BluetoothNearbyBatteryLifecycleTests.swift
Tests/StatusTrioCoreTests/NearbyBluetoothBatteryPresentationTests.swift
```

`BluetoothLEBatteryValue` / string parser 如果足够小，可以定义在 scanner 文件中，不要求为了文件数单独拆文件。

### 修改

```text
Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift
Sources/StatusTrioCore/App/AppEnvironment.swift
Sources/StatusTrioCore/UI/BluetoothStatusView.swift
Sources/StatusTrioCore/UI/StatusPopoverView.swift
Sources/StatusTrioCore/UI/Settings/BluetoothSectionView.swift
Sources/StatusTrioCore/Settings/SettingsStore.swift
Sources/StatusTrioCore/Localization/LocalizationKey.swift
Support/Info.plist
Sources/StatusTrioCore/Resources/*/Localizable.strings
Sources/StatusTrioCore/Resources/*/InfoPlist.strings
Tests/StatusTrioCoreTests/BluetoothPermissionTimingTests.swift
Tests/StatusTrioCoreTests/SettingsStoreTests.swift
```

视实现方式可能还需修改：

```text
README*.md
release-notes/<next-version>/*
docs/bluetooth-status.md
```

---

# 33. 建议按以下 Task 顺序实施

## Task 0 — Baseline

在任何生产代码修改前：

1. `swift test` 全绿。
2. 记录当前 Bluetooth permission timing tests。
3. 记录 idle 时无 BLE scan。
4. 真机记录一份当前 iPhone advertisement sample，仅作为协议验证 fixture 来源；不要把设备名 / UUID 提交到仓库。

Commit：无。

---

## Task 1 — Model + Pure Parsers

新增：

```text
NearbyBluetoothBatteryDevice
NearbyBluetoothDeviceKind
AppleBLEAdvertisementClassifier
BluetoothLEBatteryValue
BluetoothLEDeviceInfoString
```

先写失败测试，再实现。

完成条件：

```bash
swift test --filter AppleBLEAdvertisementClassifierTests
swift test --filter BluetoothLEBatteryValueTests
```

全绿。

建议 commit：

```text
feat(bluetooth): add nearby BLE battery models and parsers
```

---

## Task 2 — Scanner Protocol + Production Scanner

新增 `BluetoothLEBatteryScanning` 和 `CoreBluetoothLEBatteryScanner`。

必须实现：

- lazy CBCentralManager
- bounded 5 s scan
- candidate filter
- max 2 GATT connections
- 4 s timeout
- 180F / 2A19
- optional 180A / 2A24 / 2A29
- cooldown
- generation invalidation
- complete `stop()`

这一步先不要接 UI。

提供一个开发期手动 probe 能力即可，不新增正式菜单。

建议 commit：

```text
feat(bluetooth): add bounded BLE battery scanner
```

---

## Task 3 — Controller Lifecycle Integration

修改 `BluetoothDeviceController`：

- inject scanner
- publish nearby devices
- request / release tokens
- updateNearbyBatteryScanner
- refresh integration
- stop on visibility / availability / deactivate
- TTL prune

先写 `BluetoothNearbyBatteryLifecycleTests`。

这一步的硬验收：

```text
popover close always stops BLE scanning
```

即使 SwiftUI view claim 没释放。

建议 commit：

```text
feat(bluetooth): gate nearby battery scanning by visible surfaces
```

---

## Task 4 — Settings + Permission Copy

新增 `showsNearbyBluetoothBatteryDevices`，默认 false。

更新 Bluetooth Settings 页面。

更新 `NSBluetoothAlwaysUsageDescription`。

补全 SettingsStore tests 和 localization。

建议 commit：

```text
feat(settings): add nearby Bluetooth battery option
```

---

## Task 5 — UI

新增 Nearby row / list。

修改：

```text
BluetoothStatusView
StatusPopoverView
```

Nearby rows：

- read-only
- one line
- no connect/disconnect action
- no charging inference
- no duplicated paired-device state

补 presentation tests。

建议 commit：

```text
feat(bluetooth): show nearby BLE battery devices in status panel
```

---

## Task 6 — AppEnvironment Wiring

正式注入：

```text
CoreBluetoothLEBatteryScanner
```

重新跑 Permission Timing tests。

确保仅创建 scanner object 不会实例化 `CBCentralManager`。

建议 commit：

```text
feat(bluetooth): wire nearby BLE battery scanner
```

如果 Task 3 已经需要注入，也可以与 Task 3 合并，不强制单独 commit。

---

## Task 7 — Manual Device Validation

在 macOS 27 真机执行：

- iPhone
- 可用的话 cellular iPad
- generic BLE Battery Service peripheral
- AirPods

记录：

```text
advertisement candidate
GATT service availability
battery read success/failure
scan duration
connection duration
CPU impact
popover close cleanup
```

根据结果调整 candidate / timeout，但不要为了提高发现率变成“连接所有附近 BLE 设备”。

---

## Task 8 — Documentation / Release

更新：

```text
docs/bluetooth-status.md
README / README.zh-Hans.md
release notes
```

产品文案在真机矩阵完成前保持保守：

```text
Supports battery levels from nearby Bluetooth LE devices that expose the standard Battery Service. Availability varies by device and OS version.
```

不要宣称：

```text
Supports every iPhone / iPad
```

除非测试证据已经支持。

---

# 34. Acceptance Criteria

本功能可以合并到 main 的最低标准：

### Functional

- Nearby toggle 默认关闭。
- 开启后，符合条件的标准 BLE battery device 可显示 0–100%。
- 至少在一台目标 iPhone 上完成真机测试；如果当前 iOS 不暴露 180F，需要明确记录为平台限制，而不是伪造 fallback。
- Nearby device 有稳定名称 fallback。
- Existing paired-device battery 行为不变。
- AirPods L / R / Case 不回归。

### Lifecycle

- App launch 不开始 Nearby scan。
- popover closed 不扫描。
- setting off 不扫描。
- powered off / denied / restricted 不扫描。
- `deactivate()` 完整 teardown。
- late callbacks 不 republish stale devices。

### Permission

- Nearby scanner 不改变当前 permission prompt timing。
- Usage Description 与真实行为一致。

### Performance

- 默认配置 idle overhead ≈ 0。
- scanner 不产生 child process。
- scan 是 bounded window，不是 continuous。
- concurrent GATT connection ≤ 2。

### Tests

- 所有新增 targeted tests 通过。
- `swift test` 全绿。
- 现有 Bluetooth lifecycle / permission tests 全绿。

---

# 35. 第二阶段候选，不进入本 PR

完成 P1 后再逐项评估：

### P2 — AirPods Advertisement Enhancer

独立实现 Apple AirPods raw BLE advertisement parser：

```text
Left
Right
Case
Charging
open / closed packet
```

只能作为 `system_profiler / pmset` 的实时增强，不能覆盖更可信 source。

### P3 — iPhone USB / Wi-Fi Provider

评估独立 MobileDevice provider：

```text
USB trust once
→ Wi-Fi pairing
→ com.apple.mobile.battery
```

不要直接复制 AirBattery bundled binaries；单独完成 dependency / license / notarization / packaging 设计。

### P4 — Apple Watch / Pencil

单独调研，不和 P3 偷绑在一起。

### P5 — IORegistry Magic Device Fallback

只有确认现有 `system_profiler + pmset` 对特定 Apple HID 有稳定缺口后再增加。

---

# 36. License / Clean-room 要求

AirBattery 项目本体为 AGPL-3.0，Status Trio 当前为 Apache-2.0。

因此本实现必须：

- 不复制 AirBattery Swift 文件。
- 不复制 `logReader.sh`。
- 不复制其 bundled libimobiledevice binaries。
- 不复制具体代码结构。
- 只基于公开协议、系统 API 行为和独立采集的 packet / GATT 数据重新实现。

BLE 标准 UUID、Apple company identifier、实际观测 packet 字段属于实现研究输入；提交到 Status Trio 的代码应使用自己的命名、状态机、测试 fixture 和错误处理。

---

# 37. 最终架构

完成 P1 后：

```text
                         BluetoothDeviceController
                                   │
           ┌───────────────────────┼────────────────────────┐
           │                       │                        │
           ▼                       ▼                        ▼
 system_profiler              pmset accps            CoreBluetooth LE
 Paired devices               fallback               Nearby devices
           │                       │                        │
           │                       │                  advertisement
           │                       │                        │
           │                       │                  candidate filter
           │                       │                        │
           │                       │                   GATT connect
           │                       │                        │
           │                       │                ┌───────┴───────┐
           │                       │                │               │
           ▼                       ▼               180F            180A
 Main / L / R / Case        missing levels         2A19        2A24 / 2A29
           │                       │                │               │
           └────────── paired battery ─────────────┘               │
                                                                   │
                                                     NearbyBluetoothBatteryDevice
                                                                   │
                                                                   ▼
                                                            Nearby UI group
```

这三条 source 保持边界清楚：

```text
Paired identity  ≠ Nearby identity
```

不因为名字相同而强行合并。

---

## 推荐最终产品范围

这一轮只解决一个清晰问题：

> **当用户打开 Status Trio 的 Bluetooth 面板，并显式启用 Nearby Battery 时，短暂扫描附近 BLE 设备，读取它们主动暴露的标准电量，并把结果作为独立 Nearby 分组显示。**

它不改变 Status Trio 的核心 Bluetooth 架构，不增加默认后台成本，也为后续 iPhone / Apple accessory 能力留下清晰的数据源边界。
