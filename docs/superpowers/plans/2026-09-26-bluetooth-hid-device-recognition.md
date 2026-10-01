# 蓝牙 HID 设备识别修正 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正复合 HID 蓝牙设备的图标分类，让声明为鼠标、同时呈现鼠标和键盘接口的设备仍识别为鼠标，同时保留 MX Keys 的误分类修正。

**Architecture:** 将 I/O Registry 的 usage 集合转换为 `BluetoothHIDCapabilities`，只表达设备具备的输入能力；再由 `BluetoothDeviceKindRefinement` 把这些能力与 `system_profiler` 声明的 `PeripheralForm` 联合判断。高置信度的触控板/游戏手柄信号优先；鼠标或键盘声明只有得到对应 HID usage 支持时才保留；单一鼠标/键盘能力可修正错误声明；鼠标与键盘能力同时存在且声明不能消歧时返回 `nil`，保留原声明。

**Tech Stack:** Swift 6、IOKit、Swift Testing、Swift Package Manager。

**Spec:** 本计划将用户引用的「蓝牙设备识别修正」对话中列出的联合判断方案具体化；决策表、边界和验收用例均在本文件内，实施时无需依赖对话预览。

## Global Constraints

- CI 验收环境是 `macos-26` 运行器、Xcode 26.6、Swift 6.3.3；Swift 代码必须与该工具链兼容。
- app 必须使用 macOS 26 SDK 或更新版本构建；不得移除 `scripts/build-app.sh` 的 SDK 检查与 `scripts/verify-platform-version.sh` 的断言。
- 不使用 `isolated deinit` / `IsolatedDeinit`；不写 `weak let`；不把 actor-isolated 方法直接当函数值传递。
- 保留现有范围限制：仅 `.peripheral` 与 `.unknown` 接受 HID 修正；`BluetoothDeviceKindRefinement.apply` 必须检查 `device.isConnected`，即使传入的 HID 字典中残留同地址的数据，断开设备也保留原 kind。
- 不增加设备名称白名单；不更改图标映射、本地化、菜单栏/Dock 图标或 HID Reader 的 I/O Registry 读取方式。
- 提交 Swift 修改前运行 `swift test` 和 `swift build -c release`。

## 证据状态与验收边界

G603 误识别来自用户反馈；项目维护者当前没有这台设备，也没有误识别当时的 `system_profiler` 类型与 I/O Registry usage。"declared mouse + mouse HID + keyboard HID" 是一种可能的输入模式，尚未在 G603 上确认。本计划以该复合 HID 模式的规则与回归测试作为验收范围；取得 G603 实机数据不是实施前置条件，也不声称已在该设备上验证修复。

若报告问题的用户后续愿意提供诊断数据，在误识别状态收集以下同一设备的字段，并按 `BluetoothBatteryReader.normalizedAddress(_:)` 核对地址：

1. `system_profiler -json SPBluetoothDataType` 中的连接状态、`device_minorType` 与设备地址。
2. `ioreg -r -c IOHIDDevice -l` 中该地址的每个 `Transport`、`DeviceAddress`、`PrimaryUsagePage`、`PrimaryUsage`。只保留目标设备的字段；共享记录时遮盖实际蓝牙地址。

若后续数据符合 declared mouse + mouse/keyboard HID，Task 2 的回归可用于核对该报告；若不同，则根据实际输入另行分析，不将本计划的测试结果当作 G603 实机验证。

## File Structure

- Modify: `Sources/StatusTrioCore/Monitoring/BluetoothHIDUsageReader.swift` — 新增能力聚合模型，并将按 usage 直接给出设备身份的 classifier 改为基于能力与声明类型判定。
- Modify: `Sources/StatusTrioCore/Models/BluetoothDeviceKind.swift` — `BluetoothDeviceKindRefinement.apply` 提取原声明的 `PeripheralForm` 并传入融合逻辑；维持现有可修正类别边界。
- Modify: `Tests/StatusTrioCoreTests/BluetoothHIDUsageTests.swift` — 用能力聚合、分类决策表及端到端 refinement 回归覆盖新规则，移除旧的“键盘永远胜过鼠标”假设。
- Modify: `docs/bluetooth-status.md` — 更新当前 HID 修正规则，说明 HID usages 是能力、而非设备身份，并记录复合设备的消歧行为。

