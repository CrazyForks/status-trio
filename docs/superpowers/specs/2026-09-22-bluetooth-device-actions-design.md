# 蓝牙设备动作（点击连接/断开）设计

## 目标

1. 状态面板与蓝牙详情页的**设备行可点击**：未连接 → 连接；已连接 → 断开（toggle）。
2. 键鼠类设备（`.peripheral`）的**断开**需要行内确认，且**不关闭面板**。
3. **不做乐观翻转**：行的连接状态始终以真实报告/系统通知为准，动作失败必须可见。

## 背景：已完成的可行性验证

在 macOS 27 本机、对一台已连接的 AirPods 类设备（`AC:90:85:C2:9C:1F`）实测 `IOBluetooth`，结果为（一次性探针，产物已弃）：

| 步骤 | 结果 |
| --- | --- |
| `closeConnection()` | 返回 `0`（`kIOReturnSuccess`），约 0.5s 后确认断开 |
| 断开后观察 4 秒 | **仍为断开**——系统没有自动回连 |
| `openConnection()` | 返回 `0`，约 0.5s 后确认连接 |
| 系统通知 | 两个方向都收到 IOBluetooth 的连接/断开通知（应用已在监听这条链路） |
| 收尾 | 设备恢复为连接状态，无残留副作用 |

由此得到三条硬约束：

1. **必须按规范化地址匹配设备，绝不使用 IOBluetooth 的名字。** 同一台设备在 `system_profiler` 里叫「机灵的耳机」，在 IOBluetooth 里仍报改名前的缓存名「陈敬祥的AirPods」。仓库既有的 `BluetoothBatteryReader.normalizedAddress(_:)` 同时兼容 `AC:90:85:C2:9C:1F` 与 `ac-90-85-c2-9c-1f` 两种写法。
2. **`openConnection()` 是同步调用**：设备不在范围内时可能阻塞到 page timeout（数秒），因此必须在后台队列执行，绝不能落在主线程或按钮回调里。
3. **不需要新权限**：探针是无签名、无 Info.plist 的命令行程序，仍能完成连接/断开；`IOBluetoothDevice.pairedDevices()` 读的是应用已通过 `system_profiler` 读取的同一份配对库。

另外，**只在一台机器的 macOS 27 上验证过**（见「风险」）。

## 动作执行层

沿用仓库既有的「protocol + worker 队列」风格，新增：

```swift
protocol BluetoothDeviceActionPerforming: AnyObject {
    /// 在后台队列上按规范化地址找到设备并调用 open/closeConnection，
    /// 回传指令是否被系统接受（`kIOReturnSuccess`）。同步调用不得落在主线程。
    func setConnected(
        _ connected: Bool,
        forAddress address: String,
        completion: @escaping @Sendable (Bool) -> Void
    )
}
```

实现要点：

- 在专用 `DispatchQueue` 上先取 `IOBluetoothDevice.pairedDevices()`，按 `normalizedAddress` 找到目标；找不到即回传 `false`（设备可能刚被解绑）。
- 只回传「指令是否被系统接受」；**连接是否真的建立由状态机等待报告/通知判定**，不由返回值决定。
- 用到的 `pairedDevices()` / `openConnection()` / `closeConnection()` 都是 IOBluetooth 长期存在的 API，**不需要 `@available` 门槛**，在最低支持的 macOS 15 上即可用（但见「风险」：未在 15–26 上实测）。
- IOBluetooth 的具体实现不做单测（依赖真实硬件），controller 逻辑通过该 protocol 的 stub 覆盖。

## 状态机

动作状态挂在 `BluetoothDeviceController` 上（它已持有设备列表、报告与连接通知），按**规范化地址**分桶：

| 状态 | 进入 | 离开 |
| --- | --- | --- |
| `idle` | 初始；动作确认完成 | — |
| `connecting` / `disconnecting` | 用户点行（键鼠断开先经行内确认） | 报告或通知显示连接状态已变为目标值 → `idle`；或超时 |
| `failed` | 指令返回非 0，或 **10 秒**内状态未变 | 约 **4 秒**后自动回 `idle` |

- **不做乐观翻转**：点击后行的「已连接/未连接」文字不变，只显示进行中指示；最终状态由既有的 `system_profiler` 报告 + 连接通知驱动的刷新决定。
- **竞态**：状态变化（通知/报告）优先于超时；超时只在状态未变时触发失败。进入新状态或结束时取消上一个超时任务。
- **面板关闭不中断动作**：状态在 controller 上，面板关闭后再打开仍显示进行中/失败。

## 确认规则

纯函数（可单测）：

```
requiresConfirmation(kind: BluetoothDeviceKind, isConnected: Bool) -> Bool
// == (kind == .peripheral && isConnected)
```

即只有「当前已连接的键鼠/触控板/手柄」在**断开**时才需要确认；音频设备、手机等直接执行；未连接设备一律直接执行（连接动作没有误断风险）。

