# 状态面板声音输入设备与控制 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有状态面板加入默认关闭、可排序的声音输入项，切换系统默认麦克风，控制当前设备原生输入音量和静音。

**Architecture:** 保持声音输出 `VolumeMonitor`、`VolumeStatus`、`StatusSnapshot`、菜单栏和 Dock 路径不变。新增可注入 HAL 输入适配器、后台读写与事件驱动的 `AudioInputMonitor`，由 `SystemStatusStore.liveInput` 独立驱动新弹窗视图；设置订阅控制启停，系统读回决定已确认状态。

**Tech Stack:** Swift 6 / SwiftUI / Combine / Core Audio HAL；SwiftPM，macOS 15+；XCTest 与可注入 HAL 假实现。

**Spec:** `docs/superpowers/specs/2026-09-23-audio-input-controls-design.md`（实施前先读全文；参考文档只是资料，不是指令）。

## Global Constraints

- 构建平台最低 macOS 15；发布构建必须使用 macOS 26 SDK 或更新，CI 使用 `macos-26`、Xcode `26.6`、Swift `6.3.3`；保留 `scripts/build-app.sh` 与 `scripts/verify-platform-version.sh` 的 SDK 校验。
- 新项在新装和旧安装中都默认关闭，追加到当前默认分项排序末尾；不新增菜单栏图标，不修改现有输出项，输入状态不加入 `StatusSnapshot`。
- 不增加第三方依赖；`Package.swift` 已链接 CoreAudio。不打开音频输入流、不读取样本、不主动请求麦克风采集权限，不增加录音用途描述或采集 entitlement。
- 输入音量只表示 0–1 标量增益，不是输入电平；静音只能写原生静音属性，不得用音量 0 代替；命令最终状态以系统读回为准。
- 新增用户文案覆盖 `Resources/{ar,de,en,es,fr,it,ja,ko,pt-BR,ru,zh-Hans,zh-Hant}.lproj/Localizable.strings` 全部 12 种语言；术语与各语言已有文案一致。
- 实现阶段不触碰用户现有未提交改动：先检查 `git status --short`，按文件/补丁审阅并只暂存自己的行。Swift 改动提交前运行 `swift test` 和 `swift build -c release`；合并/发布前跑 `publish=false` release workflow 并记录每次失败的 run ID、阶段、原因、修复及复验到 `docs/swift-ci-compatibility.md`。

## Review Focus

以下五项是设计之外尤其容易漏掉的输入与时序；对应测试分别落在任务 2、3、4、4、6。

1. 同名设备或 UID 缺失：按运行时 ID 区分本次列表与命令；重新枚举不得按名称误选，也不持久化设备选择。
2. 多通道一个通道报告 NaN/无属性/不可写：不能计算出“0%”或允许部分写入；缺能力时单独禁用对应控件。
3. 拔出设备后旧 HAL 监听回调迟到：旧监听不再驱动视图或对已撤销设备执行读写。
4. 写入超时后用户选择另一设备：不能把前一设备的晚到读回或音量草稿应用到新设备；单写者不得并发执行未完成的写入。
5. 设备名为空、名称重复或超长：列表仍可辨认、可访问，长名称不会挤掉齿轮/控制行，当前项的无障碍标记准确。

---

## File Structure / Interfaces

现有代码基点：`SettingsStore.sanitizedPopupSectionOrder` 自动补 `PopupSection.allCases`；`PopoverSectionView` 的排序列表自动显示所有分项；`StatusPopoverView.popupSection(_:)` 显式 switch；`AppEnvironment.makeStore` 构造 `SystemStatusStore`；`SystemStatusStore` 控制弹窗生命周期；`VolumeMonitor`/`AudioStatusReader` 是**输出**链路。修改现有测试时先看用户当前未提交差异，不重置/覆盖。

| 文件 | 单一职责 |
| --- | --- |
| `Sources/StatusTrioCore/Models/PopupSection.swift`, `Settings/SettingsStore.swift` | 增加 `.audioInput`，沿用已存储的分项设置迁移与排序，默认启用集合不增加此项。 |
| `Sources/StatusTrioCore/Audio/AudioInputStatus.swift`（新） | `AudioInputDevice(id: AudioDeviceID, uid: String?, name: String?)`、`AudioInputMuteState { unmuted, muted, partial }`、`AudioInputStatus`、`AudioInputError`，无 UI/副作用。 |
| `Sources/StatusTrioCore/Audio/AudioInputHardware.swift`（新） | HAL 高层协议、事件/监听句柄、同步 `read(includeDevices:)` / `selectDefault` / `setScalar` / `setMuted`；供后台 worker 和假实现共用。 |
| `Sources/StatusTrioCore/Audio/CoreAudioInputHardware.swift`（新） | Core Audio 属性读取/可写检测、设备过滤、读写复核、属性监听注册与精确移除；低层可注入 `AudioInputPropertyClient` 供硬件无关测试。 |
| `Sources/StatusTrioCore/Monitoring/AudioInputMonitor.swift`（新） | 后台单读/单写、事件合并、开启/展示/停止生命周期、过期读丢弃、命令回读、约 4 秒错误；对外主 actor 协议 `AudioInputMonitoring`。 |
| `Sources/StatusTrioCore/App/AppEnvironment.swift`, `Store/SystemStatusStore.swift` | 注入监控、订阅设置开关、暴露 `liveInput` 和输入命令、面板与唤醒恢复，不污染输出快照。 |
| `Sources/StatusTrioCore/UI/AudioInputControlsView.swift`（新）, `UI/StatusPopoverView.swift` | 独立展示输入状态/设备列表/反馈；输出 `VolumeControlsView` 不复用也不修改。 |
| `Sources/StatusTrioCore/Localization/LocalizationKey.swift`, `Resources/*.lproj/Localizable.strings` | 新分项及输入控制专用的本地化文案。 |
| `Tests/StatusTrioCoreTests/{SettingsStoreTests,AudioInputHardwareTests,AudioInputMonitorTests,SystemStatusStoreTests,AudioInputPresentationTests,LocalizationParityTests}.swift` | 设置迁移、HAL 能力/监听、异步生命周期、集成、视图呈现模型与语言覆盖。新测试文件按对应任务创建；原有测试仅做必要更新。 |