## Decision Table

| HID capabilities | Declared form | Result |
| --- | --- | --- |
| 含 touch pad / finger | 任意可修正声明 | `.trackpad` |
| 含 game pad / joystick | 任意可修正声明 | `.gamepad` |
| 含 mouse 与 keyboard | `.mouse` | `.mouse` |
| 含 mouse 与 keyboard | `.keyboard` | `.keyboard` |
| 只有 keyboard（含 keypad） | 任意 / 无声明 | `.keyboard` |
| 只有 mouse（含 pointer / multi-axis） | 任意 / 无声明 | `.mouse` |
| 同时含 mouse 与 keyboard | 无声明 | `nil`，保留原 kind |
| 同时含 mouse 与 keyboard | 其他声明（例如 `.gamepad`） | `nil`，保留原 kind |
| 不含本功能识别的 usage | 任意 | `nil`，保留原 kind |

上述判定只对已连接的 `.peripheral` / `.unknown` 设备运行；断开设备即使在 `hidUsages` 中还有同地址条目，也保留原 kind。

## Review Focus

1. **复合鼠标输入模式**：声明为 `.mouse` 且同时有 mouse + keyboard usages 时仍为 `.mouse`；Task 2 的端到端 refinement 测试覆盖，并测试两个 usage 顺序。该合成用例不等同于 G603 实机验证。
2. **MX Keys 回归**：声明为 `.mouse` 且仅有 keyboard usage 时修正为 `.keyboard`；Task 2 覆盖。
3. **真正的键盘复合指针**：声明为 `.keyboard` 且有 keyboard + mouse usages 时仍为 `.keyboard`；Task 2 覆盖。
4. **特殊能力信号**：Digitizer touch pad/finger 仍优先为 `.trackpad`，game pad/joystick 仍为 `.gamepad`；Task 1 覆盖能力解析，Task 2 覆盖融合结果。
5. **未知、断开或不完整输入**：只有 mouse+keyboard 但无声明、空 usages、未知 usage、不允许 HID 修正的类别，以及断开设备仍有残留 HID 数据时，都不得被武断改类；Task 2 覆盖这些边界。

---

### Task 1: 从 HID usages 汇总输入能力

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/BluetoothHIDUsageReader.swift`
- Test: `Tests/StatusTrioCoreTests/BluetoothHIDUsageTests.swift`

**Interfaces:**
- Consumes: `BluetoothHIDUsage(usagePage:usage:)`。
- Produces: `BluetoothHIDCapabilities`，包含 `hasMouse`、`hasKeyboard`、`hasTrackpad`、`hasGamepad` 四个只读布尔能力；`BluetoothHIDCapabilities.init(usages:)` 对应现有 classifier 识别的 Generic Desktop 与 Digitizer usage。

- [ ] **Step 1: 为能力聚合写测试**

在 `BluetoothHIDUsageClassifierTests` 附近新增纯函数测试：

```swift
@Test func capabilitiesCollectEveryRecognizedInputRole() {
    let capabilities = BluetoothHIDCapabilities(usages: [
        usage(1, 2),       // mouse
        usage(1, 6),       // keyboard
        usage(0x0D, 0x05), // touch pad
        usage(1, 5),       // game pad
    ])

    #expect(capabilities.hasMouse)
    #expect(capabilities.hasKeyboard)
    #expect(capabilities.hasTrackpad)
    #expect(capabilities.hasGamepad)
}

