# 蓝牙设备动作（点击连接/断开）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让状态面板与详情页的蓝牙设备行可点击——未连接则连接、已连接则断开——键鼠类设备的断开先在行内确认，且任何动作的成败都以系统报告为准（不做乐观翻转）。

**Architecture:** 新增一个后台队列上的 IOBluetooth 动作执行器（protocol + 实现），在 `BluetoothDeviceController` 上按规范化地址维护每台设备的动作状态（进行中 / 失败）与超时，视图只渲染状态；`BluetoothDeviceRow` 变成由输入驱动的可点行，确认态由两个父视图各自的 `@State` 持有。

**Tech Stack:** Swift 6、SwiftUI、IOBluetooth、XCTest（含 `ManualEventSleeper` 注入式 sleep）、Swift Package Manager。

**Spec:** `docs/superpowers/specs/2026-09-22-bluetooth-device-actions-design.md`

## 与 spec 的两处偏离（本计划裁定，均是硬约束逼出来的）

1. **新增第 8 条文案键 `bluetooth.action.connect`（"Connect"）**。spec 只列了 7 条，但「行的无障碍 label 要说明动作」与 `.help` 提示都需要一个「连接」动词；没有它，未连接行的 label 只能重复「未连接」而说不出该行能做什么。
2. **行内确认的提示文案不带设备名**：spec 写的是 `Disconnect "%@"?`，但 330pt 宽的面板里一行要同时容纳图标、设备名、提示与两个按钮——带上设备名的提示必然换行或截断按钮，破坏「确认保持单行」这一硬要求。改为固定的「断开？」（`bluetooth.action.confirmDisconnect` = "Disconnect?"，用 `string(_:)` 而非 `format`），行的图标与设备名已经指明了是哪台设备。Task 4 用**最长的设备名夹具**钉住「确认态仍是单行」。

## Global Constraints

- CI 验收环境是 `macos-26` 运行器、Xcode 26.6、Swift 6.3.3；不得使用更新的语法。
- 必须使用 macOS 26 或更新的 SDK 构建；不得移除 `scripts/build-app.sh` 的 SDK 检查与 `scripts/verify-platform-version.sh` 的断言。
- 不使用 `isolated deinit` / `IsolatedDeinit`；不写 `weak let`；不把 actor 隔离的方法直接当函数值传递。
- 只用**公开** IOBluetooth API（`pairedDevices()` / `openConnection()` / `closeConnection()`），**不得**引入私有 API；不需要 `@available` 门槛（这些 API 在 macOS 15 上就存在）。
- `openConnection()` / `closeConnection()` 是**同步**调用：必须只在动作执行器的专用队列上调用，绝不出现在主线程或视图回调里。
- **不做乐观翻转**：行的连接状态只能由 `system_profiler` 报告（或连接通知触发的刷新）改变；动作的返回值只用于「指令是否被接受」。
- 设备一律按 `BluetoothBatteryReader.normalizedAddress(_:)` 匹配；**绝不使用 IOBluetooth 的名字**（对同一台设备它会报改名前的缓存名）。
- 不新增系统权限、不新增后台轮询、不改动菜单栏/Dock 图标与图标相关设置（icon parity 规则不触发）。
- 新增 8 条本地化键，12 种语言必须齐全，术语取自各语言既有 `.lproj`。
- 本次改动涉及 SwiftUI 绑定与 `@MainActor` 状态：除 `swift test` 与 `swift build -c release` 外，合并前还必须跑一次 `publish=false` 的 release 预检；预检要求 ref 已在远端，因此推送需人类伙伴授权（见 Task 5）。
- 分支：`feat/bluetooth-device-actions`，从 `main` 分出。

## File Structure