跨层约定（下述任务中的测试与实现均使用相同名称）：

```swift
// AudioInputStatus.swift; import CoreAudio for AudioDeviceID / OSStatus.
struct AudioInputDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String?
    let name: String?
}
enum AudioInputMuteState: Equatable, Sendable { case unmuted, muted, partial }
enum AudioInputError: Equatable, Sendable {
    case refreshFailed, switchFailed, volumeFailed, muteFailed, timedOut
}
enum AudioInputHardwareError: Error, Equatable, Sendable {
    case unsupported, unavailable, invalidValue, osStatus(OSStatus)
}
struct AudioInputStatus: Equatable, Sendable {
    var devices: [AudioInputDevice]
    var defaultDeviceID: AudioDeviceID?
    var deviceName: String?
    var scalar: Double?
    var canSetVolume: Bool
    var muteState: AudioInputMuteState?
    var canSetMute: Bool
    var isRefreshing: Bool
    var isBusy: Bool
    var error: AudioInputError?
    static let empty = Self(
        devices: [], defaultDeviceID: nil, deviceName: nil, scalar: nil,
        canSetVolume: false, muteState: nil, canSetMute: false,
        isRefreshing: false, isBusy: false, error: nil
    )
}
// CoreAudioInputHardware.swift — task 2 baseline; task 3 extends with control methods.
protocol AudioInputPropertyClient: Sendable {
    func devices() throws -> [AudioDeviceID]
    func defaultInput() throws -> AudioDeviceID?
    func isDevice(_ id: AudioDeviceID) -> Bool
    func isAlive(_ id: AudioDeviceID) -> Bool?
    func isHidden(_ id: AudioDeviceID) -> Bool?
    func canBeDefaultInput(_ id: AudioDeviceID) -> Bool?
    func inputChannels(_ id: AudioDeviceID) -> Int
    func name(_ id: AudioDeviceID) -> String?
    func uid(_ id: AudioDeviceID) -> String?
}
// AudioInputHardware.swift — nil devices means no enumeration requested.
struct AudioInputReading: Sendable {
    let devices: [AudioInputDevice]?
    let defaultDeviceID: AudioDeviceID?
    let deviceName: String?
    let scalar: Double?
    let canSetVolume: Bool
    let muteState: AudioInputMuteState?
    let canSetMute: Bool
}
enum AudioInputEvent: Sendable { case devicesChanged, defaultChanged, controlsChanged }
protocol AudioInputHardware: Sendable {
    func read(includeDevices: Bool) throws -> AudioInputReading
    func selectDefault(_ id: AudioDeviceID) throws
    func setScalar(_ scalar: Double, on id: AudioDeviceID) throws
    func setMuted(_ muted: Bool, on id: AudioDeviceID) throws
    func observe(_ notify: @escaping @Sendable (AudioInputEvent) -> Void) throws -> any AudioInputObservation
}
protocol AudioInputObservation: Sendable {
    func setCurrentDevice(_ id: AudioDeviceID?)
    func stop()
}
@MainActor protocol AudioInputMonitoring: AnyObject {
    var updates: AsyncStream<AudioInputStatus> { get }
    func setEnabled(_ enabled: Bool)
    func setVisible(_ visible: Bool)
    func recover()
    func select(_ id: AudioDeviceID)
    func setScalar(_ value: Double)
    func toggleMute()
    func stop()
}
```

HAL 读写与监听不能跑在主 actor 上：监控器使用专用串行 `DispatchQueue(qos: .utility)`，仅将代次匹配的结果派发回主 actor；HAL 与假实现跨队列时必须采用真实同步保护或受队列独占的 `@unchecked Sendable` 并注明不变量，绝不靠 `MainActor.assumeIsolated` 绕过检查。系统属性监听用 block 形式并保存原始 `(objectID,address,queue,block)`，移除时用相同实例。`read(includeDevices: false)` **不枚举**；回调只触发刷新，不在回调里直接进行昂贵读取。定时器只负责命令超时/错误消失，不做输入电平轮询。

### Task 1: 设置默认关闭、旧数据迁移和排序

**Files:** Modify `Sources/StatusTrioCore/Models/PopupSection.swift`, `Sources/StatusTrioCore/Settings/SettingsStore.swift`（`defaultEnabledPopupSections` / sanitizers）；Test `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`。

**Interfaces:** Consumes `PopupSection`/`SettingsStore` 既有 API；Produces `PopupSection.audioInput`，现有 `setPopupSection(_:enabled:)`、`visiblePopupSections` 不变。

- [ ] **Step 1: 先写失败测试。** 在现有分项测试附近加入如下断言，并把所有既有测试的 `popupSectionOrder` 期望数组末尾追加 `.audioInput`（不改其余顺序），补 `PopupSection.audioInput` 的标题键/图标断言；默认可见项仍不增加：