@Test func unknownUsagesProduceNoCapabilities() {
    let capabilities = BluetoothHIDCapabilities(usages: [usage(0x0C, 1), usage(1, 0x80)])

    #expect(!capabilities.hasMouse)
    #expect(!capabilities.hasKeyboard)
    #expect(!capabilities.hasTrackpad)
    #expect(!capabilities.hasGamepad)
}
```

- [ ] **Step 2: 运行针对性测试，确认能力类型缺失导致失败**

Run: `swift test --filter BluetoothHIDUsageClassifierTests`
Expected: FAIL，因为 `BluetoothHIDCapabilities` 尚未实现。

- [ ] **Step 3: 实现能力聚合**

在 `BluetoothHIDUsageReader.swift` 将用法常量保留在同一文件，并新增：

```swift
struct BluetoothHIDCapabilities: Equatable, Sendable {
    let hasMouse: Bool
    let hasKeyboard: Bool
    let hasTrackpad: Bool
    let hasGamepad: Bool

    private enum UsagePage {
        static let genericDesktop = 1
        static let digitizer = 0x0D
    }

    private enum GenericDesktopUsage {
        static let pointer = 1
        static let mouse = 2
        static let joystick = 4
        static let gamePad = 5
        static let keyboard = 6
        static let keypad = 7
        static let multiAxisController = 8
    }

    private enum DigitizerUsage {
        static let touchPad = 0x05
        static let finger = 0x22
    }

    init(usages: [BluetoothHIDUsage]) {
        func has(_ page: Int, _ usage: Int) -> Bool {
            usages.contains { $0.usagePage == page && $0.usage == usage }
        }

        hasMouse = has(UsagePage.genericDesktop, GenericDesktopUsage.pointer)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.mouse)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.multiAxisController)
        hasKeyboard = has(UsagePage.genericDesktop, GenericDesktopUsage.keyboard)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.keypad)
        hasTrackpad = has(UsagePage.digitizer, DigitizerUsage.touchPad)
            || has(UsagePage.digitizer, DigitizerUsage.finger)
        hasGamepad = has(UsagePage.genericDesktop, GenericDesktopUsage.joystick)
            || has(UsagePage.genericDesktop, GenericDesktopUsage.gamePad)
    }
}
```

能力模型只描述观察到的接口，不提供 `PeripheralForm` 或“设备真实类型”。

- [ ] **Step 4: 运行针对性测试，确认能力聚合通过**

Run: `swift test --filter BluetoothHIDUsageClassifierTests`
Expected: PASS，能力组合与未知 usage 用例通过。

- [ ] **Step 5: 满足 Swift 修改的提交门槛**

Run: `swift test`
Expected: PASS，0 failures。

Run: `swift build -c release`
Expected: 构建成功。

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/BluetoothHIDUsageReader.swift Tests/StatusTrioCoreTests/BluetoothHIDUsageTests.swift
git commit -m "refactor(bluetooth): model HID input capabilities"
```

---

### Task 2: 联合声明类型与 HID 能力并接入 refinement

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/BluetoothHIDUsageReader.swift`
- Modify: `Sources/StatusTrioCore/Models/BluetoothDeviceKind.swift`
- Test: `Tests/StatusTrioCoreTests/BluetoothHIDUsageTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `BluetoothHIDCapabilities(usages:)`；`BluetoothDevice.kind`；既有 `BluetoothDeviceKind.acceptsHIDRefinement`。
- Produces: `BluetoothHIDUsageClassifier.peripheralForm(from:declared:) -> PeripheralForm?`；`BluetoothDeviceKindRefinement.apply(to:hidUsages:)` 将 `.peripheral(form)` 中的 form 作为 declared 输入，`.unknown` 传 `nil`。

- [ ] **Step 1: 先增加融合规则失败测试**

将旧测试 `aKeyboardOutranksThePointerItAlsoPresents` 删除，并在 classifier/refinement 测试中加入以下回归：

