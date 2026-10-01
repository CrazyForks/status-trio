# 外接显示器音量监控 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 按仓库 `AGENTS.md` 的模型偏好，实施本书面计划时使用当时最新的 Luna 模型；当前为 `gpt-6-luna`。

**Goal:** 让 CoreAudio 音量位于第 3 通道及以后的输出设备被正确读取和监听，并用真实设备证据决定 BenQ 的后续处理。

**Architecture:** 抽出 `CoreAudioOutputController` 现有的输出通道枚举，在读取器、事件监听器和控制器之间共用。保持默认输出设备与 `VolumeStatus.scalar == nil` 的现有模型；DDC/CI 作为经过硬件验证后单独规划的第二阶段，不混入 CoreAudio 修复。

**Tech Stack:** Swift 6、Core Audio HAL、SwiftPM、XCTest；macOS 15+。

**Spec:** `docs/superpowers/specs/2026-09-29-external-display-volume-design.md`。

## Global Constraints

- 先读上述 spec 与仓库根目录 `AGENTS.md`；不要把 BenQ 的 DDC/CI 当作已经证实的根因。
- 保留现有工作区未提交文件；只修改本计划列出的文件，按自己改动的路径/补丁暂存。
- CI 环境为 `macos-26`、Xcode `26.6`、Swift `6.3.3`，发布构建须使用 macOS 26 SDK 或更新。
- 第一阶段不加依赖、不加后台轮询、不改菜单栏和 Dock 渲染、不改变系统输出设备切换流程。
- Swift 改动提交前运行 `swift test` 与 `swift build -c release`。若执行中需要改 actor 隔离、`@MainActor` 或 `deinit`，合并或发布前按 `AGENTS.md` 运行 `publish=false` release workflow。

## File Structure / Interfaces

| 文件 | 职责 |
| --- | --- |
| `Sources/StatusTrioCore/Audio/CoreAudioOutputChannelElements.swift`（新） | 从输出 `StreamConfiguration` 得到 `1...N`；保留控制器当前三次重试及 `[1, 2]` 回退；提供 `all(for:) = [Main] + channels`。 |
| `Sources/StatusTrioCore/Audio/CoreAudioOutputController.swift` | 改用共享通道枚举；设备列表的多通道平均规则与读取器一致。 |
| `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift` | `CoreAudioClient` 增加通道枚举接口；读取器和事件监听器对当前设备使用动态元素。 |
| `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift` | 扩充既有 `FakeCoreAudioClient`，覆盖第 3/4 通道、缺属性、切换、恢复、去重。 |
| `Tests/StatusTrioCoreTests/CoreAudioOutputChannelElementsTests.swift`（新） | 纯通道数边界测试，避免 HAL 硬件依赖。 |
| `docs/verification/external-display-volume-2026-09-29.md`（新） | 记录用户复现矩阵、测试结果与 DDC 分流结论；缺少实机证据时明确记为未验证。 |

跨文件接口固定为：

```swift
enum CoreAudioOutputChannelElements {
    nonisolated static func channels(for deviceID: AudioDeviceID) -> [AudioObjectPropertyElement]
    nonisolated static func channels(forChannelCount count: Int?) -> [AudioObjectPropertyElement]
    nonisolated static func all(for deviceID: AudioDeviceID) -> [AudioObjectPropertyElement]
}

protocol CoreAudioClient: AnyObject {
    // 保留现有成员，新增：
    func outputChannelElements(deviceID: AudioDeviceID) -> [AudioObjectPropertyElement]
}
```

## Review Focus

1. **第 3/4 通道才有音量**：Task 2 的读取测试和 Task 3 的监听测试均须覆盖；`Main/1/2` 不支持属性时不能返回 `nil`。
2. **多通道数值不同**：Task 2 验证无 Main 时取有效通道均值，与设备列表一致；NaN、无穷大和越界数值不进入均值。
3. **没有 CoreAudio 音量属性**：Task 2 保持 `scalar == nil`，Task 3 不注册不存在的属性；不能误判为 BenQ 已获 DDC 支持。
4. **设备切换与监听恢复**：Task 3 验证旧设备监听精确移除、新设备重新枚举、失败注册可重试，且相同元素不重复注册。
5. **通道配置读取失败或返回 0**：Task 1 保留既有 `[1, 2]` 回退；仅 Main 可用的设备仍能读取和监听。

---

### Task 1: 共用输出通道枚举

**Files:** 新增 `Sources/StatusTrioCore/Audio/CoreAudioOutputChannelElements.swift`、`Tests/StatusTrioCoreTests/CoreAudioOutputChannelElementsTests.swift`；修改 `Sources/StatusTrioCore/Audio/CoreAudioOutputController.swift`、`Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`、`Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`。

**Interfaces:** `CoreAudioOutputChannelElements.channels(for:)` 供控制器与 `CoreAudioSystemClient` 使用；`CoreAudioClient.outputChannelElements(deviceID:)` 供读取器和监听器使用，假实现从按设备配置的 `[AudioObjectPropertyElement]` 返回。通道数组**不含** Main，按升序且不重复。