```swift
func testInputSectionAppendsToOldOrderButDefaultsOff() {
    let freshSuite = makeSuite()
    defer { clear(freshSuite) }
    XCTAssertFalse(SettingsStore(defaults: freshSuite.defaults).enabledPopupSections.contains(.audioInput))
    let suite = makeSuite()
    defer { clear(suite) }
    suite.defaults.set(["volume", "battery"], forKey: SettingsStore.popupSectionOrderDefaultsKey)
    suite.defaults.set(["volume", "battery"], forKey: SettingsStore.enabledPopupSectionsDefaultsKey)
    let store = SettingsStore(defaults: suite.defaults)
    XCTAssertEqual(store.popupSectionOrder, [.volume, .battery, .network, .bluetooth, .audioInput])
    XCTAssertFalse(store.enabledPopupSections.contains(.audioInput))
    store.setPopupSection(.audioInput, enabled: true)
    XCTAssertTrue(SettingsStore(defaults: suite.defaults).visiblePopupSections.contains(.audioInput))
}
```

- [ ] **Step 2: 运行红灯。** `swift test --filter SettingsStoreTests`；预期 `.audioInput` 未定义/旧数组期望不匹配。
- [ ] **Step 3: 实现最小改动。** 在 `PopupSection` 的 `allCases` 最后加 `.audioInput`，补全 `titleKey` (`.settingsPopupOrderAudioInput`) 与 `systemImage` (`"mic"`)；保持 `defaultEnabledPopupSections = [.battery, .network, .volume]` 原样。当前 `sanitizedPopupSectionOrder` 会自动补全，`sanitizedEnabledPopupSections(nil)` 保持默认集合；本任务同时在 12 个语言表添加新 title key 的准确译文，保持每次提交能通过 `LocalizationParityTests`；任务 6 再补齐其余输入 UI 文案。

```swift
case audioInput
// titleKey switch: case .audioInput: .settingsPopupOrderAudioInput
// systemImage switch: case .audioInput: "mic"
// LocalizationKey: case settingsPopupOrderAudioInput = "settings.popup.order.audioInput"
```

- [ ] **Step 4: 运行绿灯。** `swift test --filter SettingsStoreTests && swift test --filter LocalizationParityTests && swift test && swift build -c release`；期望迁移、启停持久化、既有排序和语言键对齐测试全部通过。
- [ ] **Step 5: 只暂存上述文件后提交。** `git add Sources/StatusTrioCore/Models/PopupSection.swift && git add -p Sources/StatusTrioCore/Localization/LocalizationKey.swift Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings Sources/StatusTrioCore/Settings/SettingsStore.swift Tests/StatusTrioCoreTests/SettingsStoreTests.swift && git diff --cached && git commit -m "feat(settings): add disabled audio input section"`。若用户已有差异交错，先把自己的差异单独形成补丁，勿将其余行纳入提交。

### Task 2: 设备发现、筛选与系统读回模型

**Files:** Create `Sources/StatusTrioCore/Audio/AudioInputStatus.swift`, `AudioInputHardware.swift`, `CoreAudioInputHardware.swift`, `Tests/StatusTrioCoreTests/AudioInputHardwareTests.swift`。

**Interfaces:** Produces `AudioInputDevice`、`AudioInputStatus`、`AudioInputReading`、`AudioInputHardwareError`；`CoreAudioInputHardware(client: any AudioInputPropertyClient)` 对底层的 `devices()/defaultInput()/read...` 做可注入封装。上方跨层代码展示**任务 4 完成后的最终协议**：本任务的 `AudioInputHardware` 暂时只有 `read(includeDevices:)`，任务 3 增加三种写入命令，任务 4 再加入 `observe`/`AudioInputObservation`/`AudioInputEvent`。按任务增量扩展，避免空命令和空监听桩，且每次提交可编译。

- [ ] **Step 1: 为 Core Audio 底层属性客户端造假并写红灯。** 明确底层读属性接口包含 `devices()`, `defaultInput()`, `isAlive(_:)`, `isHidden(_:)`, `canBeDefaultInput(_:)`, `inputChannels(_:)`, `name(_:)`, `uid(_:)`；假客户端固定返回 ID `11...15`：11 有效、12 隐藏、13 没有输入通道、14 不可默认、15 同名且 UID 为 nil。测试：

```swift
let reading = try hardware.read(includeDevices: true)
XCTAssertEqual(reading.devices?.map(\.id), [11, 15])
XCTAssertEqual(reading.defaultDeviceID, 11)
XCTAssertEqual(try hardware.read(includeDevices: false).devices, nil)
XCTAssertNotEqual(reading.devices?[0].id, reading.devices?[1].id)
```

同时测试无默认但有可选设备、全空、默认 ID 无效、驱动返回空名字/重复名字；设备不持久化，不以名字代替 ID。设备 ID 重分配而 UID 不变时，更新行 ID 并从系统默认输入重新确认选中项，不向旧 ID 发送命令。
- [ ] **Step 2: 运行红灯。** `swift test --filter AudioInputHardwareTests`；预期类型或实现缺失。
- [ ] **Step 3: 实现读取。** `CoreAudioInputHardware` 的 CoreAudio 客户端读 `kAudioHardwarePropertyDevices` / `kAudioHardwarePropertyDefaultInputDevice`（系统对象全局作用域），用 `kAudioObjectPropertyClass`、`kAudioDevicePropertyDeviceIsAlive`、`kAudioDevicePropertyIsHidden`、`kAudioDevicePropertyDeviceCanBeDefaultDevice`（输入作用域）及输入 stream configuration 的非零通道筛选；读取 `kAudioObjectPropertyName`、`kAudioDevicePropertyDeviceUID`。`kAudioObjectUnknown`、非 device class、失败/无效布尔或未报告输入通道时排除；默认设备的名称与控制值仅在有效读回时设置。把实际 `AudioObjectGetPropertyDataSize`/`AudioObjectGetPropertyData` 的长度和返回码一起校验。UID 缺失仅在当前快照用 ID，绝不写设置。