## UI 呈现

- **可点区域**：面板列表与详情页**共用同一个 `BluetoothDeviceRow`**，因此两处都可点、行为一致。行改成一个 `.plain` 样式的 `Button` 加 `.contentShape(Rectangle())`；**不新增** chevron 或悬停高亮等额外提示，可发现性由无障碍 label 承担。
- **进行中**：行尾原本的「已连接/未连接」文字位置换成 `ProgressView` + 「连接中…」/「断开中…」。
- **失败**：同一位置显示「连接失败」/「断开失败」（强调色），约 4 秒后恢复真实状态。失败态**可以再点**（重试），新的动作会立刻清掉失败提示。
- **键鼠断开的行内确认**：该行临时变为：左侧图标、设备名与电量文本**保持不变**，行尾位置换成 `断开「<设备名>」？` 加 `[断开]` `[取消]` 两个按钮；**面板保持打开**（面板是 transient 的，NSAlert 之类的弹窗会把它关掉，因此确认必须做在行内）。取消即恢复。
- **不可重复触发**：进行中与确认中的行不可再点。
- **确认态的面板关闭语义**：确认态是视图内 `@State`，面板关闭即视为取消，绝不执行未确认的断开。
- **无障碍**：行的 label 说明当前动作（例如「MX Keys，已连接，双击断开」），进行中与失败状态通过 `accessibilityValue` 读出。

## 本地化

新增 7 条键，12 语言齐全（`LocalizationTests` 遍历所有键 × 全部语言）：

| key | 英文文案（其余语言按各自 `.lproj` 既有术语翻译） |
| --- | --- |
| `bluetooth.action.disconnect` | Disconnect |
| `bluetooth.action.cancel` | Cancel |
| `bluetooth.state.connecting` | Connecting… |
| `bluetooth.state.disconnecting` | Disconnecting… |
| `bluetooth.state.connectFailed` | Could not connect |
| `bluetooth.state.disconnectFailed` | Could not disconnect |
| `bluetooth.action.confirmDisconnect` | Disconnect “%@”? |

复用既有键：`bluetoothConnected` / `bluetoothNotConnected`（行内状态文字）、`bluetoothTitle`。
`confirmDisconnect` 用 `Localization.format`（`String(format:locale:)`）带入设备名。

## 边界与错误处理

- 设备不在范围内 / 没电：指令可能返回非 0 或状态迟迟不变 → 走 `failed`，行回到真实状态。
- 地址在 `pairedDevices()` 中找不到（刚被解绑）：直接判失败，不崩。
- 不同设备可并行操作（状态按地址分桶）。
- 断开正在播放音频的设备：探针显示约 0.5s 生效且系统不自动回连；音频会切回上一个输出，这是 macOS 自身行为，本设计不干预，但写入文档。
- 电量显示不受影响：动作不新增任何读数；连接后若设备报告电量，既有链路会带出来。

## 风险

1. **只在 macOS 27 本机验证过**，最低支持版本是 macOS 15。`IOBluetooth` 这套 API 多年未变且未标废弃，但无法在 macOS 15–26 上验证；因此「失败就诚实显示失败」是设计要求，不是可选项。
2. `openConnection()` 的同步特性：必须后台队列 + 超时保护。
3. 行内确认依赖面板处于打开状态；用户点到别处即取消（安全方向）。
4. 未新增权限、未新增后台轮询、未使用私有 API。

## 测试

- **状态机**（stub `BluetoothDeviceActionPerforming`）：点未连接 → `connecting`；报告变为已连接 → `idle`；指令返回 `false` → `failed`；10 秒内状态不变 → `failed`；`failed` 约 4 秒后自动回 `idle`。
- **确认规则**纯函数：`.peripheral` + 已连接 → 需要确认；`.peripheral` + 未连接 → 不需要；`.audio` / `.phone` / `.computer` / `.unknown` + 已连接 → 不需要。
- **不可重复触发**：进行中或确认中的地址再次点击不产生第二次指令。
- **渲染**：行内确认态与进行中/失败态会改变行高——用既有布局测试的风格钉住（英文与简体中文各一次）。
- **12 语言**：由 `LocalizationTests` / `LocalizationParityTests` 自动覆盖。
- IOBluetooth 的真实路径不做单测，由已完成的探针与本机手动测试覆盖。

## 不在本次范围内

- 设备配对 / 解绑 / 取消配对。
- 改用 CoreBluetooth（macOS SDK 无 Classic/BR-EDR API，无法连接经典蓝牙设备）。
- 「点击打开系统蓝牙设置」这类替代路径。
- 新增系统权限或后台轮询。
- 菜单栏 / Dock 图标与图标相关设置的任何改动。
- 在 macOS 15–26 上的验证（已知限制，见「风险」）。