- Create: `Sources/StatusTrioCore/Models/BluetoothDeviceAction.swift` — `BluetoothDeviceAction` / `BluetoothDeviceActionState` / `BluetoothDeviceActionPolicy`（纯规则，可单测）。
- Create: `Sources/StatusTrioCore/Monitoring/BluetoothDeviceActionPerformer.swift` — `BluetoothDeviceActionPerforming` protocol 与 IOBluetooth 实现（后台队列）。
- Modify: `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift` — 动作状态字典、超时与失败清理、`performDeviceAction(for:)`、`reconcileDeviceActions()`、init 注入、`deactivate()` 清理。
- Modify: `Sources/StatusTrioCore/UI/BluetoothDeviceRow.swift` — 行改为可点，渲染进行中/失败/确认三种状态。
- Modify: `Sources/StatusTrioCore/UI/BluetoothDeviceList.swift` — 持有确认态、把动作状态与回调传给行。
- Modify: `Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift` — 详情页持有确认态并把动作状态与回调传给行（概要行本身不变）。
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift` + `Sources/StatusTrioCore/Resources/*/Localizable.strings`（12 个）— 8 条新键。
- Test: Create `Tests/StatusTrioCoreTests/BluetoothDeviceActionsTests.swift`、`Tests/StatusTrioCoreTests/BluetoothDeviceRowLayoutTests.swift`。
- Modify: `docs/bluetooth-status.md`、`release-notes/1.3.0/*.md`（12 个）。

## Review Focus

1. **行内确认必须在 330pt 宽度下保持单行**（图标 + 设备名 + 「断开？」 + 两个按钮）。Task 4 用最长设备名夹具断言确认态与普通态行高相同——若确认态换行或把按钮挤出，该断言必须失败。
2. **不做乐观翻转**：Task 2 必须有「指令被接受但报告始终没变 → 超时 → 失败」的用例；任何让指令返回值直接翻转行状态的实现都是缺陷。
3. **键鼠断开的确认不可绕过**：`.peripheral` + 已连接才需要确认；音频/手机/电脑/未知设备与所有未连接设备直接执行（Task 2 的纯函数测试逐类钉住）。
4. **同步 IOBluetooth 调用不得出现在主线程**：Task 1 的队列是唯一调用点；Task 2 的 stub 只能证明接口语义，真机路径由已完成的探针与 Task 5 的手动验证覆盖。
5. **8 条键 ×12 语言齐全且不含音频场景残留用词**（Task 3 的术语检查）。

---

### Task 1: 动作执行器（IOBluetooth 适配层）

**Files:**
- Create: `Sources/StatusTrioCore/Monitoring/BluetoothDeviceActionPerformer.swift`

**Interfaces:**
- Consumes: `BluetoothBatteryReader.normalizedAddress(_:)`、`IOBluetoothDevice.pairedDevices()` / `openConnection()` / `closeConnection()`、`kIOReturnSuccess`。
- Produces: `protocol BluetoothDeviceActionPerforming { func setConnected(_ connected: Bool, forAddress address: String, completion: @escaping @Sendable (Bool) -> Void) }`；`final class IOBluetoothDeviceActionPerformer: @unchecked Sendable, BluetoothDeviceActionPerforming`（Task 2 的 controller 以该 protocol 注入，测试用 stub 替代）。

本任务**没有单测**：实现依赖真实蓝牙硬件。它的正确性由已完成的真机探针（两个方向都返回 `kIOReturnSuccess`、约 0.5s 生效、系统不自动回连）与本任务的编译/全量测试验证；语义由 Task 2 通过 protocol 的 stub 钉住。

- [ ] **Step 1: 写实现**

新建 `Sources/StatusTrioCore/Monitoring/BluetoothDeviceActionPerformer.swift`：

```swift
import Foundation
import IOBluetooth
import IOKit

/// Asks the system to connect or disconnect a paired device.
///
/// `IOBluetoothDevice`'s connect and disconnect calls are synchronous and can
/// block until the page timeout when a device is out of range, so the
/// implementation runs them on its own queue and the controller only ever sees
/// whether the system accepted the request. Whether the link actually comes up
/// is decided by the device report, never by this return value.
protocol BluetoothDeviceActionPerforming: AnyObject {
    func setConnected(
        _ connected: Bool,
        forAddress address: String,
        completion: @escaping @Sendable (Bool) -> Void
    )
}

final class IOBluetoothDeviceActionPerformer: @unchecked Sendable, BluetoothDeviceActionPerforming {
    private let queue = DispatchQueue(
        label: "StatusTrio.IOBluetoothDeviceActionPerformer",
        qos: .userInitiated
    )

    func setConnected(
        _ connected: Bool,
        forAddress address: String,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        queue.async {
            // The paired list is the only source of a device handle, and it is
            // matched on the normalized address: IOBluetooth keeps reporting the
            // name a device had before it was renamed, so names cannot join it to
            // the report the UI is built from.
            let target = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?
                .first {
                    BluetoothBatteryReader.normalizedAddress($0.addressString ?? "") == address
                }
            guard let target else {
                // The device is gone from the paired database (unpaired, say).
                completion(false)
                return
            }
            let result = connected ? target.openConnection() : target.closeConnection()
            completion(result == kIOReturnSuccess)
        }
    }
}
```

- [ ] **Step 2: 构建与全量测试**

Run: `swift build -c release`
Expected: 构建成功，0 errors（`import IOKit` 会解析出 `kIOReturnSuccess`；仓库已有 `BatteryMonitor` 等文件这样做）。

Run: `swift test`
Expected: PASS，0 failures（本任务不改变任何现有行为）。

- [ ] **Step 3: 提交**

```bash
git add Sources/StatusTrioCore/Monitoring/BluetoothDeviceActionPerformer.swift
git commit -m "feat(bluetooth): add the device action performer"
```

---

### Task 2: 动作规则与状态机

**Files:**
- Create: `Sources/StatusTrioCore/Models/BluetoothDeviceAction.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`
- Test: Create `Tests/StatusTrioCoreTests/BluetoothDeviceActionsTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `BluetoothDeviceActionPerforming`；`BluetoothDevice`（`id` / `kind` / `isConnected`）。
- Produces:
  - `BluetoothDeviceAction`（`.connect` / `.disconnect`，含 `inFlightState`）
  - `BluetoothDeviceActionState`（`.connecting` / `.disconnecting` / `.failed(BluetoothDeviceAction)`）
  - `BluetoothDeviceActionPolicy.action(for:) -> BluetoothDeviceAction`
  - `BluetoothDeviceActionPolicy.requiresConfirmation(for:) -> Bool`
  - `BluetoothDeviceActionPolicy.status(for:actionState:) -> BluetoothDeviceRowStatus`（Task 4 的行渲染用）
  - `BluetoothDeviceController.deviceActionStates: [String: BluetoothDeviceActionState]`（`@Published private(set)`，键是规范化地址）
  - `BluetoothDeviceController.performDeviceAction(for device: BluetoothDevice)`
  - init 新增注入：`actionPerformer`、`actionTimeout`（默认 10 秒）、`actionTimeoutSleep`、`failureVisibleDuration`（默认 4 秒）、`failureVisibleSleep`

- [ ] **Step 1: 写失败的测试**

新建 `Tests/StatusTrioCoreTests/BluetoothDeviceActionsTests.swift`：

```swift
import Foundation
import XCTest
@testable import StatusTrioCore

/// Tapping a device row asks the system to connect or disconnect it. Nothing in
/// this path flips a row optimistically: the report decides, the request only
/// starts a wait that either sees the report change or fails.
@MainActor
final class BluetoothDeviceActionsTests: XCTestCase {
    private let airPodsAddress = "AC:90:85:C2:9C:1F"

    private func makeDevice(isConnected: Bool, name: String = "AirPods", kind: BluetoothDeviceKind = .audio) -> BluetoothDevice {
        BluetoothDevice(id: airPodsAddress, name: name, kind: kind, isConnected: isConnected)
    }

    private func makeController(
        device: BluetoothDevice,
        performer: BluetoothActionPerformerStub,
        timeoutSleeper: ManualEventSleeper,
        failureSleeper: ManualEventSleeper
    ) -> (BluetoothDeviceController, MutableBluetoothDeviceReader) {
        let reader = MutableBluetoothDeviceReader(devices: [device])
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: ActionTestStateMonitor(),
            batteryReader: SilentBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            actionPerformer: performer,
            actionTimeoutSleep: { duration in await timeoutSleeper.sleep(duration) },
            failureVisibleSleep: { duration in await failureSleeper.sleep(duration) }
        )
        return (controller, reader)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the controller to settle")
    }

    func testTapOnAnUnconnectedDeviceAsksToConnectAndShowsConnecting() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        let timeoutSleeper = ManualEventSleeper()
        let failureSleeper = ManualEventSleeper()
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: timeoutSleeper,
            failureSleeper: failureSleeper
        )
        controller.activate()
        await waitUntil { controller.availability == .available }

        controller.performDeviceAction(for: device)

        XCTAssertEqual(performer.requests.map(\.connected), [true])
        XCTAssertEqual(
            performer.requests.map(\.address),
            [BluetoothBatteryReader.normalizedAddress(airPodsAddress)]
        )
        XCTAssertEqual(
            controller.deviceActionStates[BluetoothBatteryReader.normalizedAddress(airPodsAddress)],
            .connecting
        )
        XCTAssertEqual(
            BluetoothDeviceActionPolicy.status(for: device, actionState: .connecting),
            .connecting
        )
        controller.deactivate()
    }

    func testConnectingClearsOnlyWhenTheReportShowsTheDeviceConnected() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        let (controller, reader) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.performDeviceAction(for: device)
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)

        // The request was accepted, but the report has not changed yet: the row
        // must still say it is working.
        XCTAssertEqual(controller.deviceActionStates[address], .connecting)

        reader.devices = [makeDevice(isConnected: true)]
        controller.refresh()

        await waitUntil { controller.deviceActionStates[address] == nil }
        controller.deactivate()
    }

    func testDisconnectingClearsWhenTheReportShowsTheDeviceGone() async {
        let device = makeDevice(isConnected: true)
        let performer = BluetoothActionPerformerStub()
        let (controller, reader) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.performDeviceAction(for: device)
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)
        XCTAssertEqual(performer.requests.map(\.connected), [false])
        XCTAssertEqual(controller.deviceActionStates[address], .disconnecting)

        reader.devices = [makeDevice(isConnected: false)]
        controller.refresh()

        await waitUntil { controller.deviceActionStates[address] == nil }
        controller.deactivate()
    }

    func testARejectedRequestFailsImmediately() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        performer.accepted = false
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }

        controller.performDeviceAction(for: device)
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)
        await waitUntil { controller.deviceActionStates[address] == .failed(.connect) }
        controller.deactivate()
    }

    func testAnAcceptedRequestThatNeverChangesTheReportTimesOut() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        let timeoutSleeper = ManualEventSleeper()
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: timeoutSleeper,
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.performDeviceAction(for: device)
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)

        let armed = await timeoutSleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertTrue(armed, "the action must arm a timeout")
        XCTAssertEqual(timeoutSleeper.durations.first, .seconds(10))
        timeoutSleeper.releaseAll()

        await waitUntil { controller.deviceActionStates[address] == .failed(.connect) }
        controller.deactivate()
    }

    func testAFailureClearsItselfAfterTheVisibleDuration() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        performer.accepted = false
        let failureSleeper = ManualEventSleeper()
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: failureSleeper
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.performDeviceAction(for: device)
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)
        await waitUntil { controller.deviceActionStates[address] == .failed(.connect) }

        let armed = await failureSleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertTrue(armed, "a failure must arm its own clear")
        XCTAssertEqual(failureSleeper.durations.first, .seconds(4))
        failureSleeper.releaseAll()

        await waitUntil { controller.deviceActionStates[address] == nil }
        controller.deactivate()
    }

    func testASecondTapWhileInFlightSendsNoSecondRequest() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }

        controller.performDeviceAction(for: device)
        controller.performDeviceAction(for: device)
        controller.performDeviceAction(for: device)

        XCTAssertEqual(performer.requests.count, 1)
        controller.deactivate()
    }

    func testAFailedRowAcceptsARetry() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        performer.accepted = false
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.performDeviceAction(for: device)
        let address = BluetoothBatteryReader.normalizedAddress(airPodsAddress)
        await waitUntil { controller.deviceActionStates[address] == .failed(.connect) }

        controller.performDeviceAction(for: device)

        XCTAssertEqual(performer.requests.count, 2)
        controller.deactivate()
    }

    func testDeactivatingClearsEveryActionState() async {
        let device = makeDevice(isConnected: false)
        let performer = BluetoothActionPerformerStub()
        let (controller, _) = makeController(
            device: device,
            performer: performer,
            timeoutSleeper: ManualEventSleeper(),
            failureSleeper: ManualEventSleeper()
        )
        controller.activate()
        await waitUntil { controller.availability == .available }
        controller.performDeviceAction(for: device)

        controller.deactivate()

        XCTAssertTrue(controller.deviceActionStates.isEmpty)
    }

    func testOnlyDisconnectingAnInputDeviceNeedsConfirmation() {
        XCTAssertTrue(
            BluetoothDeviceActionPolicy.requiresConfirmation(
                for: makeDevice(isConnected: true, name: "MX Keys", kind: .peripheral)
            )
        )
        XCTAssertFalse(
            BluetoothDeviceActionPolicy.requiresConfirmation(
                for: makeDevice(isConnected: false, name: "MX Keys", kind: .peripheral)
            )
        )
        for kind in [BluetoothDeviceKind.audio, .computer, .phone, .unknown] {
            XCTAssertFalse(
                BluetoothDeviceActionPolicy.requiresConfirmation(
                    for: makeDevice(isConnected: true, kind: kind)
                ),
                "\(kind) must disconnect without a confirmation"
            )
        }
    }

    func testTheActionFollowsTheConnectionState() {
        XCTAssertEqual(BluetoothDeviceActionPolicy.action(for: makeDevice(isConnected: true)), .disconnect)
        XCTAssertEqual(BluetoothDeviceActionPolicy.action(for: makeDevice(isConnected: false)), .connect)
    }

    func testTheRowStatusFollowsTheActionState() {
        let device = makeDevice(isConnected: true)

        XCTAssertEqual(BluetoothDeviceActionPolicy.status(for: device, actionState: nil), .connected)
        XCTAssertEqual(
            BluetoothDeviceActionPolicy.status(for: makeDevice(isConnected: false), actionState: nil),
            .notConnected
        )
        XCTAssertEqual(
            BluetoothDeviceActionPolicy.status(for: device, actionState: .connecting),
            .connecting
        )
        XCTAssertEqual(
            BluetoothDeviceActionPolicy.status(for: device, actionState: .disconnecting),
            .disconnecting
        )
        XCTAssertEqual(
            BluetoothDeviceActionPolicy.status(for: device, actionState: .failed(.connect)),
            .connectFailed
        )
        XCTAssertEqual(
            BluetoothDeviceActionPolicy.status(for: device, actionState: .failed(.disconnect)),
            .disconnectFailed
        )
    }
}

private final class BluetoothActionPerformerStub: BluetoothDeviceActionPerforming {
    private(set) var requests: [(connected: Bool, address: String)] = []
    var accepted = true

    func setConnected(
        _ connected: Bool,
        forAddress address: String,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        requests.append((connected, address))
        completion(accepted)
    }
}

private final class MutableBluetoothDeviceReader: BluetoothPairedDeviceReading {
    var devices: [BluetoothDevice]
    private(set) var readCount = 0

    init(devices: [BluetoothDevice]) {
        self.devices = devices
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        readCount += 1
        completion(.success(devices))
    }
}

@MainActor
private final class ActionTestStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() {
        onStateChange?(authorization, .poweredOn)
    }

    func stop() {}
}

private final class SilentBluetoothBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter BluetoothDeviceActionsTests`
Expected: FAIL 编译错误：`cannot find 'BluetoothDeviceActionPolicy' in scope`、`extra argument 'actionPerformer'`。

- [ ] **Step 3: 加规则类型**

新建 `Sources/StatusTrioCore/Models/BluetoothDeviceAction.swift`：

```swift
import Foundation

/// What tapping a device row asks the system to do.
enum BluetoothDeviceAction: Equatable, Sendable {
    case connect
    case disconnect

    /// The state a row shows while this action is in flight.
    var inFlightState: BluetoothDeviceActionState {
        switch self {
        case .connect: .connecting
        case .disconnect: .disconnecting
        }
    }
}

/// A row's action state. No entry for a device means the row reports the
/// device's own connection state.
enum BluetoothDeviceActionState: Equatable, Sendable {
    case connecting
    case disconnecting
    /// The action did not take effect; the row shows this for a few seconds.
    case failed(BluetoothDeviceAction)
}

/// The text a row shows where the connection state normally goes.
enum BluetoothDeviceRowStatus: Equatable, Sendable {
    case connected
    case notConnected
    case connecting
    case disconnecting
    case connectFailed
    case disconnectFailed
}

/// The rules a row's action follows, kept out of the views so both surfaces
/// agree and the rules can be unit-tested.
enum BluetoothDeviceActionPolicy {
    /// Which action a tap requests, from the device's current state.
    static func action(for device: BluetoothDevice) -> BluetoothDeviceAction {
        device.isConnected ? .disconnect : .connect
    }

    /// Disconnecting an input device would cut the user off from their own
    /// keyboard or mouse, so that one action is confirmed in place first. A
    /// connect never needs confirmation, and neither does disconnecting
    /// anything else.
    static func requiresConfirmation(for device: BluetoothDevice) -> Bool {
        device.isConnected && device.kind == .peripheral
    }

    /// What the row shows in place of its connection state.
    static func status(
        for device: BluetoothDevice,
        actionState: BluetoothDeviceActionState?
    ) -> BluetoothDeviceRowStatus {
        switch actionState {
        case .connecting: .connecting
        case .disconnecting: .disconnecting
        case .failed(.connect): .connectFailed
        case .failed(.disconnect): .disconnectFailed
        case nil: device.isConnected ? .connected : .notConnected
        }
    }
}
```

- [ ] **Step 4: 在 controller 里加状态机**

`Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift`：

在 `periodicRefreshGeneration` 之后加属性：

```swift
    /// The action in flight, or the failure still on screen, keyed by normalized
    /// address. No entry means the row reports the device's own state.
    @Published private(set) var deviceActionStates: [String: BluetoothDeviceActionState] = [:]

    private let actionPerformer: any BluetoothDeviceActionPerforming
    private let actionTimeout: Duration
    private let actionTimeoutSleep: @Sendable (Duration) async throws -> Void
    private let failureVisibleDuration: Duration
    private let failureVisibleSleep: @Sendable (Duration) async throws -> Void
    private var actionTimeouts: [String: Task<Void, Never>] = [:]
    private var failureClearTasks: [String: Task<Void, Never>] = [:]
```

init 参数在 `readTimeoutSleep` 之后追加，并在 init 体内赋值：

```swift
        actionPerformer: any BluetoothDeviceActionPerforming = IOBluetoothDeviceActionPerformer(),
        actionTimeout: Duration = .seconds(10),
        actionTimeoutSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        failureVisibleDuration: Duration = .seconds(4),
        failureVisibleSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
```

```swift
        self.actionPerformer = actionPerformer
        self.actionTimeout = actionTimeout
        self.actionTimeoutSleep = actionTimeoutSleep
        self.failureVisibleDuration = failureVisibleDuration
        self.failureVisibleSleep = failureVisibleSleep
```

在 `deactivate()` 的 `availability = .idle` 之前加一行 `clearDeviceActions()`。

在 `refresh()` 的成功分支里、`self.devices = devices` 之后加一行 `self.reconcileDeviceActions()`。

在 `receiveConnectionEvent()` 之前加整段动作逻辑：

```swift
    // MARK: - Device actions

    /// Asks the system to toggle a device. The row's state changes when the
    /// report does, never because this call returned: the request only starts a
    /// wait that ends in the report changing or in a visible failure.
    func performDeviceAction(for device: BluetoothDevice) {
        guard isActive, availability == .available else { return }
        let address = BluetoothBatteryReader.normalizedAddress(device.id)
        switch deviceActionStates[address] {
        case .none, .failed:
            // Free, or a retry of a failure that is still on screen.
            break
        case .connecting, .disconnecting:
            // One action per device at a time.
            return
        }

        let action = BluetoothDeviceActionPolicy.action(for: device)
        deviceActionStates[address] = action.inFlightState
        armActionTimeout(for: action, address: address)
        actionPerformer.setConnected(action == .connect, forAddress: address) { [weak self] accepted in
            guard !accepted else { return }
            Task { @MainActor [weak self] in
                self?.failDeviceAction(action, address: address)
            }
        }
    }

    /// Clears the actions whose target state the report now shows. This is the
    /// only way an action succeeds.
    private func reconcileDeviceActions() {
        guard !deviceActionStates.isEmpty else { return }
        for device in devices {
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            guard let state = deviceActionStates[address] else { continue }
            let reachedTarget = switch state {
            case .connecting: device.isConnected
            case .disconnecting: !device.isConnected
            case .failed: false
            }
            if reachedTarget {
                finishDeviceAction(address: address)
            }
        }
    }

    private func armActionTimeout(for action: BluetoothDeviceAction, address: String) {
        actionTimeouts[address]?.cancel()
        let timeout = actionTimeout
        let sleep = actionTimeoutSleep
        actionTimeouts[address] = Task { @MainActor [weak self] in
            do {
                try await sleep(timeout)
            } catch {
                return
            }
            guard let self, self.deviceActionStates[address] == action.inFlightState else { return }
            self.failDeviceAction(action, address: address)
        }
    }

    private func failDeviceAction(_ action: BluetoothDeviceAction, address: String) {
        actionTimeouts[address]?.cancel()
        actionTimeouts[address] = nil
        deviceActionStates[address] = .failed(action)

        failureClearTasks[address]?.cancel()
        let visible = failureVisibleDuration
        let sleep = failureVisibleSleep
        failureClearTasks[address] = Task { @MainActor [weak self] in
            do {
                try await sleep(visible)
            } catch {
                return
            }
            guard let self, case .failed = self.deviceActionStates[address] else { return }
            self.deviceActionStates[address] = nil
            self.failureClearTasks[address] = nil
        }
    }

    private func finishDeviceAction(address: String) {
        actionTimeouts[address]?.cancel()
        actionTimeouts[address] = nil
        failureClearTasks[address]?.cancel()
        failureClearTasks[address] = nil
        deviceActionStates[address] = nil
    }

    private func clearDeviceActions() {
        for task in actionTimeouts.values { task.cancel() }
        for task in failureClearTasks.values { task.cancel() }
        actionTimeouts.removeAll()
        failureClearTasks.removeAll()
        deviceActionStates.removeAll()
    }
```

- [ ] **Step 5: 运行测试确认通过**

Run: `swift test --filter BluetoothDeviceActionsTests`
Expected: PASS（12 个用例）。

Run: `swift test`
Expected: PASS，0 failures。

Run: `swift build -c release`
Expected: 构建成功，0 errors。

- [ ] **Step 6: 提交**

```bash
git add Sources/StatusTrioCore/Models/BluetoothDeviceAction.swift \
        Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift \
        Tests/StatusTrioCoreTests/BluetoothDeviceActionsTests.swift
git commit -m "feat(bluetooth): toggle a device from its row, waiting on the report"
```

---

### Task 3: 8 条文案键 × 12 语言

**Files:**
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift`
- Modify: `Sources/StatusTrioCore/Resources/{ar,de,en,es,fr,it,ja,ko,pt-BR,ru,zh-Hans,zh-Hant}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: 无（纯文案）。
- Produces: `bluetoothActionConnect` / `bluetoothActionDisconnect` / `bluetoothActionCancel` / `bluetoothActionConfirmDisconnect` / `bluetoothStateConnecting` / `bluetoothStateDisconnecting` / `bluetoothStateConnectFailed` / `bluetoothStateDisconnectFailed`（Task 4 的行渲染使用）。

- [ ] **Step 1: 加键（先让本地化测试失败）**

`LocalizationKey.swift`，在 `bluetoothListCollapse` 之后加：

```swift
    case bluetoothActionConnect = "bluetooth.action.connect"
    case bluetoothActionDisconnect = "bluetooth.action.disconnect"
    case bluetoothActionCancel = "bluetooth.action.cancel"
    case bluetoothActionConfirmDisconnect = "bluetooth.action.confirmDisconnect"
    case bluetoothStateConnecting = "bluetooth.state.connecting"
    case bluetoothStateDisconnecting = "bluetooth.state.disconnecting"
    case bluetoothStateConnectFailed = "bluetooth.state.connectFailed"
    case bluetoothStateDisconnectFailed = "bluetooth.state.disconnectFailed"
```

Run: `swift test --filter LocalizationTests`
Expected: FAIL —— 8 条新键在 12 个语言里都还没有字符串。

- [ ] **Step 2: 写 12 语言文案**

英文与两种中文的完整文案：

| key | en | zh-Hans | zh-Hant |
| --- | --- | --- | --- |
| `bluetooth.action.connect` | Connect | 连接 | 連接 |
| `bluetooth.action.disconnect` | Disconnect | 断开 | 中斷連接 |
| `bluetooth.action.cancel` | Cancel | 取消 | 取消 |
| `bluetooth.action.confirmDisconnect` | Disconnect? | 要断开吗？ | 要中斷連接嗎？ |
| `bluetooth.state.connecting` | Connecting… | 连接中… | 連接中… |
| `bluetooth.state.disconnecting` | Disconnecting… | 断开中… | 中斷連接中… |
| `bluetooth.state.connectFailed` | Could not connect | 连接失败 | 連接失敗 |
| `bluetooth.state.disconnectFailed` | Could not disconnect | 断开失败 | 中斷連接失敗 |

其余 9 种语言按同语言既有术语翻译：`connect` / `disconnect` 参照该语言 `bluetooth.connected` / `bluetooth.notConnected` 与 `bluetooth.noConnectedDevices` 的用词（例如德语用 `verbunden` / `getrennt` 体系、日语用「接続／切断」、韩语用「연결／연결 해제」、法语用 `connecté` / `déconnecté` 体系）；`cancel` 参照该语言 `settings.language` 一类既有对话框用词；失败文案用该语言 `bluetooth.readFailed` 的句式。插入位置：每个 `.lproj` 紧跟 `"bluetooth.list.collapse"` 之后。

- [ ] **Step 3: 术语检查**

Run: `for l in ar de en es fr it ja ko pt-BR ru zh-Hans zh-Hant; do printf '%s ' "$l"; grep -c '^"bluetooth\.\(action\|state\)\.' Sources/StatusTrioCore/Resources/$l.lproj/Localizable.strings; done`
Expected: 12 行，每行都是 `8`。

Run: `grep -n "Ausgabegerät\|output device\|出力デバイス\|출력 장치\|设备输出\|輸出裝置" Sources/StatusTrioCore/Resources/*/Localizable.strings | grep -i "bluetooth\."`
Expected: 无匹配（新文案里不残留音频场景用词）。

Run: `grep -n '%@\|%d' Sources/StatusTrioCore/Resources/*/Localizable.strings | grep 'bluetooth\.action\|bluetooth\.state'`
Expected: 无匹配（确认提示不带参数，避免行内换行）。

- [ ] **Step 4: 运行本地化测试确认通过**

Run: `swift test --filter Localization`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/StatusTrioCore/Localization/LocalizationKey.swift \
        Sources/StatusTrioCore/Resources
git commit -m "feat(localization): add the Bluetooth device action strings"
```

---

### Task 4: 可点行与接线

**Files:**
- Modify: `Sources/StatusTrioCore/UI/BluetoothDeviceRow.swift`
- Modify: `Sources/StatusTrioCore/UI/BluetoothDeviceList.swift`
- Modify: `Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift`（详情页的 `section(_:devices:)`）
- Test: Create `Tests/StatusTrioCoreTests/BluetoothDeviceRowLayoutTests.swift`

**Interfaces:**
- Consumes: Task 2 的 `BluetoothDeviceActionState` / `BluetoothDeviceActionPolicy.status(for:actionState:)`、Task 3 的 8 条键、`BluetoothPanelMetrics`、控制器的 `deviceActionStates` 与 `performDeviceAction(for:)`。
- Produces: `BluetoothDeviceRow(device:batteryLevels:actionState:isConfirmingDisconnect:onPerformAction:onRequestDisconnect:onCancelDisconnect:)`；`BluetoothDeviceList(devices:batteryLevels:actionStates:options:onPerformAction:)`（`actionStates` 声明在 `batteryLevels` 之后、`options` 之前；`onPerformAction` 在 `options` 之后）。

确认态是**行视图的输入**而不是行内部的 `@State`，两个父视图各自持有 `@State private var confirmingAddress: String?`。这样行是一个纯函数式的视图（可直接渲染测试），而确认态随面板关闭自然消失。

- [ ] **Step 1: 写失败的渲染测试**

新建 `Tests/StatusTrioCoreTests/BluetoothDeviceRowLayoutTests.swift`：

```swift
import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// A device row is one line, whatever it is showing. The confirmation of an
/// input device's disconnect and the spinner of an action in flight both live in
/// the row's trailing area, and neither may wrap or push a control out of the
/// 330-point panel — not even for the longest paired-device name this Mac has.
@MainActor
final class BluetoothDeviceRowLayoutTests: XCTestCase {
    func testTheConfirmingRowStaysOnOneLine() async throws {
        let device = BluetoothDevice(
            id: "AA:00:00:00:00:01",
            name: "EDIFIER LolliPods 2022版",
            kind: .peripheral,
            isConnected: true
        )

        for language in [AppLanguage.english, .simplifiedChinese] {
            let plain = try await renderRow(language: language, device: device)
            let confirming = try await renderRow(
                language: language,
                device: device,
                isConfirmingDisconnect: true
            )

            XCTAssertEqual(confirming.width, 330, accuracy: 0.5)
            XCTAssertEqual(
                confirming.height,
                plain.height,
                accuracy: 1,
                "the confirmation must stay on the row's single line in \(language.rawValue)"
            )
        }
    }

    func testTheInFlightRowStaysOnOneLine() async throws {
        let device = BluetoothDevice(
            id: "AA:00:00:00:00:01",
            name: "EDIFIER LolliPods 2022版",
            kind: .audio,
            isConnected: false
        )

        let plain = try await renderRow(language: .english, device: device)
        let connecting = try await renderRow(
            language: .english,
            device: device,
            actionState: .connecting
        )

        XCTAssertEqual(connecting.width, 330, accuracy: 0.5)
        XCTAssertEqual(
            connecting.height,
            plain.height,
            accuracy: 1,
            "an action in flight must stay on the row's single line"
        )
    }

    /// Renders one row at the width the panel gives it: the popover is 330 wide
    /// with 14 points of padding on each side, so the row itself gets 302.
    private func renderRow(
        language: AppLanguage,
        device: BluetoothDevice,
        batteryLevels: [String: BluetoothBatteryLevel] = [:],
        actionState: BluetoothDeviceActionState? = nil,
        isConfirmingDisconnect: Bool = false
    ) async throws -> NSSize {
        let suite = "StatusTrioCoreTests.BluetoothDeviceRow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))

        let view = BluetoothDeviceRow(
            device: device,
            batteryLevels: batteryLevels,
            actionState: actionState,
            isConfirmingDisconnect: isConfirmingDisconnect,
            onPerformAction: {},
            onRequestDisconnect: {},
            onCancelDisconnect: {}
        )
        .padding(14)
        .frame(width: 330)
        .background(Color(white: 0.96))
        .environmentObject(localization)
        .environment(\.colorScheme, .light)

        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        return hosting.fittingSize
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter BluetoothDeviceRowLayoutTests`
Expected: FAIL 编译错误：`extra arguments at positions ... in call`（`BluetoothDeviceRow` 还没有这些参数）。

- [ ] **Step 3: 行视图改成输入驱动**

`Sources/StatusTrioCore/UI/BluetoothDeviceRow.swift` 整体替换为：

```swift
import SwiftUI

/// One paired-device row. The status panel's list and the detail page share it
/// so the two surfaces cannot drift, and a device the report carries no level
/// for simply draws no battery text.
///
/// The row is a pure function of its inputs: which action is in flight (or which
/// failure is on screen), and whether it is currently asking to confirm a
/// disconnect. Both parents hold that confirmation themselves, so the state
/// cannot outlive the surface showing it.
struct BluetoothDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let device: BluetoothDevice
    let batteryLevels: [String: BluetoothBatteryLevel]
    let actionState: BluetoothDeviceActionState?
    let isConfirmingDisconnect: Bool
    let onPerformAction: () -> Void
    let onRequestDisconnect: () -> Void
    let onCancelDisconnect: () -> Void

    var body: some View {
        if isConfirmingDisconnect {
            HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
                leading
                Spacer(minLength: 8)
                Text(localization.string(.bluetoothActionConfirmDisconnect))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(localization.string(.bluetoothActionDisconnect), action: onPerformAction)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                Button(localization.string(.bluetoothActionCancel), action: onCancelDisconnect)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .contain)
        } else {
            Button(action: handleTap) {
                HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
                    leading
                    Spacer(minLength: 8)
                    batteryText
                    statusText
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isActionInFlight)
            .help(actionHelp)
            .accessibilityElement(children: .combine)
            .accessibilityHint(actionHelp)
        }
    }

    private var leading: some View {
        HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
            Image(systemName: BluetoothDeviceRowIcon.symbolName(for: device))
                .frame(width: BluetoothPanelMetrics.iconColumnWidth)
                .foregroundStyle(.secondary)
            Text(device.name)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var batteryText: some View {
        if let level = BluetoothDevicePresentation.batteryLevelText(
            for: device,
            batteryLevels: batteryLevels
        ) {
            Text(level)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch BluetoothDeviceActionPolicy.status(for: device, actionState: actionState) {
        case .connected:
            stateLabel(localization.string(.bluetoothConnected))
        case .notConnected:
            stateLabel(localization.string(.bluetoothNotConnected))
        case .connecting:
            workingLabel(localization.string(.bluetoothStateConnecting))
        case .disconnecting:
            workingLabel(localization.string(.bluetoothStateDisconnecting))
        case .connectFailed:
            failureLabel(localization.string(.bluetoothStateConnectFailed))
        case .disconnectFailed:
            failureLabel(localization.string(.bluetoothStateDisconnectFailed))
        }
    }

    private func stateLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func workingLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityLabel(text)
    }

    private func failureLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(1)
    }

    /// Whether an action is already running for this device. A failure that is
    /// still on screen is not in flight: tapping it retries.
    private var isActionInFlight: Bool {
        switch actionState {
        case .connecting, .disconnecting: true
        case .failed, .none: false
        }
    }

    private var actionHelp: String {
        BluetoothDeviceActionPolicy.action(for: device) == .connect
            ? localization.string(.bluetoothActionConnect)
            : localization.string(.bluetoothActionDisconnect)
    }

    private func handleTap() {
        guard !isActionInFlight else { return }
        if BluetoothDeviceActionPolicy.requiresConfirmation(for: device) {
            onRequestDisconnect()
        } else {
            onPerformAction()
        }
    }
}
```

- [ ] **Step 4: 两个父视图持有确认态并接线**

`Sources/StatusTrioCore/UI/BluetoothDeviceList.swift`：把输入声明改成下面这个顺序（memberwise init 的实参顺序由声明顺序决定，本步骤的调用点按此顺序传参），并加确认态：

```swift
    let devices: [BluetoothDevice]
    let batteryLevels: [String: BluetoothBatteryLevel]
    let actionStates: [String: BluetoothDeviceActionState]
    let options: BluetoothDeviceListOptions
    let onPerformAction: (BluetoothDevice) -> Void

    @State private var confirmingAddress: String?
```

`ForEach` 里的行改为：

```swift
            ForEach(model.visibleDevices) { device in
                let address = BluetoothBatteryReader.normalizedAddress(device.id)
                BluetoothDeviceRow(
                    device: device,
                    batteryLevels: batteryLevels,
                    actionState: actionStates[address],
                    isConfirmingDisconnect: confirmingAddress == address,
                    onPerformAction: {
                        confirmingAddress = nil
                        onPerformAction(device)
                    },
                    onRequestDisconnect: { confirmingAddress = address },
                    onCancelDisconnect: { confirmingAddress = nil }
                )
            }
```

`Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift` 的两处：

概要行 `BluetoothStatusView` 里构造列表处加：

```swift
                BluetoothDeviceList(
                    devices: controller.devices,
                    batteryLevels: controller.batteryLevels,
                    actionStates: controller.deviceActionStates,
                    options: listOptions,
                    onPerformAction: { controller.performDeviceAction(for: $0) }
                )
```

详情页 `BluetoothDeviceListView` 加 `@State private var confirmingAddress: String?`，并把 `section(_:devices:)` 的 `ForEach` 改为：

```swift
            ForEach(devices) { device in
                let address = BluetoothBatteryReader.normalizedAddress(device.id)
                BluetoothDeviceRow(
                    device: device,
                    batteryLevels: controller.batteryLevels,
                    actionState: controller.deviceActionStates[address],
                    isConfirmingDisconnect: confirmingAddress == address,
                    onPerformAction: {
                        confirmingAddress = nil
                        controller.performDeviceAction(for: device)
                    },
                    onRequestDisconnect: { confirmingAddress = address },
                    onCancelDisconnect: { confirmingAddress = nil }
                )
            }
```

- [ ] **Step 5: 运行测试确认通过**

Run: `swift test --filter BluetoothDeviceRowLayoutTests`
Expected: PASS（2 个新用例；确认态与普通态、进行中与普通态的高度一致）。

Run: `swift test`
Expected: PASS，0 failures。

Run: `swift build -c release`
Expected: 构建成功，0 errors。

- [ ] **Step 6: 提交**

```bash
git add Sources/StatusTrioCore/UI/BluetoothDeviceRow.swift \
        Sources/StatusTrioCore/UI/BluetoothDeviceList.swift \
        Sources/StatusTrioCore/UI/BluetoothDeviceListView.swift \
        Tests/StatusTrioCoreTests/BluetoothSummaryLayoutTests.swift
git commit -m "feat(bluetooth): connect or disconnect a device from its row"
```

---

### Task 5: 文档、发布说明与完整验证

**Files:**
- Modify: `docs/bluetooth-status.md`
- Modify: `release-notes/1.3.0/{ar,de,en,es,fr,it,ja,ko,pt-BR,ru,zh-Hans,zh-Hant}.md`

**Interfaces:**
- Consumes: Task 1-4 的最终行为。
- Produces: 行为文档与 12 语言发布说明；本地验证证据。

- [ ] **Step 1: 行为文档补一节**

`docs/bluetooth-status.md` 末尾追加：

```markdown
## Acting on a device from its row

A device row is a button: tapping an unconnected device asks the system to
connect it, and tapping a connected one asks it to disconnect. The request goes
through `IOBluetoothDevice.openConnection()` / `closeConnection()` on a private
queue — those calls are synchronous and can block until the page timeout when a
device is out of range, so they never run on the main thread. Devices are
matched on the normalized address: IOBluetooth keeps reporting the name a device
had before it was renamed, while the report the UI is built from carries the
current one, so names cannot join the two sources.

Nothing here flips a row optimistically. The request only decides whether the
system accepted the command; the row's connection state still comes from the
device report, and the action is considered done only when that report changes.
A request that is refused, and one that is accepted but takes longer than ten
seconds to show up, both become a visible failure for a few seconds and then
clear.

Disconnecting an input device — a keyboard, mouse, trackpad or gamepad — asks
for confirmation in the row itself, because disconnecting the keyboard or mouse
the user is holding would cut them off from their own Mac. The prompt lives in
the row rather than in an alert: the panel is transient, so a modal would close
it. The confirmation is view state, so closing the panel cancels it and an
unconfirmed disconnect is never sent.
```

- [ ] **Step 2: 12 语言发布说明**

`release-notes/1.3.0/en.md` 末尾追加：

```markdown
## Connect or disconnect a device from the panel
- Tapping a paired device in the Bluetooth list now connects it, and tapping a connected one disconnects it. The row shows the request in progress and reports a failure instead of pretending it worked.
- Disconnecting a keyboard, mouse, trackpad or gamepad asks first, in the row itself — disconnecting the one you are holding would leave you without input.
```

`release-notes/1.3.0/zh-Hans.md` 末尾追加：

```markdown
## 在面板里连接或断开设备
- 点按蓝牙列表里已配对的设备即可连接；点按已连接的设备即可断开。行内会显示请求进行中，失败时如实报错，不会假装成功。
- 断开键盘、鼠标、触控板或手柄会先在行内确认——断开你手上正在用的那个会让你失去输入。
```

其余 10 种语言按英文段落翻译，术语取各自 `.lproj`（`bluetooth.action.*` / `bluetooth.state.*` 等 Task 3 新键）与同文件既有小节；每语言只追加一个 `##` 小节，首行 `%VERSION%` / `%BUILD%` 占位标题不得改动。

- [ ] **Step 3: 校验说明与 appcast**

Run: `VERSION=1.3.0 BUILD=27 PUBLISH=false bash scripts/validate-appcast-notes.sh`
Expected: PASS，`12 titles and 12 descriptions, en first`。

- [ ] **Step 4: 本地完整验证**

Run: `swift test`
Expected: PASS，0 failures。

Run: `swift build -c release`
Expected: 构建成功，0 errors。

- [ ] **Step 5: 提交**

```bash
git add docs/bluetooth-status.md release-notes/1.3.0
git commit -m "docs: describe the Bluetooth device actions in the 1.3.0 notes"
```

- [ ] **Step 6: 真机手动验证（必须由人类伙伴执行或确认）**

在没有自动测试覆盖的那部分，必须手动确认：

1. 面板里点一台**未连接**的音频设备 → 行显示「连接中…」→ 约 1 秒内变为「已连接」，且系统音频输出切到该设备。
2. 点同一台设备 → 行显示「断开中…」→ 变为「未连接」；再等 10 秒确认系统没有自动回连。
3. 把一台已连接的键鼠点一下 → 行内出现「要断开吗？[断开][取消]」；点「取消」不做任何动作；再点一次并确认「断开」，键盘/鼠标确实断开。
4. 点一台**不在范围内**的设备（例如关掉耳机）→ 10 秒后显示「连接失败」，随后恢复「未连接」。

- [ ] **Step 7: 请求授权后推送并跑非发布预检**

本改动触及 SwiftUI 绑定与 `@MainActor` 状态，按仓库规则合并前必须预检；预检要求 ref 已在远端，因此这一步**必须先得到人类伙伴的推送授权**。

```bash
branch=$(git rev-parse --abbrev-ref HEAD)
git push -u origin "$branch"

gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref "$branch" \
  -f version=1.3.0 \
  -f build=27 \
  -f publish=false

run_id=$(gh run list --repo lingyired/status-trio --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run_id" --repo lingyired/status-trio --exit-status
```

Expected: 成功，`publish=false` 不产生 Release、不改 `appcast.xml`。

- [ ] **Step 8: 失败时补 CI 兼容性记录**

若 Step 7 失败，把 run ID、失败阶段、根因、修复与验证结果按既有格式写进 `docs/swift-ci-compatibility.md`，重跑 Step 7，再提交该文件。