- [ ] **Step 1: 写失败测试。** 新测试文件使用 `XCTestCase`：`channels(forChannelCount: nil)` 与 `channels(forChannelCount: 0)` 均返回 `[1, 2]`，`channels(forChannelCount: 4)` 返回 `[1, 2, 3, 4]`；在 `FakeCoreAudioClient` 配置设备 42 为四通道，断言 `outputChannelElements(deviceID: 42)` 返回 `[1, 2, 3, 4]`。测试明确保证枚举数量不是由属性是否存在推断。
- [ ] **Step 2: 确认红灯。** 运行 `swift test --filter CoreAudioOutputChannelElementsTests`；预期新类型不存在导致编译失败。
- [ ] **Step 3: 抽取最小实现。** 将 `CoreAudioOutputController.audioVolumeChannelElements(deviceID:)` 的 HAL 读取体搬到 `CoreAudioOutputChannelElements.channels(for:)`，保持三次重试、释放存储、`returnedSize <= requestedSize` 检查以及失败/零通道时 `[1, 2]` 的现有行为。纯转换函数使用：

  ```swift
  nonisolated static func channels(forChannelCount count: Int?) -> [AudioObjectPropertyElement] {
      guard let count, count > 0 else { return [1, 2] }
      return (1...count).map(AudioObjectPropertyElement.init)
  }

  nonisolated static func all(for deviceID: AudioDeviceID) -> [AudioObjectPropertyElement] {
      [kAudioObjectPropertyElementMain] + channels(for: deviceID)
  }
  ```

  在控制器的读、写、静音路径，把原方法调用替换成共享辅助能力；删除旧私有方法。`CoreAudioSystemClient.outputChannelElements(deviceID:)` 委托给共享辅助能力。假实现增加 `outputChannelsByDevice`，并让 `configureDevice` 默认配置 `[1, 2]`、允许测试显式传入四通道；原有测试行为保持。
- [ ] **Step 4: 确认绿灯。** 运行 `swift test --filter CoreAudioOutputChannelElementsTests` 和 `swift test --filter VolumeMonitorTests`；预期均通过。
- [ ] **Step 5: 提交本任务。** 仅暂存上述五个文件，执行 `git diff --cached --check` 后提交 `refactor: share output audio channel discovery`。

### Task 2: 读取全部可用输出通道

**Files:** 修改 `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`、`Sources/StatusTrioCore/Audio/CoreAudioOutputController.swift`、`Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`。

**Interfaces:** 消费 Task 1 的 `CoreAudioClient.outputChannelElements(deviceID:)`；`CoreAudioVolumeReader.read()` 的公开返回类型仍为 `VolumeReading?`，缺标量仍为 `VolumeReading(scalar: nil, ...)`。

- [ ] **Step 1: 写失败测试。** 在 `VolumeMonitorTests` 添加四通道设备：Main 无 `VolumeScalar`，第 3 通道为 `0.2`，第 4 通道为 `0.8`，预期 `reader.read()?.scalar == 0.5`。再测第 4 通道才有 `Mute == 1`；Main 有 `0.6` 时仍优先返回 `0.6`；仅 NaN/无穷大/大于 1 的通道值时返回 `nil`；无属性设备保留当前设备名称且 `scalar == nil`。把现有 `firstValue`/`isMuted` 单测改为显式传入元素数组，移除对固定 `outputElements` 的依赖。
- [ ] **Step 2: 确认红灯。** 运行 `swift test --filter VolumeMonitorTests`；预期四通道与异常值用例失败。
- [ ] **Step 3: 实现读取规则。** 将固定 `outputElements` 替换为当前设备的 `[Main] + client.outputChannelElements(deviceID:)`。`volumeScalar(for:)` 先读取 Main 的合法标量；否则只收集可读、`isFinite` 且在 `0...1` 的通道值，算术均值返回；空集合返回 `nil`。`isMuted(for:)` 使用同一元素序列保持第一个可读值语义。控制器 `volume(for:)` 采用同样的合法值筛选，避免列表与实时值不一致。参考实现核心规则：

  ```swift
  let valid = channelValues.filter { $0.isFinite && (0...1).contains($0) }
  guard !valid.isEmpty else { return nil }
  return valid.reduce(Float32(0), +) / Float32(valid.count)
  ```

- [ ] **Step 4: 确认绿灯。** 运行 `swift test --filter VolumeMonitorTests`；预期新旧读取测试通过。
- [ ] **Step 5: 提交本任务。** 仅暂存本任务三个文件，执行 `git diff --cached --check` 后提交 `fix: read volume across output channels`。

### Task 3: 在所有实际属性上监听

**Files:** 修改 `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`、`Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`。