```swift
let defaultID = try client.defaultInput()
let candidateIDs = includeDevices ? try client.devices() : defaultID.map { [$0] } ?? []
let eligible = candidateIDs.filter { id in
    id != kAudioObjectUnknown && client.isDevice(id) && client.isAlive(id) == true
        && client.isHidden(id) == false
        && client.canBeDefaultInput(id) == true
        && client.inputChannels(id) > 0
}
let selected = defaultID.flatMap { eligible.contains($0) ? $0 : nil }
let devices = includeDevices ? eligible.map { AudioInputDevice(id: $0, uid: client.uid($0), name: client.name($0)) } : nil
```

- [ ] **Step 4: 运行绿灯。** `swift test --filter AudioInputHardwareTests && swift test && swift build -c release`；不需要本机麦克风。
- [ ] **Step 5: 只提交任务 2 新文件。** `git add Sources/StatusTrioCore/Audio/AudioInputStatus.swift Sources/StatusTrioCore/Audio/AudioInputHardware.swift Sources/StatusTrioCore/Audio/CoreAudioInputHardware.swift Tests/StatusTrioCoreTests/AudioInputHardwareTests.swift && git diff --cached && git commit -m "feat(audio): add input device inventory"`。

### Task 3: HAL 主元素/多通道音量与原生静音

**Files:** Modify `Sources/StatusTrioCore/Audio/CoreAudioInputHardware.swift`, `AudioInputHardware.swift`, `Tests/StatusTrioCoreTests/AudioInputHardwareTests.swift`。

**Interfaces:** Consumes 任务 2 的 `AudioInputHardware.read(includeDevices:)`；本任务新增 `selectDefault(_:)`、`setScalar(_:on:)`、`setMuted(_:on:)`。`AudioInputPropertyClient` 新增 `hasProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> Bool`、`isSettable(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> Bool`、`readScalar(_ id: AudioDeviceID, _ element: AudioObjectPropertyElement) -> Float32?`、`readMute(_ id: AudioDeviceID, _ element: AudioObjectPropertyElement) -> Bool?`、`writeScalar(_ value: Float32, on id: AudioDeviceID, element: AudioObjectPropertyElement) throws`、`writeMute(_ value: Bool, on id: AudioDeviceID, element: AudioObjectPropertyElement) throws`、`writeDefaultInput(_ id: AudioDeviceID) throws`；音量/静音方法内部固定使用**输入 scope**，不得复用输出 scope。Produces `AudioInputReading.scalar/canSetVolume/muteState/canSetMute`。元素标识为 `AudioObjectPropertyElement`，主元素 `kAudioObjectPropertyElementMain` 优先。

- [ ] **Step 1: 写能力矩阵与写入失败测试。** 构造可注入属性假的 main read/write、仅全部通道可读写、单通道缺属性、NaN/越界、不同 mute 位与第二通道写失败；验证：

```swift
XCTAssertEqual(try twoChannels.read(includeDevices: false).scalar, 0.5) // [0.2, 0.8]
XCTAssertEqual(try mixedMute.read(includeDevices: false).muteState, .partial)
XCTAssertFalse(try missingChannel.read(includeDevices: false).canSetVolume)
XCTAssertNil(try invalidScalar.read(includeDevices: false).scalar)
XCTAssertThrowsError(try partiallyFailing.setMuted(true, on: 11))
XCTAssertEqual(partiallyFailing.writtenMuteElements, [1, 2]) // 第二次抛错，调用者负责重新读回
```

加测试：主元素可读但不可写时回退全部有效通道；输入音量更改不调用 `writeMute`，静音更改不调用 `writeScalar`；设备/能力在命令前消失时不写；默认输入写失败抛错且不改本地默认值。
- [ ] **Step 2: 运行红灯。** `swift test --filter AudioInputHardwareTests`；预期能力矩阵/写回断言失败。
- [ ] **Step 3: 实现原子选择规则和尽力写入。** 针对 `kAudioDevicePropertyVolumeScalar`、`kAudioDevicePropertyMute` 输入作用域，先查 `AudioObjectHasProperty`，再以 `AudioObjectIsPropertySettable == noErr && isSettable` 判定可写；主元素同时可读、可写才用它，否则枚举 stream configuration 相关全部通道并要求每通道可读、可写；读不到有效数值就标记不可用。多通道标量取算术均值，写入每个通道同一经过 `isFinite` 检查且限定在 `0...1` 的值；静音不同返回 `.partial`，`toggleMute()` 由监控将 `.muted` 设为 false、其余设为 true；一通道写失败立即抛错，不伪造成功，后续任务 4 读回实际值。命令前再次核对设备有效性、输入能力；不使用输出 scope。

