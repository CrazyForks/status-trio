# 状态面板设置 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增“状态面板”设置 Tab，让电量、网络、蓝牙和音量可以独立开关；默认蓝牙关闭，开启蓝牙时才申请系统权限。

**Architecture:** `SettingsStore` 保存显示开关和完整排序，`StatusPopoverView` 只渲染两者的交集。新的 `StatusPanelSettingsPane` 负责开关和拖拽，并在蓝牙由关变开时调用 `SystemStatusStore` 启动 CoreBluetooth。

**Tech Stack:** Swift 6、SwiftUI、AppKit、CoreBluetooth、XCTest、Swift Package Manager。

**Spec:** `docs/superpowers/specs/2026-09-15-popup-item-visibility-design.md`

## Global Constraints

- CI 环境必须是 macOS 15、Xcode 16.4、Swift 6.1.2 可编译的代码。
- 不引入 Swift 6.2 或更新版本专属语法。
- 用户可见名称为“状态面板”，英文为 `Status Panel`。
- 电量、网络、音量默认开启；蓝牙默认关闭。
- 显示开关只影响状态面板，不影响菜单栏图标或电量、网络、音量监控器。
- 打开状态面板本身不得启动 `CBCentralManager`。
- 每个任务先写失败测试，再写最小实现，再运行测试，最后提交。

---

## File Structure

- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift`
  - 负责显示开关持久化、默认值、数据清理和可见项目过滤。
- Modify: `Sources/StatusTrioCore/UI/StatusPopoverView.swift`
  - 只渲染 `settings.visiblePopupSections`。
- Modify: `Sources/StatusTrioCore/UI/Settings/SettingsTab.swift`
  - 新增 `.panel` Tab，并保持 Tab 顺序为“基础”之后。
- Create: `Sources/StatusTrioCore/UI/Settings/StatusPanelSettingsPane.swift`
  - 管理显示开关和拖拽排序。
- Modify: `Sources/StatusTrioCore/UI/Settings/BasicsSettingsPane.swift`
  - 移除原有 Popup 排序区域和辅助方法。
- Modify: `Sources/StatusTrioCore/UI/Settings/SettingsDetailView.swift`
  - 将 `.panel` 映射到 `StatusPanelSettingsPane`。
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift`
  - 增加 `settings.tab.panel`。
- Modify: `Sources/StatusTrioCore/Resources/*/Localizable.strings`
  - 增加 Tab 名称并更新状态面板项目标题和说明。
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift`
  - 增加 `setBluetoothEnabled(_:)`，统一蓝牙启动和停止。
- Modify: `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`
  - 覆盖默认值、持久化、清理、可见顺序和 Tab 元数据。
- Modify: `Tests/StatusTrioCoreTests/BluetoothPermissionTimingTests.swift`
  - 覆盖开启和关闭蓝牙时的 monitor 生命周期。

---

### Task 1: 保存显示开关并过滤状态面板

**Files:**
- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusPopoverView.swift:295-322`
- Test: `Tests/StatusTrioCoreTests/SettingsStoreTests.swift:300-346`

**Interfaces:**
- Consumes: `PopupSection`、`SettingsStore.popupSectionOrder`
- Produces:
  - `static let enabledPopupSectionsDefaultsKey: String`
  - `static let defaultEnabledPopupSections: Set<PopupSection>`
  - `@Published private(set) var enabledPopupSections: Set<PopupSection>`
  - `var visiblePopupSections: [PopupSection]`
  - `func setPopupSection(_ section: PopupSection, enabled: Bool)`
  - `static func sanitizedEnabledPopupSections(_ rawValues: [String]?) -> Set<PopupSection>`

- [ ] **Step 1: 写默认值和过滤顺序的失败测试**

在 `SettingsStoreTests` 的 `testPopupSectionOrderDefaultsToBatteryNetworkBluetoothVolume` 后加入：