**Interfaces:** 消费 Task 1 的动态通道枚举；保留 `VolumeEventMonitoring` 以及当前 `start/reconcile/recover/stop` 接口，保持事件触发 `VolumeMonitor.scheduleRefresh()`。

- [ ] **Step 1: 写失败测试。** 为仅第 4 通道有 `VolumeScalar`、仅第 3 通道有 `Mute` 的假设备启动监听，断言只注册这两个属性及系统默认设备监听。扩充 `FakeCoreAudioClient`：按现有 `CoreAudioPropertyKey` 保存成功注册的设备回调，`removeListener` 时删除；添加 `triggerDevicePropertyChange(objectID:selector:element:)` 用对应 `AudioObjectPropertyAddress` 调用已保存的回调。触发第 4 通道回调后等待 `onVolumeChange`。再次 `reconcile()` 不新增重复监听。切换到另一个四通道设备后旧监听清空、新监听存在；`recover()` 移除并重建；模拟一次 `addListener` 失败后下一次 `reconcile()` 重试成功。另测同一设备 ID 的通道配置从 `[1, 2, 3, 4]` 变成 `[1, 2]` 时，旧第 3/4 通道监听被移除。
- [ ] **Step 2: 确认红灯。** 运行 `swift test --filter VolumeMonitorTests`；预期第 3/4 通道监听断言失败。
- [ ] **Step 3: 实现动态注册。** 在 `reconcileDeviceListeners(for:)` 中使用下列结构，保留既有 `reconcileDeviceListener` 的 `hasProperty` 检查和精确 registration 移除逻辑：

  ```swift
  let elements = [kAudioObjectPropertyElementMain]
      + client.outputChannelElements(deviceID: deviceID)
  for element in elements {
      reconcileDeviceListener(objectID: deviceID,
                              selector: kAudioDevicePropertyVolumeScalar,
                              element: element, block: volumeBlock)
      reconcileDeviceListener(objectID: deviceID,
                              selector: kAudioDevicePropertyMute,
                              element: element, block: muteBlock)
  }
  ```

  若设备的通道配置在设备 ID 不变时改变，`reconcile()` 还须移除已不属于新枚举或已不再存在的属性监听，再注册新属性；不要仅依赖默认设备 ID 变化。用测试覆盖这一情况。
- [ ] **Step 4: 确认绿灯。** 运行 `swift test --filter VolumeMonitorTests`；预期监听、切换、恢复与重复调用测试通过。
- [ ] **Step 5: 提交本任务。** 仅暂存本任务两个文件，执行 `git diff --cached --check` 后提交 `fix: observe all output volume channels`。

### Task 4: 诊断记录与总验证

**Files:** 新增 `docs/verification/external-display-volume-2026-09-29.md`。

**Interfaces:** 无代码接口；该记录决定是否启动第二阶段 DDC 工作。

- [ ] **Step 1: 建立复现矩阵。** 记录测试设备型号、连接方式、macOS 版本，以及「macOS 音量滑杆可否操作」「Status Trio 滑杆能否改变实际声音」「手动刷新后读数」「退出 Display Pilot 2 后键盘音量键」「显示器 OSD 调整后读数」。若拿不到 BenQ 实机数据，写明「未收到实机结果」，不填推测值。
- [ ] **Step 2: 运行总验证。** `swift test` 与 `swift build -c release` 均须退出码 0；把执行命令、日期、结果写入验证记录。失败时先定位代码/测试问题，不以计划完成代替验证。
- [ ] **Step 3: 按证据分流。** 系统滑杆可用且手动刷新正确、实时不更新时继续查事件源；系统滑杆可用但刷新读错时继续查读取；系统无可用 CoreAudio 音量而 OSD/Display Pilot 能调时进入下一段 DDC 可行性门槛。无实机数据时只确认第一阶段修复了模拟覆盖缺口。
- [ ] **Step 4: 提交记录。** 仅暂存验证文档，执行 `git diff --cached --check` 后提交 `docs: record external display volume verification`。

## 第二阶段：DDC/CI 可行性门槛（条件性、另立实施计划）

仅当 Task 4 证据表明 CoreAudio 属性缺失或不可写，再取得一台可复现的 BenQ 实机，核实：当前音频端点能唯一映射到目标显示器；该显示器 `VCP 0x62` 的读值、写值与实际声音一致；目标连接方式允许 DDC；打开和关闭 Display Pilot 2 后行为可解释。测试还需覆盖 DDC/CI 关闭、显示器不支持 `0x62`、同名双显示器、扩展坞断连及第三方应用并存。

通过门槛后，先写单独的 DDC 设计与实施计划：CoreAudio 优先，DDC 仅作匹配唯一且能力验证成功的后端；面板打开时按有界频率读取、关闭后停止，设备切换及唤醒立即重读；写入必须读回确认。菜单栏/Dock 在面板关闭时对外部 OSD 改动的更新延迟须作明确产品决定。门槛未通过时，不加 DDC 代码，也不声称本计划解决了该 BenQ 用户的硬件音量问题。