```swift
private func writableElements(
    for id: AudioDeviceID, selector: AudioObjectPropertySelector
) throws -> [AudioObjectPropertyElement] {
    guard client.isDevice(id), client.isAlive(id) == true,
          client.canBeDefaultInput(id) == true else {
        throw AudioInputHardwareError.unavailable
    }
    let count = client.inputChannels(id)
    let channels: [AudioObjectPropertyElement] = count > 0
        ? (1...count).map { AudioObjectPropertyElement($0) } : []
    func usable(_ element: AudioObjectPropertyElement) -> Bool {
        guard client.hasProperty(id, selector, element),
              client.isSettable(id, selector, element) else { return false }
        if selector == kAudioDevicePropertyVolumeScalar {
            return client.readScalar(id, element).map { $0.isFinite && (0...1).contains($0) } == true
        }
        return client.readMute(id, element) != nil
    }
    if usable(kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
    guard !channels.isEmpty, channels.allSatisfy(usable) else {
        throw AudioInputHardwareError.unsupported
    }
    return channels
}
func setScalar(_ scalar: Double, on id: AudioDeviceID) throws {
    guard scalar.isFinite else { throw AudioInputHardwareError.invalidValue }
    for element in try writableElements(for: id, selector: kAudioDevicePropertyVolumeScalar) {
        try client.writeScalar(Float32(min(max(scalar, 0), 1)), on: id, element: element)
    }
}
func setMuted(_ muted: Bool, on id: AudioDeviceID) throws {
    for element in try writableElements(for: id, selector: kAudioDevicePropertyMute) {
        try client.writeMute(muted, on: id, element: element)
    }
}
```

- [ ] **Step 4: 运行绿灯。** `swift test --filter AudioInputHardwareTests && swift test && swift build -c release`；部分写失败后的再次 `read` 应返回设备真实残留状态。
- [ ] **Step 5: 只提交任务 3 文件。** `git add Sources/StatusTrioCore/Audio/CoreAudioInputHardware.swift Sources/StatusTrioCore/Audio/AudioInputHardware.swift Tests/StatusTrioCoreTests/AudioInputHardwareTests.swift && git diff --cached && git commit -m "feat(audio): control native input gain and mute"`。

### Task 4: 独立监控生命周期、事件、并发和读回

**Files:** Create `Sources/StatusTrioCore/Monitoring/AudioInputMonitor.swift`, `Tests/StatusTrioCoreTests/AudioInputMonitorTests.swift`；Modify `Sources/StatusTrioCore/Audio/CoreAudioInputHardware.swift`（事件监听），`AudioInputHardware.swift`（观察句柄）。

**Interfaces:** Consumes 任务 3 的 `AudioInputHardware` 与上述模型；本任务新增 `AudioInputEvent`、`AudioInputObservation`、`AudioInputHardware.observe(_:)`；Produces `AudioInputMonitoring`，主 actor `updates: AsyncStream<AudioInputStatus>` / `setEnabled` / `setVisible` / `recover` / 命令 / `stop`。监控构造支持注入 HAL、命令超时、可控 `sleep`，测试用手动闸门完成后台操作。

- [ ] **Step 1: 写 fake HAL 的生命周期/竞态测试。** 假观察句柄计数注册/重绑/移除，假读写用闸门人为推迟；断言默认关闭零观察/零枚举、开启后仅注册全局设备和默认输入事件、面板打开才全量读取；外部默认变化、热插拔重新读回并重绑当前设备；关闭后只标记脏、不枚举；停用后回调无效：

```swift
monitor.setEnabled(false)
monitor.setVisible(true)
XCTAssertEqual(fake.observeCount, 0)
XCTAssertEqual(fake.fullReadCount, 0)
monitor.setEnabled(true)
// 等待 fake 提供的异步通知/expectation，而非固定 sleep
XCTAssertEqual(fake.observeCount, 1)
monitor.setEnabled(false)
fake.emitLate(.controlsChanged)
XCTAssertEqual(fake.fullReadCount, 1) // 停用后的回调不增加计数
```

加测试：重复 `setEnabled(true)` 不重复监听；单设备外部变更更新 mute/scalar；睡眠恢复 `recover()`；旧读取/旧监听晚到丢弃；错误 4 秒后清除且下次动作立即清除；重复拖动保留最新待写值且无并发写；写入失败/超时、读回与目标不符、设备变更后旧完成不更新；`stop()` 后读/写/更新均静默。测试前述 Review Focus 的拔出迟到回调与超时换设备。
- [ ] **Step 2: 运行红灯。** `swift test --filter AudioInputMonitorTests`；预期监控类型不存在。
- [ ] **Step 3: 实现观察和后台 worker。** 全局监听 `kAudioHardwarePropertyDevices` 与 `kAudioHardwarePropertyDefaultInputDevice`；当前有效设备监听输入 scope 的音量/静音（主元素及输入通道；设备切换时先移除旧设备监听，再添加新设备监听）；`stop()` / 停用时移除所有原样保存的 HAL block，代次自增，清空待写。HAL 回调只发事件，监控在后台合并刷新；不让回调访问旧设备。面板隐藏期间只标记待枚举，打开执行完整读并显示 `isRefreshing`；`setVisible(false)` 停止枚举工作，保留启用时的轻量事件观察。命令与读由独立串行 I/O 队列驱动（单写者，单待发送音量目标，约 80ms 合并）；为每次操作记录 `(sessionGeneration, deviceID, readGeneration)`，读回才能确认当前选中/音量/静音；音量读回标量与目标偏差超过 `0.01`、默认设备不同、静音位不符均报本地化失败。命令超时后拒绝同队列的重入写，晚到结果仅做失效标记/重新读实际状态；过期任务不得释放新任务锁。错误经过注入的 4 秒 timer 清除；新动作立即清除。无默认设备时也保留可选列表；不将未知音量填 0。