```swift
@Test func aDeclaredMouseOutranksAnAuxiliaryKeyboardInterface() {
    #expect(
        BluetoothHIDUsageClassifier.peripheralForm(
            from: [usage(1, 2), usage(1, 6)],
            declared: .mouse
        ) == .mouse
    )
}

@Test func aKeyboardOnlyUsageCorrectsAWronglyDeclaredMouse() {
    #expect(
        BluetoothHIDUsageClassifier.peripheralForm(
            from: [usage(1, 6)],
            declared: .mouse
        ) == .keyboard
    )
}

@Test func aDeclaredKeyboardOutranksItsPointerInterface() {
    #expect(
        BluetoothHIDUsageClassifier.peripheralForm(
            from: [usage(1, 6), usage(1, 2)],
            declared: .keyboard
        ) == .keyboard
    )
}

@Test func ambiguousMouseAndKeyboardWithoutADeclarationAnswerNothing() {
    #expect(
        BluetoothHIDUsageClassifier.peripheralForm(
            from: [usage(1, 2), usage(1, 6)],
            declared: nil
        ) == nil
    )
}
```

在 `BluetoothDeviceKindRefinementTests` 加入端到端用例（沿用该测试结构现有的 `device(kind:)` helper 与 `mouseUsage`）：

```swift
@Test func aDeclaredMouseStaysMouseWhenItAlsoPresentsAKeyboardInterface() {
    for usages in [[mouseUsage, keyboardUsage], [keyboardUsage, mouseUsage]] {
        let refined = BluetoothDeviceKindRefinement.apply(
            to: [device(kind: .peripheral(.mouse))],
            hidUsages: ["D36D6C40A32E": usages]
        )

        #expect(refined.first?.kind == .peripheral(.mouse))
    }
}

@Test func anUnknownKindStaysUnknownWhenMouseAndKeyboardAreAmbiguous() {
    let refined = BluetoothDeviceKindRefinement.apply(
        to: [device(kind: .unknown)],
        hidUsages: ["D36D6C40A32E": [mouseUsage, keyboardUsage]]
    )

    #expect(refined.first?.kind == .unknown)
}

@Test func aDeclaredKeyboardStaysKeyboardWithItsPointerInterface() {
    let refined = BluetoothDeviceKindRefinement.apply(
        to: [device(kind: .peripheral(.keyboard))],
        hidUsages: ["D36D6C40A32E": [mouseUsage, keyboardUsage]]
    )

    #expect(refined.first?.kind == .peripheral(.keyboard))
}

@Test func aDisconnectedDeviceIgnoresStaleHIDUsages() {
    let refined = BluetoothDeviceKindRefinement.apply(
        to: [device(kind: .peripheral(.mouse), connected: false)],
        hidUsages: ["D36D6C40A32E": [keyboardUsage]]
    )

    #expect(refined.first?.kind == .peripheral(.mouse))
}
```

- [ ] **Step 2: 运行针对性测试，确认旧 API 与旧优先级不能满足回归**

Run: `swift test --filter BluetoothHIDUsage`
Expected: FAIL，因为新的 `declared:` 参数尚不存在，且现有组合设备规则会将鼠标判为键盘；此筛选同时包含 classifier 与 refinement 测试。

- [ ] **Step 3: 实现联合分类和 refinement 接入**

将 classifier 的函数签名改为 `static func peripheralForm(from usages: [BluetoothHIDUsage], declared: PeripheralForm?) -> PeripheralForm?`，实现规则如下：

```swift
static func peripheralForm(
    from usages: [BluetoothHIDUsage],
    declared: PeripheralForm?
) -> PeripheralForm? {
    let capabilities = BluetoothHIDCapabilities(usages: usages)

    if capabilities.hasTrackpad { return .trackpad }
    if capabilities.hasGamepad { return .gamepad }

    if capabilities.hasMouse && capabilities.hasKeyboard {
        if declared == .mouse || declared == .keyboard {
            return declared
        }
        return nil
    }
    if capabilities.hasKeyboard { return .keyboard }
    if capabilities.hasMouse { return .mouse }
    return nil
}
```