```swift
func testPopupSectionVisibilityDefaultsToEverythingExceptBluetooth() {
    let store = SettingsStore(defaults: makeSuite().defaults)

    XCTAssertEqual(
        store.enabledPopupSections,
        Set([.battery, .network, .volume])
    )
    XCTAssertEqual(
        store.visiblePopupSections,
        [.battery, .network, .volume]
    )
}

func testPopupSectionVisibilityFiltersWithoutChangingStoredOrder() {
    let suite = makeSuite()
    defer { clear(suite) }

    let first = SettingsStore(defaults: suite.defaults)
    first.setPopupSection(.network, enabled: false)
    first.setPopupSection(.bluetooth, enabled: true)

    XCTAssertEqual(
        first.popupSectionOrder,
        [.battery, .network, .bluetooth, .volume]
    )
    XCTAssertEqual(
        first.visiblePopupSections,
        [.battery, .bluetooth, .volume]
    )

    let second = SettingsStore(defaults: suite.defaults)
    XCTAssertEqual(second.enabledPopupSections, Set([.battery, .bluetooth, .volume]))
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
swift test --filter SettingsStoreTests/testPopupSectionVisibilityDefaultsToEverythingExceptBluetooth
```

Expected: 编译失败，提示 `SettingsStore` 没有 `enabledPopupSections` 或 `visiblePopupSections`。

- [ ] **Step 3: 添加最小数据模型**

在 `SettingsStore` 的 `popupSectionOrderDefaultsKey` 后加入：

```swift
static let enabledPopupSectionsDefaultsKey = "enabledPopupSections"
static let defaultEnabledPopupSections: Set<PopupSection> = [.battery, .network, .volume]
```

在 `popupSectionOrder` 属性后加入：

```swift
@Published private(set) var enabledPopupSections: Set<PopupSection> {
    didSet {
        defaults.set(
            enabledPopupSections.map(\.rawValue).sorted(),
            forKey: Self.enabledPopupSectionsDefaultsKey
        )
    }
}

var visiblePopupSections: [PopupSection] {
    popupSectionOrder.filter { enabledPopupSections.contains($0) }
}
```

在 `movePopupSections(fromOffsets:toOffset:)` 后加入：

```swift
func setPopupSection(_ section: PopupSection, enabled: Bool) {
    if enabled {
        enabledPopupSections.insert(section)
    } else {
        enabledPopupSections.remove(section)
    }
}
```

在 `init` 读取 `storedPopupSectionOrder` 后加入：

```swift
let storedEnabledPopupSections = defaults.stringArray(
    forKey: Self.enabledPopupSectionsDefaultsKey
)
```

在 `init` 最后初始化 `popupSectionOrder` 后加入：

```swift
self.enabledPopupSections = Self.sanitizedEnabledPopupSections(
    storedEnabledPopupSections
)
```

在 `sanitizedPopupSectionOrder` 后加入：

```swift
static func sanitizedEnabledPopupSections(_ rawValues: [String]?) -> Set<PopupSection> {
    guard let rawValues else {
        return defaultEnabledPopupSections
    }
    return Set(rawValues.compactMap(PopupSection.init(rawValue:)))
}
```

- [ ] **Step 4: 让状态面板只渲染可见项目**

将 `StatusPopoverView.summary` 的 `ForEach` 改为：

```swift
ForEach(settings.visiblePopupSections) { section in
    popupSection(section)

    if section != settings.visiblePopupSections.last {
        Divider()
    }
}

if !settings.visiblePopupSections.isEmpty {
    Divider()
}
```

同时删除原来无条件执行的：

```swift
Divider()
```

该位置就是 `ForEach` 与“Settings…”按钮之间的分隔线；保留 Settings 和 Quit 按钮本身。

- [ ] **Step 5: 补数据清理测试**

在 `SettingsStoreTests` 加入：

```swift
func testStoredPopupSectionVisibilityIgnoresUnknownValues() {
    let suite = makeSuite()
    defer { clear(suite) }

    suite.defaults.set(
        ["network", "unknown", "network"],
        forKey: SettingsStore.enabledPopupSectionsDefaultsKey
    )

    let store = SettingsStore(defaults: suite.defaults)

    XCTAssertEqual(store.enabledPopupSections, Set([.network]))
    XCTAssertEqual(store.visiblePopupSections, [.network])
}
```

- [ ] **Step 6: 运行测试并确认通过**

Run:

```bash
swift test --filter SettingsStoreTests
```

Expected: 全部通过。

- [ ] **Step 7: 提交**

```bash
git add Sources/StatusTrioCore/Settings/SettingsStore.swift \
  Sources/StatusTrioCore/UI/StatusPopoverView.swift \
  Tests/StatusTrioCoreTests/SettingsStoreTests.swift
git commit -m "feat: add popup section visibility settings"
```

---

### Task 2: 用蓝牙开关控制权限和监控生命周期