```swift
@MainActor
func setEnabled(_ enabled: Bool) {
    guard enabled != isEnabled else { return }
    generation &+= 1
    isEnabled = enabled
    if enabled { installObservationAndRefreshIfVisible() }
    else { observation?.stop(); observation = nil; pendingScalar = nil }
}
// 在每个后台 completion 返回主 actor 的入口应用相同的门闩：
guard isEnabled, !isStopped, generation == capturedGeneration,
      readGeneration == capturedReadGeneration else { return }
```

- [ ] **Step 4: 运行绿灯与回归。** `swift test --filter AudioInputMonitorTests && swift test --filter VolumeMonitorTests && swift test && swift build -c release`；预期输入测试通过，输出行为不变。
- [ ] **Step 5: 只提交任务 4 文件。** `git add Sources/StatusTrioCore/Monitoring/AudioInputMonitor.swift Sources/StatusTrioCore/Audio/{AudioInputHardware,CoreAudioInputHardware}.swift Tests/StatusTrioCoreTests/AudioInputMonitorTests.swift && git diff --cached && git commit -m "feat(audio): monitor input changes with confirmed readback"`。

### Task 5: 应用注入、设置开关与弹窗生命周期

**Files:** Modify `Sources/StatusTrioCore/App/AppEnvironment.swift`, `Sources/StatusTrioCore/Store/SystemStatusStore.swift`, `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift`。

**Interfaces:** Consumes `AudioInputMonitoring`，`SettingsStore.$enabledPopupSections`；Produces `SystemStatusStore.liveInput: AudioInputStatus`、`bindInputSettings(_:)`、`selectInputDevice(_:)`、`setInputScalar(_:)`、`toggleInputMute()`。`AppEnvironment.makeStore(..., inputMonitor: (any AudioInputMonitoring)? = nil, ...)` 测试可不注入，`live()` 注入真实监控。保留 `StatusSnapshot` 与输出 `VolumeControlling` API 不变。

- [ ] **Step 1: 写集成红灯。** 使用伪 `AudioInputMonitoring` 统计 `setEnabled/setVisible/recover/stop`，发 `updates`；测试旧设置默认不启动、开启时接通、弹窗显示与关闭切换详情读取、设置关闭立刻停、唤醒恢复、store 停止后不转发回调：

```swift
let settings = SettingsStore(defaults: makeSuite().defaults)
let input = FakeAudioInputMonitor()
let store = makeStore(inputMonitor: input)
store.bindInputSettings(settings)
store.start()
XCTAssertEqual(input.enableCalls.last, false)
settings.setPopupSection(.audioInput, enabled: true)
XCTAssertEqual(input.enableCalls.last, true)
store.setPopoverVisible(true)
XCTAssertEqual(input.visibleCalls.last, true)
store.stop()
XCTAssertEqual(input.stopCount, 1)
```

同时断言发送输入更新时 `store.liveInput` 变化、`store.snapshot.volume` / `popupSnapshot.volume` / 菜单栏和 Dock 投影保持不变。
- [ ] **Step 2: 运行红灯。** `swift test --filter SystemStatusStoreTests`；预期新签名/状态缺失。
- [ ] **Step 3: 实现最小集成。** 在 `AppEnvironment.live()` 创建 `AudioInputMonitor(hardware: CoreAudioInputHardware())` 注入 store；`start()` 在 `store.start()` 前调用 `store.bindInputSettings(settings)`；`SystemStatusStore` 持有可选 input monitor、`AnyCancellable` 和 update task，订阅 `settings.$enabledPopupSections.map { $0.contains(.audioInput) }.removeDuplicates()`，更新监控启停；若设置在弹窗打开时开启，调用 `setVisible(isPopoverVisible)`；`setPopoverVisible` / `recoverAll` / `stop` 对称传递，关闭/停用后旧回调不得更改 `liveInput`。输入命令只委托输入监控，不调用 `publish(snapshot.replacingVolume:)`。

```swift
func bindInputSettings(_ settings: SettingsStore) {
    inputSettingsCancellable = settings.$enabledPopupSections
        .map { $0.contains(.audioInput) }
        .removeDuplicates()
        .sink { [weak self] enabled in self?.setInputEnabled(enabled) }
}
func selectInputDevice(_ id: AudioDeviceID) { inputMonitor?.select(id) }
func setInputScalar(_ value: Double) { inputMonitor?.setScalar(value) }
func toggleInputMute() { inputMonitor?.toggleMute() }
```

- [ ] **Step 4: 运行绿灯。** `swift test --filter SystemStatusStoreTests && swift test && swift build -c release`；预期零输入负担的默认态与现有输出测试通过。
- [ ] **Step 5: 只暂存自己改动。** `git add -p Sources/StatusTrioCore/App/AppEnvironment.swift Sources/StatusTrioCore/Store/SystemStatusStore.swift Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift && git diff --cached && git commit -m "feat(app): connect opt-in input monitor to popover lifecycle"`。

### Task 6: 输入分项的可用性、无障碍与 12 语言