移除 classifier 原来重复的 usage 常量与 `has(_:_:)` 逻辑；能力解析只由 `BluetoothHIDCapabilities` 负责。这样同时呈现 mouse 与 keyboard usage 的已声明鼠标不会被辅助 keyboard usage 覆盖，MX Keys 的 keyboard-only usage 仍可修正错误的 mouse 声明。

在 `BluetoothDeviceKindRefinement.apply` 中明确检查连接状态、提取原声明并传给 classifier；用以下代码替换现有 `devices.map` 主体：

```swift
devices.map { device in
    guard device.isConnected, device.kind.acceptsHIDRefinement else {
        return device
    }

    let declared: PeripheralForm?
    if case .peripheral(let form) = device.kind {
        declared = form
    } else {
        declared = nil
    }

    guard let form = BluetoothHIDUsageClassifier.peripheralForm(
        from: hidUsages[BluetoothBatteryReader.normalizedAddress(device.id)] ?? [],
        declared: declared
    ) else {
        return device
    }
    return device.replacingKind(with: .peripheral(form))
}
```

同步更新 classifier 与 refinement 的注释，删除“keyboard always outranks pointer”的规则说明。

- [ ] **Step 4: 补齐边界测试并运行针对性测试**

将 `BluetoothHIDUsageClassifierTests` 中现有的单一能力、特殊能力、空输入、未知 usage 断言改为新签名；其中没有声明的纯 usage 测试传入 `declared: nil`，例如：

```swift
#expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 6)], declared: nil) == .keyboard)
#expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 2)], declared: nil) == .mouse)
#expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 2), usage(0x0D, 0x05)], declared: nil) == .trackpad)
#expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(1, 5)], declared: nil) == .gamepad)
#expect(BluetoothHIDUsageClassifier.peripheralForm(from: [], declared: nil) == nil)
#expect(BluetoothHIDUsageClassifier.peripheralForm(from: [usage(0x0C, 0x01)], declared: nil) == nil)
```

同样更新该测试结构中 keypad、pointer、multi-axis、joystick、finger 的现有断言，并保留 `BluetoothDeviceKindRefinementTests` 已有的不可修正 kind 回归。运行：

Run: `swift test --filter BluetoothHIDUsage`
Expected: PASS，复合鼠标、MX Keys、键盘复合指针、触控板、手柄、断开设备及保留原 kind 的用例通过。

- [ ] **Step 5: 满足 Swift 修改的提交门槛**

Run: `swift test`
Expected: PASS，0 failures。

Run: `swift build -c release`
Expected: 构建成功。

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/BluetoothHIDUsageReader.swift Sources/StatusTrioCore/Models/BluetoothDeviceKind.swift Tests/StatusTrioCoreTests/BluetoothHIDUsageTests.swift
git commit -m "fix(bluetooth): combine HID capabilities with declared kind"
```

---

### Task 3: 更新蓝牙识别文档

**Files:**
- Modify: `docs/bluetooth-status.md`

- [ ] **Step 1: 更新识别规则说明**

在 “Correcting a class the report got wrong” 英文段落中，将“a keyboard outranks the pointing surface”改为：HID usages 表示设备可提供的输入能力，不单独决定设备身份；mouse+keyboard 同时出现时，保留有对应 mouse/keyboard usage 支持的声明类型；若只有其中一种能力，则可修正错误声明；冲突且无声明可消歧时不改原分类。保留 touch pad 优先于 pointer、只修正 `.peripheral`/`.unknown`、只针对 connected HID 设备等已记录限制。

- [ ] **Step 2: 检查文档及代码差异**

Run: `git diff --check`
Expected: 无空白错误；文档不再声称 keyboard usage 固定优先于 mouse usage。

- [ ] **Step 3: Commit**

```bash
git add docs/bluetooth-status.md
git commit -m "docs(bluetooth): describe HID capability refinement"
```