**Files:**
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift:205-208`
- Test: `Tests/StatusTrioCoreTests/BluetoothPermissionTimingTests.swift:27-62`

**Interfaces:**
- Consumes: `BluetoothDeviceController.activate()`、`BluetoothDeviceController.deactivate()`
- Produces: `SystemStatusStore.setBluetoothEnabled(_ enabled: Bool)`

- [ ] **Step 1: 写蓝牙开启和关闭的失败测试**

将 `BluetoothPermissionTimingTests` 的 spy 改为记录停止次数：

```swift
private final class BluetoothStateMonitorSpy: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    let authorization: BluetoothAuthorizationStatus

    init(authorization: BluetoothAuthorizationStatus = .notDetermined) {
        self.authorization = authorization
    }

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }
}
```

在 `testRequestingBluetoothAuthorizationStartsStateMonitor` 后加入：

```swift
func testBluetoothSettingControlsStateMonitorLifecycle() {
    let stateMonitor = BluetoothStateMonitorSpy(authorization: .notDetermined)
    let bluetoothController = BluetoothDeviceController(
        stateMonitor: stateMonitor,
        notificationCenter: NotificationCenter(),
        workspaceNotificationCenter: NotificationCenter()
    )
    let store = SystemStatusStore(
        batteryMonitor: EmptyBatteryMonitorForBluetoothTiming(),
        wifiMonitor: EmptyWiFiMonitorForBluetoothTiming(),
        volumeMonitor: EmptyVolumeMonitorForBluetoothTiming(),
        bluetoothDevices: bluetoothController
    )

    store.setBluetoothEnabled(true)
    XCTAssertEqual(stateMonitor.startCount, 1)

    store.setBluetoothEnabled(false)
    XCTAssertEqual(stateMonitor.stopCount, 1)
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
swift test --filter BluetoothPermissionTimingTests/testBluetoothSettingControlsStateMonitorLifecycle
```

Expected: 编译失败，提示 `SystemStatusStore` 没有 `setBluetoothEnabled`。

- [ ] **Step 3: 添加最小生命周期方法**

将 `SystemStatusStore` 的蓝牙方法改为：

```swift
func requestBluetoothAuthorization() {
    setBluetoothEnabled(true)
}

func setBluetoothEnabled(_ enabled: Bool) {
    guard !hasStopped else { return }
    if enabled {
        bluetoothDevices.activate()
    } else {
        bluetoothDevices.deactivate()
    }
}
```

- [ ] **Step 4: 运行测试并确认通过**

Run:

```bash
swift test --filter BluetoothPermissionTimingTests
```

Expected: 全部通过，包括“仅打开状态面板不启动 CoreBluetooth”。

- [ ] **Step 5: 提交**

```bash
git add Sources/StatusTrioCore/Store/SystemStatusStore.swift \
  Tests/StatusTrioCoreTests/BluetoothPermissionTimingTests.swift
git commit -m "feat: gate Bluetooth permission on panel setting"
```

---

### Task 3: 新增“状态面板”设置 Tab

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Settings/SettingsTab.swift`
- Create: `Sources/StatusTrioCore/UI/Settings/StatusPanelSettingsPane.swift`
- Modify: `Sources/StatusTrioCore/UI/Settings/BasicsSettingsPane.swift:60-65`
- Modify: `Sources/StatusTrioCore/UI/Settings/SettingsDetailView.swift:11-24`
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift:17-29`
- Modify: `Sources/StatusTrioCore/Resources/*/Localizable.strings`
- Test: `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `SettingsStore.visiblePopupSections`、`SettingsStore.setPopupSection(_:enabled:)`、`SystemStatusStore.setBluetoothEnabled(_:)`
- Produces:
  - `SettingsTab.panel`
  - `LocalizationKey.settingsTabPanel`
  - `StatusPanelSettingsPane(store:statusStore:)`

- [ ] **Step 1: 写 Tab 元数据失败测试**

在 `SettingsStoreTests` 的 `testPopupSectionMetadataIncludesBluetooth` 后加入：

```swift
func testStatusPanelTabIsAvailableAfterBasics() {
    XCTAssertEqual(Array(SettingsTab.allCases.prefix(2)), [.basics, .panel])
    XCTAssertEqual(SettingsTab.panel.titleKey, .settingsTabPanel)
    XCTAssertEqual(SettingsTab.panel.systemImage, "rectangle.on.rectangle")
    XCTAssertEqual(SettingsTab.panel.tint, .purple)
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
swift test --filter SettingsStoreTests/testStatusPanelTabIsAvailableAfterBasics
```

Expected: 编译失败，提示 `SettingsTab` 没有 `panel`。

- [ ] **Step 3: 增加 `panel` Tab 定义**

将 `SettingsTab` 改为：

```swift
enum SettingsTab: String, CaseIterable, Identifiable {
    case basics
    case panel
    case menuBar
    case audio
    case battery
    case updates
    case about

    var id: Self { self }

    var titleKey: LocalizationKey {
        switch self {
        case .basics: .settingsTabBasics
        case .panel: .settingsTabPanel
        case .menuBar: .settingsTabMenuBar
        case .audio: .settingsTabAudio
        case .battery: .settingsTabBattery
        case .updates: .settingsUpdatesTitle
        case .about: .settingsTabAbout
        }
    }

    var systemImage: String {
        switch self {
        case .basics: "gearshape"
        case .panel: "rectangle.on.rectangle"
        case .menuBar: "menubar.rectangle"
        case .audio: "hifispeaker"
        case .battery: "battery.100percent"
        case .updates: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .basics: .blue
        case .panel: .purple
        case .menuBar: .indigo
        case .audio: .cyan
        case .battery: .green
        case .updates: .orange
        case .about: .gray
        }
    }
}
```

- [ ] **Step 4: 创建“状态面板”设置视图**

创建 `Sources/StatusTrioCore/UI/Settings/StatusPanelSettingsPane.swift`：

```swift
import AppKit
import SwiftUI

struct StatusPanelSettingsPane: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        PreferencesPane {
            PreferenceRow(
                label: .settingsPopupOrder,
                description: .settingsPopupOrderDescription
            ) {
                List {
                    ForEach(store.popupSectionOrder) { section in
                        HStack(spacing: 8) {
                            Toggle("", isOn: visibilityBinding(for: section))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .accessibilityLabel(localization.string(section.titleKey))

                            popupSectionIcon(section)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            Text(localization.string(section.titleKey))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { source, destination in
                        store.movePopupSections(
                            fromOffsets: source,
                            toOffset: destination
                        )
                    }
                }
                .listStyle(.inset)
                .frame(height: popupListHeight)
            }
        }
    }

    private func visibilityBinding(for section: PopupSection) -> Binding<Bool> {
        Binding(
            get: { store.enabledPopupSections.contains(section) },
            set: { enabled in
                let wasEnabled = store.enabledPopupSections.contains(section)
                store.setPopupSection(section, enabled: enabled)

                guard section == .bluetooth, enabled != wasEnabled else { return }
                if enabled {
                    NSApp.activate()
                }
                statusStore.setBluetoothEnabled(enabled)
            }
        )
    }

    @ViewBuilder
    private func popupSectionIcon(_ section: PopupSection) -> some View {
        if section == .bluetooth {
            BluetoothIcon(size: 18)
        } else {
            Image(systemName: section.systemImage)
        }
    }

    private var popupListHeight: CGFloat {
        min(max(CGFloat(store.popupSectionOrder.count) * 28 + 8, 44), 168)
    }
}
```

- [ ] **Step 5: 从 Basics 移除旧排序区域**

在 `BasicsSettingsPane.body` 中删除：

```swift
Divider()

popupOrderSection
```

保留前面的 `refreshIntervalSection`。同时删除以下三个方法：

```swift
private var popupOrderSection: some View
@ViewBuilder private func popupSectionIcon(_:)
private var popupOrderListHeight: CGFloat
```

- [ ] **Step 6: 接入 `SettingsDetailView`**

在 `SettingsDetailView` 的 switch 中加入：

```swift
case .panel:
    StatusPanelSettingsPane(store: store, statusStore: statusStore)
```

将其放在 `.basics` 和 `.menuBar` 之间。

- [ ] **Step 7: 增加本地化 key**

在 `LocalizationKey` 中加入：

```swift
case settingsTabPanel = "settings.tab.panel"
```

将其放在 `settingsTabBasics` 后面。

- [ ] **Step 8: 更新所有本地化字符串**

在 12 个 `Localizable.strings` 文件中，紧跟 `settings.tab.basics` 后加入 `settings.tab.panel`：

| 语言 | `settings.tab.panel` |
| --- | --- |
| ar | `لوحة الحالة` |
| de | `Statusbereich` |
| en | `Status Panel` |
| es | `Panel de estado` |
| fr | `Panneau d’état` |
| it | `Pannello di stato` |
| ja | `ステータスパネル` |
| ko | `상태 패널` |
| pt-BR | `Painel de status` |
| ru | `Панель состояния` |
| zh-Hans | `状态面板` |
| zh-Hant | `狀態面板` |

同时将现有的 `settings.popup.order` 和 `settings.popup.order.description` 替换为：

| 语言 | `settings.popup.order` | `settings.popup.order.description` |
| --- | --- | --- |
| ar | `عناصر لوحة الحالة` | `اختر العناصر التي تظهر في لوحة الحالة واسحب لتغيير ترتيبها.` |
| de | `Angezeigte Elemente` | `Wähle aus, welche Elemente im Statusbereich erscheinen, und ziehe sie, um die Reihenfolge zu ändern.` |
| en | `Displayed Items` | `Choose which items appear in the status panel and drag to change their order.` |
| es | `Elementos mostrados` | `Elige qué elementos aparecen en el panel de estado y arrástralos para cambiar su orden.` |
| fr | `Éléments affichés` | `Choisissez les éléments affichés dans le panneau d’état, puis faites-les glisser pour modifier leur ordre.` |
| it | `Elementi mostrati` | `Scegli quali elementi appaiono nel pannello di stato e trascinali per cambiarne l’ordine.` |
| ja | `表示項目` | `ステータスパネルに表示する項目を選択し、ドラッグして順序を変更します。` |
| ko | `표시 항목` | `상태 패널에 표시할 항목을 선택하고 드래그하여 순서를 변경하십시오.` |
| pt-BR | `Itens exibidos` | `Escolha quais itens aparecem no painel de status e arraste para alterar a ordem.` |
| ru | `Отображаемые элементы` | `Выберите элементы, отображаемые на панели состояния, и перетаскивайте их, чтобы изменить порядок.` |
| zh-Hans | `显示项目` | `选择状态面板显示的项目，并拖动调整顺序。` |
| zh-Hant | `顯示項目` | `選擇狀態面板顯示的項目，並拖曳調整順序。` |

- [ ] **Step 9: 运行测试并确认通过**

Run:

```bash
swift test --filter SettingsStoreTests/testStatusPanelTabIsAvailableAfterBasics
swift test --filter LocalizationTests
swift test --filter SettingsTabLoadingTests
```

Expected: 全部通过。

- [ ] **Step 10: 提交**

```bash
git add Sources/StatusTrioCore/UI/Settings/SettingsTab.swift \
  Sources/StatusTrioCore/UI/Settings/StatusPanelSettingsPane.swift \
  Sources/StatusTrioCore/UI/Settings/BasicsSettingsPane.swift \
  Sources/StatusTrioCore/UI/Settings/SettingsDetailView.swift \
  Sources/StatusTrioCore/Localization/LocalizationKey.swift \
  Sources/StatusTrioCore/Resources \
  Tests/StatusTrioCoreTests/SettingsStoreTests.swift
git commit -m "feat: add status panel settings tab"
```

---

### Task 4: 完整验证和 CI 预检

**Files:**
- Verify: 全部修改文件

**Interfaces:**
- Consumes: 前三个任务完成后的 `main` 分支
- Produces: 完整测试、release build 和非发布 release workflow 结果

- [ ] **Step 1: 运行完整测试**

```bash
swift test
```

Expected: 全部测试通过。

- [ ] **Step 2: 运行 release build**

```bash
swift build -c release
```

Expected: `Build complete!`

- [ ] **Step 3: 推送 `main`**

```bash
git status --short --branch
git push origin main
```

Expected: `main` 已同步到 `origin/main`。

- [ ] **Step 4: 运行非发布 release workflow 预检**

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref main \
  -f version=1.1.1 \
  -f build=9 \
  -f publish=false
```

Expected: 命令输出 workflow run URL。

- [ ] **Step 5: 等待 workflow 并确认结果**

先获取 run id：

```bash
gh run list \
  --repo lingyired/status-trio \
  --workflow release.yml \
  --limit 1 \
  --json databaseId,headBranch,status,conclusion,createdAt
```

然后用上一步返回的 `databaseId` 执行：

```bash
gh run watch <databaseId> \
  --repo lingyired/status-trio \
  --exit-status
```

Expected: workflow 成功，测试、Ad-hoc 签名、DMG 创建和 artifact 上传均通过；不得创建 GitHub Release 或更新 appcast。

- [ ] **Step 6: 确认工作区**

```bash
git status --short --branch
```

Expected: 除原本未跟踪的截图文件外，没有未提交改动。