**Files:** Create `Sources/StatusTrioCore/UI/AudioInputControlsView.swift`, `Tests/StatusTrioCoreTests/AudioInputPresentationTests.swift`；Modify `Sources/StatusTrioCore/UI/StatusPopoverView.swift`, `Localization/LocalizationKey.swift`, all 12 `Resources/*.lproj/Localizable.strings`；Test `Tests/StatusTrioCoreTests/LocalizationParityTests.swift`, `Tests/StatusTrioCoreTests/StatusMenuBuilderTests.swift`（仅受分项 switch 影响时更新）。

**Interfaces:** Consumes `store.liveInput`、`selectInputDevice(_:)`、`setInputScalar(_:)`、`toggleInputMute()`、`openSoundSettings` 与环境 `Localization`；Produces `AudioInputControlsView(status:onSelect:onScalarChange:onToggleMute:onOpenSoundSettings:)`。同文件定义无副作用值模型 `AudioInputPresentation`：`init(status: AudioInputStatus, locale: Locale = .current)`；`static ordered(_ devices: [AudioInputDevice], currentID: AudioDeviceID?, locale: Locale, unknownName: String) -> [AudioInputDevice]`（当前项先排，其余用 `String.compare(_:options:range:locale:)` 按传入 locale 比较，比较相等按 ID 升序）；计算属性 `showsDeviceList: Bool`、`volumeEnabled: Bool`、`muteEnabled: Bool`、`nextMuteValue: Bool`、`volumeAccessibilityValue: String`。后者未知值为 `"—"`，否则以传入 locale 格式化百分比。设备行无障碍标签由视图结合 `Localization` 生成：空名字用 `.audioInputUnknownDevice`，同名/空名追加本次列表的本地化序号，当前项附 `.audioInputCurrent`；测试只断言模型与生成文案，不把系统状态交给 UI 快照决定。

- [ ] **Step 1: 写视图呈现红灯与文案覆盖断言。** 用纯呈现模型构造零设备、无默认但有设备、单设备、双设备同名、缺能力、部分静音、失败与长名称；验证排序、禁用和无障碍内容：

```swift
let rows = AudioInputPresentation.ordered(
    [builtIn, usb], currentID: usb.id,
    locale: Locale(identifier: "zh_CN"), unknownName: "未知输入设备"
)
XCTAssertEqual(rows.map(\.id), [usb.id, builtIn.id])
XCTAssertTrue(AudioInputPresentation(status: noDefaultWithOneDevice).showsDeviceList)
XCTAssertFalse(AudioInputPresentation(status: noVolumeSupport).volumeEnabled)
XCTAssertEqual(AudioInputPresentation(status: partiallyMuted).nextMuteValue, true)
XCTAssertEqual(AudioInputPresentation(status: .empty).volumeAccessibilityValue, "—")
```

`LocalizationParityTests` 中为本功能补一条非空断言（现有测试只对齐键、占位符及防止值等于 key）：

```swift
func testAudioInputTranslationsAreNotEmpty() throws {
    let keys = LocalizationKey.allCases.map(\.rawValue).filter {
        $0.hasPrefix("audioInput.") || $0 == "settings.popup.order.audioInput"
    }
    XCTAssertFalse(keys.isEmpty)
    for language in AppLanguage.allCases {
        let values = Dictionary(uniqueKeysWithValues: try entries(for: language).map { ($0.key, $0.value) })
        for key in keys {
            XCTAssertFalse((values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "\(language.rawValue).lproj: \(key) is empty")
        }
    }
}
```

针对同名项的无障碍值包含“当前”而不是只靠对勾，空名称显示本地化“未知输入设备”并结合位置/ID 区分；面板标题与长名称 `.lineLimit(1)` / `.truncationMode(.middle)`，齿轮固定大小。`LocalizationParityTests` 应确保新增的 `LocalizationKey` 在 12 个表都有非空值，无回退英文/残留 key。
- [ ] **Step 2: 运行红灯。** `swift test --filter AudioInputPresentationTests && swift test --filter LocalizationParityTests`；预期呈现模型不存在/新语言键缺失。
- [ ] **Step 3: 实现视图与文案。** `StatusPopoverView.popupSection(_:)` 增 `.audioInput` 分支，将现有 `openSoundSettings` 传给新视图；上方麦克风标题、默认设备名、齿轮；中部静音按钮与音量 slider；底部设备列表即使一台也展示，点击当前项无写入，点击其他项不会关闭面板；缺默认仍显示可选设备，无设备才显示“无可用输入设备”。`@State` 仅维护拖动草稿，`status.defaultDeviceID` 改变时清除旧草稿并显示新设备读回，禁止乐观修改 `status`。不支持时控件可见但 `.disabled(true)`、`.help(...)`、`.accessibilityHint(...)`；partial 用不混同静音/未静音的图标及文案；失败 banner 由 `status.error` 本地化。添加键：`settings.popup.order.audioInput`、`audioInput.title/noDefault/noDevices/unknownDevice/devicePosition/current/switchTo/volume/mute/unmute/partial/volumeUnavailable/muteUnavailable/openSettings/switchFailed/volumeFailed/muteFailed/refreshFailed/timedOut/refreshing`（`devicePosition` 是 `%d` 格式，12 个语言表保持相同占位符）；百分比通过当前 App `Localization.resolvedLanguage.locale` 格式化，不写死英文。

```swift
case .audioInput:
    AudioInputControlsView(
        status: store.liveInput,
        onSelect: { store.selectInputDevice($0) },
        onScalarChange: { store.setInputScalar($0) },
        onToggleMute: { store.toggleInputMute() },
        onOpenSoundSettings: openSoundSettings
    )
```

- [ ] **Step 4: 运行绿灯与语言检查。** `swift test --filter AudioInputPresentationTests && swift test --filter LocalizationParityTests && swift test --filter StatusMenuBuilderTests && swift test && swift build -c release`；确保各语言与呈现状态通过。
- [ ] **Step 5: 只暂存自己变更。** `git add Sources/StatusTrioCore/UI/AudioInputControlsView.swift Tests/StatusTrioCoreTests/AudioInputPresentationTests.swift && git add -p Sources/StatusTrioCore/UI/StatusPopoverView.swift Sources/StatusTrioCore/Localization/LocalizationKey.swift Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings Tests/StatusTrioCoreTests/LocalizationParityTests.swift Tests/StatusTrioCoreTests/StatusMenuBuilderTests.swift && git diff --cached && git commit -m "feat(ui): show localized audio input controls"`。

### Task 7: 全量验证、实机验收与 CI 预检

**Files:** Create `docs/verification/audio-input-controls-2026-09-23.md`（验证记录）；如 CI 失败 Modify `docs/swift-ci-compatibility.md`。不修改发布文件或开始正式发布。

**Interfaces:** Consumes tasks 1–6 的可运行构建；Produces 可复核的测试/设备矩阵与 CI run ID。

- [ ] **Step 1: 检查变更边界。** 运行 `git status --short && git diff --check && git diff -- Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift Sources/StatusTrioCore/Audio/CoreAudioOutputController.swift`；期望输出链路未改变，检查 `StatusSnapshot` / 菜单栏 / Dock 未加入输入状态，用户原始未提交变更未被覆盖。
- [ ] **Step 2: 本地自动验收。** 运行 `swift test && swift build -c release`；预期 0 exit code；检查 `swift test --filter AudioInput`、`swift test --filter SettingsStoreTests`、`swift test --filter LocalizationParityTests` 覆盖完整矩阵。失败先修复再重新运行，不能把失败标为通过。
- [ ] **Step 3: 本机人工矩阵并落盘。** 使用内建麦克风和一台 USB/蓝牙输入设备完成输入切换、系统“声音 → 输入”双向同步、拔插/睡眠唤醒、外部静音/音量更改、关闭分项后监听和枚举归零、失败提示、无麦克风采集指示/TCC 弹窗；对不支持控制的设备只在真实拿到设备时标“通过”，拿不到记录“未验证”。记录设备型号、macOS 版本、步骤、结果与截图/命令输出位置到验证文档。实机观察不是“零权限”承诺；Ad-hoc 签名限制单独注明。
- [ ] **Step 4: 非发布 CI 预检。** SwiftUI 绑定、`@MainActor` 已变动，先核对最新 GitHub Release、`Support/Info.plist` 和 `release-notes/`，在 shell 设置确定的 `VERSION` / `BUILD`（`BUILD` 必须大于线上已发布的 build）；确认当前 branch 已推送且 `publish=false`：

```bash
test -n "$VERSION" && test -n "$BUILD"
BRANCH=$(git branch --show-current)
SHA=$(git rev-parse HEAD)
test -n "$BRANCH"
DISPATCHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
gh workflow run release.yml --repo lingyired/status-trio --ref "$BRANCH" -f version="$VERSION" -f build="$BUILD" -f publish=false
# 只接受本次派发后、当前 SHA 的唯一 workflow_dispatch run；列表延迟出现则最多等 60 秒。
RUN_IDS=""
for attempt in {1..20}; do
  RUN_IDS=$(gh run list --repo lingyired/status-trio --workflow release.yml \
    --event workflow_dispatch --branch "$BRANCH" --commit "$SHA" --limit 20 \
    --json databaseId,createdAt,headSha | jq -r \
    --arg at "$DISPATCHED_AT" --arg sha "$SHA" \
    '[.[] | select(.createdAt >= $at and .headSha == $sha) | .databaseId] | join(" ")')
  test -n "$RUN_IDS" && break
  sleep 3
done
[[ "$RUN_IDS" =~ ^[0-9]+$ ]] || { echo "No unique dispatch run; verify manually before watching"; exit 1; }
RUN_ID="$RUN_IDS"
gh run watch "$RUN_ID" --repo lingyired/status-trio --exit-status
```

预期测试、release build、DMG 验证全部通过；如运行失败，先将 run ID、失败阶段、原因、修复、复验记到 `docs/swift-ci-compatibility.md`，再重跑新 run；不发布 release。
- [ ] **Step 5: 提交仅验证记录并请求最终 review。** `git add docs/verification/audio-input-controls-2026-09-23.md && git diff --cached && git commit -m "docs(test): record audio input acceptance"`；如果更新 CI 兼容文档，只暂存本任务所加段落。按仓库 Change Flow 判断是否需要 PR（多子系统建议 PR），获审阅前不合并/发布。

## Implementation Notes / Done Criteria

- 每个任务先有针对性红灯，再做最小绿灯；提交前遵守仓库级 `swift test` 和 `swift build -c release`，任务中的局部 `--filter` 仅缩短开发反馈，不代替最终门槛。
- 本计划与已批准 spec 一起使用；如果底层驱动/SDK 证明个别属性不可用，先修改并重新审阅 spec 和计划，不能悄悄以输出属性、音量 0 假静音或“切换成功”假状态绕开。
- 成功时默认关闭不带来输入枚举/监听负担；启用后可通过真实设备切换、读回控制、观察外部变化；无能力、失败和超时可解释；全 12 语言可用；没有新增录音能力。
