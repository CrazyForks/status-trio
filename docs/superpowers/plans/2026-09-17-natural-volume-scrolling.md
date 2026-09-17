# 自然滚动音量调节 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用默认关闭的“自然滚动”开关替代旧的音量滚动方向选择，使开关开启时鼠标和触控板物理上滚都增大音量，关闭时沿用系统报告的滚动方向。

**Architecture:** `SettingsStore` 保存新的布尔偏好；`PopupVolumeScrollAdjustment` 只负责把事件增量转换为音量增量；`StatusBarController` 在滚轮事件路径上传入该偏好；设置面板用新的开关行替换旧的 Up/Down 菜单行。旧方向类型和持久化值保留，但不再参与运行时计算。

**Tech Stack:** Swift 6、SwiftUI、AppKit `NSEvent`、XCTest、Swift Package Manager。

**Spec:** `docs/superpowers/specs/2026-09-17-natural-volume-scrolling-design.md`

## Global Constraints

- 新设置默认值为 `false`。
- 开启自然滚动时，物理上滚在鼠标和触控板上都增大音量。
- 关闭自然滚动时，直接使用 `NSEvent.scrollingDeltaY` 的系统报告方向。
- 不检测或特殊兼容 MOS。
- 旧的 `PopupVolumeScrollDirection` 类型和持久化字段保留，但生产路径不再读取。
- 新本地化文案必须覆盖 12 种语言。
- 保持 Swift 6.1/Xcode 16.4 CI 兼容，不使用 Swift 6.2 特性。
- 合并前运行 `swift test`、`swift build -c release` 和非发布 release workflow 预检。

---

### Task 1: 添加 `naturalVolumeScrolling` 设置

**Files:**
- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift:42-47`
- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift:254-261`
- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift:383-455`
- Test: `Tests/StatusTrioCoreTests/SettingsStoreTests.swift:360-430`

**Interfaces:**
- Consumes: existing `SettingsStore` persistence helpers and test helpers `makeSuite()`, `clear(_:)`.
- Produces: `SettingsStore.defaultPopupVolumeNaturalScrolling: Bool`, `SettingsStore.popupVolumeNaturalScrollingDefaultsKey: String`, `SettingsStore.popupVolumeNaturalScrolling: Bool`.

- [ ] **Step 1: 写失败的设置测试**

Replace the three existing popup-volume tests in `Tests/StatusTrioCoreTests/SettingsStoreTests.swift` with:

```swift
    func testPopupVolumeScrollDefaultsToEverywhereSystemDirectionAndNaturalScrollingOff() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertTrue(store.popupScrollAdjustsVolume)
        XCTAssertEqual(store.popupVolumeScrollScope, .panel)
        XCTAssertEqual(store.popupVolumeScrollDirection, .up)
        XCTAssertFalse(store.popupVolumeNaturalScrolling)
    }

    func testPopupVolumeScrollChoicesPersistAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.popupScrollAdjustsVolume = false
        first.popupVolumeScrollScope = .volumeControl
        first.popupVolumeScrollDirection = .down
        first.popupVolumeNaturalScrolling = true

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(second.popupScrollAdjustsVolume)
        XCTAssertEqual(second.popupVolumeScrollScope, .volumeControl)
        XCTAssertEqual(second.popupVolumeScrollDirection, .down)
        XCTAssertTrue(second.popupVolumeNaturalScrolling)
    }

    func testPopupVolumeNaturalScrollingFallsBackToOffForNonBooleanStoredValue() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(
            "yes",
            forKey: SettingsStore.popupVolumeNaturalScrollingDefaultsKey
        )

        let store = SettingsStore(defaults: suite.defaults)

        XCTAssertFalse(store.popupVolumeNaturalScrolling)
    }
```

Keep `testUnknownStoredPopupVolumeScrollValuesFallBackToDefaults()` and update it to also verify the new setting:

```swift
        XCTAssertEqual(store.popupVolumeScrollScope, .panel)
        XCTAssertEqual(store.popupVolumeScrollDirection, .up)
        XCTAssertFalse(store.popupVolumeNaturalScrolling)
```

- [ ] **Step 2: 运行测试，确认先失败**

Run:

```bash
swift test --filter SettingsStoreTests
```

Expected: compile failure because `SettingsStore` has no member `popupVolumeNaturalScrolling` or `popupVolumeNaturalScrollingDefaultsKey`.

- [ ] **Step 3: 添加设置存储**

In `Sources/StatusTrioCore/Settings/SettingsStore.swift`, add after `defaultPopupVolumeScrollDirection`:

```swift
    static let popupVolumeNaturalScrollingDefaultsKey = "popupVolumeNaturalScrolling"
    static let defaultPopupVolumeNaturalScrolling = false
```

Add after the `popupVolumeScrollDirection` property:

```swift
    @Published var popupVolumeNaturalScrolling: Bool {
        didSet {
            defaults.set(
                popupVolumeNaturalScrolling,
                forKey: Self.popupVolumeNaturalScrollingDefaultsKey
            )
        }
    }
```

At the end of the initializer, after assigning `popupVolumeScrollDirection`, add:

```swift
        self.popupVolumeNaturalScrolling = defaults.object(
            forKey: Self.popupVolumeNaturalScrollingDefaultsKey
        ) as? Bool ?? Self.defaultPopupVolumeNaturalScrolling
```

- [ ] **Step 4: 运行设置测试**

Run:

```bash
swift test --filter SettingsStoreTests
```

Expected: all `SettingsStoreTests` pass.

- [ ] **Step 5: 提交**

```bash
git add Sources/StatusTrioCore/Settings/SettingsStore.swift Tests/StatusTrioCoreTests/SettingsStoreTests.swift
git commit -m "feat: add natural volume scrolling setting"
```

---

### Task 2: 按开关选择事件归一化方式

**Files:**
- Modify: `Sources/StatusTrioCore/UI/PopupVolumeScrollAdjustment.swift:7-23`
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift:430-435`
- Test: `Tests/StatusTrioCoreTests/PopupVolumeScrollAdjustmentTests.swift`

**Interfaces:**
- Consumes: `SettingsStore.popupVolumeNaturalScrolling: Bool` from Task 1.
- Produces: `PopupVolumeScrollAdjustment.volumeDelta(deltaY:isPrecise:isDirectionInverted:usesNaturalScrolling:) -> Double?`.

- [ ] **Step 1: 重写失败的方向测试**

Replace `Tests/StatusTrioCoreTests/PopupVolumeScrollAdjustmentTests.swift` with:

```swift
import XCTest
@testable import StatusTrioCore

final class PopupVolumeScrollAdjustmentTests: XCTestCase {
    private let adjustment = PopupVolumeScrollAdjustment()

    func testNaturalScrollingRaisesVolumeForPhysicalScrollUpWithSystemNaturalScrolling() throws {
        // The system reports a negative value after natural-scrolling inversion.
        let delta = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: -4,
                isPrecise: true,
                isDirectionInverted: true,
                usesNaturalScrolling: true
            )
        )

        XCTAssertEqual(delta, 0.008, accuracy: 0.000_001)
    }

    func testNaturalScrollingRaisesVolumeForPhysicalScrollUpWithoutSystemNaturalScrolling() throws {
        let delta = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 4,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: true
            )
        )

        XCTAssertEqual(delta, 0.008, accuracy: 0.000_001)
    }

    func testNaturalScrollingOffUsesSystemReportedDirection() throws {
        let naturalSystem = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: -4,
                isPrecise: true,
                isDirectionInverted: true,
                usesNaturalScrolling: false
            )
        )
        XCTAssertEqual(naturalSystem, -0.008, accuracy: 0.000_001)

        let classicSystem = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 4,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: false
            )
        )
        XCTAssertEqual(classicSystem, 0.008, accuracy: 0.000_001)
    }

    func testNaturalScrollingOffMatchesTheOriginalRawDeltaMapping() throws {
        let negative = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: -2.5,
                isPrecise: true,
                isDirectionInverted: true,
                usesNaturalScrolling: false
            )
        )
        XCTAssertEqual(negative, -0.005, accuracy: 0.000_001)

        let positive = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 2.5,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: false
            )
        )
        XCTAssertEqual(positive, 0.005, accuracy: 0.000_001)
    }

    func testPreciseScrollKeepsFractionalVolumeWithoutStepping() throws {
        let first = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 1,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: false
            )
        )
        let second = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 9,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: false
            )
        )

        XCTAssertEqual(first + second, 0.02, accuracy: 0.000_001)
    }

    func testDiscreteWheelScrollUsesLineDeltaAsStepCount() throws {
        let increase = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 1,
                isPrecise: false,
                isDirectionInverted: false,
                usesNaturalScrolling: false
            )
        )
        XCTAssertEqual(increase, 0.02, accuracy: 0.000_001)

        let decrease = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: -2,
                isPrecise: false,
                isDirectionInverted: false,
                usesNaturalScrolling: false
            )
        )
        XCTAssertEqual(decrease, -0.04, accuracy: 0.000_001)
    }

    func testInvalidAndZeroDeltasAreIgnored() {
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: .nan,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: true
            )
        )
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: .infinity,
                isPrecise: true,
                isDirectionInverted: true,
                usesNaturalScrolling: false
            )
        )
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: -.infinity,
                isPrecise: false,
                isDirectionInverted: false,
                usesNaturalScrolling: true
            )
        )
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: 0,
                isPrecise: true,
                isDirectionInverted: false,
                usesNaturalScrolling: true
            )
        )
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: 0,
                isPrecise: false,
                isDirectionInverted: true,
                usesNaturalScrolling: false
            )
        )
    }
}
```

- [ ] **Step 2: 运行测试，确认先失败**

Run:

```bash
swift test --filter PopupVolumeScrollAdjustmentTests
```

Expected: compile failure because `volumeDelta` still requires `direction:` and the tests pass `usesNaturalScrolling:`.

- [ ] **Step 3: 实现新的归一化规则并接线**

Replace `PopupVolumeScrollAdjustment.volumeDelta` in `Sources/StatusTrioCore/UI/PopupVolumeScrollAdjustment.swift` with:

```swift
    func volumeDelta(
        deltaY: Double,
        isPrecise: Bool,
        isDirectionInverted: Bool,
        usesNaturalScrolling: Bool
    ) -> Double? {
        guard deltaY.isFinite, deltaY != 0 else { return nil }

        let volumePerUnit = isPrecise
            ? Self.preciseVolumePerPoint
            : Self.discreteVolumePerLine
        let scrollUpDelta = usesNaturalScrolling
            ? (isDirectionInverted ? -deltaY : deltaY)
            : deltaY
        return scrollUpDelta * volumePerUnit
    }
```

In `Sources/StatusTrioCore/UI/StatusBarController.swift`, replace the call argument:

```swift
            direction: settings.popupVolumeScrollDirection
```

with:

```swift
            usesNaturalScrolling: settings.popupVolumeNaturalScrolling
```

- [ ] **Step 4: 运行单元测试**

Run:

```bash
swift test --filter PopupVolumeScrollAdjustmentTests
```

Expected: all adjustment tests pass.

- [ ] **Step 5: 提交**

```bash
git add Sources/StatusTrioCore/UI/PopupVolumeScrollAdjustment.swift Sources/StatusTrioCore/UI/StatusBarController.swift Tests/StatusTrioCoreTests/PopupVolumeScrollAdjustmentTests.swift
git commit -m "fix: normalize natural volume scrolling"
```

---

### Task 3: 用自然滚动开关替换方向菜单

**Files:**
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift:33-43`
- Modify: `Sources/StatusTrioCore/Resources/ar.lproj/Localizable.strings:146-153`
- Modify: `Sources/StatusTrioCore/Resources/de.lproj/Localizable.strings:146-153`
- Modify: `Sources/StatusTrioCore/Resources/en.lproj/Localizable.strings:146-153`
- Modify: `Sources/StatusTrioCore/Resources/es.lproj/Localizable.strings:146-153`
- Modify: `Sources/StatusTrioCore/Resources/fr.lproj/Localizable.strings:146-153`
- Modify: `Sources/StatusTrioCore/Resources/it.lproj/Localizable.strings:146-153`
- Modify: `Sources/StatusTrioCore/Resources/ja.lproj/Localizable.strings:146-153`
- Modify: `Sources/StatusTrioCore/Resources/ko.lproj/Localizable.strings:146-153`
- Modify: `Sources/StatusTrioCore/Resources/pt-BR.lproj/Localizable.strings:146-153`
- Modify: `Sources/StatusTrioCore/Resources/ru.lproj/Localizable.strings:146-153`
- Modify: `Sources/StatusTrioCore/Resources/zh-Hans.lproj/Localizable.strings:146-153`
- Modify: `Sources/StatusTrioCore/Resources/zh-Hant.lproj/Localizable.strings:146-153`
- Modify: `Sources/StatusTrioCore/UI/Settings/PopoverSectionView.swift:82-132`
- Test: `Tests/StatusTrioCoreTests/LocalizationTests.swift`
- Test: `Tests/StatusTrioCoreTests/SettingsViewTests.swift`

**Interfaces:**
- Consumes: `SettingsStore.popupVolumeNaturalScrolling` binding from Task 1.
- Produces: `LocalizationKey.settingsPopupVolumeScrollNatural` and `LocalizationKey.settingsPopupVolumeScrollNaturalDescription`; no new public Swift types.

- [ ] **Step 1: 添加本地化键，先让现有全语言测试失败**

In `Sources/StatusTrioCore/Localization/LocalizationKey.swift`, add after the scope cases:

```swift
    case settingsPopupVolumeScrollNatural = "settings.popup.volumeScroll.natural"
    case settingsPopupVolumeScrollNaturalDescription = "settings.popup.volumeScroll.natural.description"
```

Run:

```bash
swift test --filter LocalizationTests.testEveryLanguageHasEveryNonEmptyKey
```

Expected: every language fails for the two new keys.

- [ ] **Step 2: 补齐 12 种语言文案**

Insert the following two lines after `settings.popup.volumeScroll.scope.volumeControl` in each matching `.strings` file:

```text
settings.popup.volumeScroll.natural
settings.popup.volumeScroll.natural.description
```

Use these exact values:

| File | Title value | Description value |
| --- | --- | --- |
| `ar.lproj` | `التمرير الطبيعي` | `عند التشغيل، يؤدي التمرير لأعلى بالماوس أو لوحة التتبع إلى زيادة مستوى الصوت. عند الإيقاف، يتبع مستوى الصوت اتجاه التمرير في النظام.` |
| `de.lproj` | `Natürliches Scrollen` | `Wenn aktiviert, erhöht Scrollen nach oben mit Maus oder Trackpad die Lautstärke. Wenn deaktiviert, folgt die Lautstärke der System-Scrollrichtung.` |
| `en.lproj` | `Natural Scrolling` | `When on, scrolling up on a mouse or trackpad increases volume. When off, volume follows the system's scrolling direction.` |
| `es.lproj` | `Desplazamiento natural` | `Si está activado, desplazarse hacia arriba con el ratón o el trackpad sube el volumen. Si está desactivado, el volumen sigue la dirección de desplazamiento del sistema.` |
| `fr.lproj` | `Défilement naturel` | `Lorsque cette option est activée, un défilement vers le haut avec la souris ou le trackpad augmente le volume. Sinon, le volume suit le sens de défilement du système.` |
| `it.lproj` | `Scorrimento naturale` | `Se attivo, scorrendo verso l’alto con mouse o trackpad il volume aumenta. Se disattivo, il volume segue la direzione di scorrimento del sistema.` |
| `ja.lproj` | `ナチュラルスクロール` | `オンにすると、マウスまたはトラックパッドの上方向スクロールで音量が上がります。オフでは、システムのスクロール方向に従います。` |
| `ko.lproj` | `자연스러운 스크롤` | `켜면 마우스나 트랙패드에서 위로 스크롤할 때 볼륨이 커집니다. 끄면 시스템의 스크롤 방향을 따릅니다.` |
| `pt-BR.lproj` | `Rolagem natural` | `Quando ativado, rolar para cima com o mouse ou trackpad aumenta o volume. Quando desativado, o volume segue a direção de rolagem do sistema.` |
| `ru.lproj` | `Естественная прокрутка` | `Если включено, прокрутка вверх мышью или трекпадом увеличивает громкость. Если выключено, громкость следует направлению прокрутки системы.` |
| `zh-Hans.lproj` | `自然滚动` | `开启后，鼠标和触控板上滚都会增大音量；关闭后，音量跟随系统的滚动方向。` |
| `zh-Hant.lproj` | `自然捲動` | `開啟後，滑鼠和觸控板上滑都會提高音量；關閉後，音量跟隨系統的捲動方向。` |

For example, `en.lproj` receives exactly:

```text
"settings.popup.volumeScroll.natural" = "Natural Scrolling";
"settings.popup.volumeScroll.natural.description" = "When on, scrolling up on a mouse or trackpad increases volume. When off, volume follows the system's scrolling direction.";
```

- [ ] **Step 3: 运行本地化测试**

Run:

```bash
swift test --filter LocalizationTests
```

Expected: all localization tests pass.

- [ ] **Step 4: 替换设置行**

In `Sources/StatusTrioCore/UI/Settings/PopoverSectionView.swift`, replace the `SettingsMenuRow` that uses `.settingsPopupVolumeScrollDirection` with:

```swift
                SettingsToggleRow(
                    symbol: "arrow.up.arrow.down",
                    tint: .indigo,
                    title: localization.string(.settingsPopupVolumeScrollNatural),
                    subtitle: localization.string(.settingsPopupVolumeScrollNaturalDescription),
                    isOn: $store.popupVolumeNaturalScrolling
                )
```

Delete the now-unused `scrollDirectionLabel(_:)` helper at the bottom of the view.

- [ ] **Step 5: 运行设置视图测试**

Run:

```bash
swift test --filter SettingsViewTests
```

Expected: all settings view hosting tests pass.

- [ ] **Step 6: 提交**

```bash
git add Sources/StatusTrioCore/Localization/LocalizationKey.swift Sources/StatusTrioCore/Resources/*/Localizable.strings Sources/StatusTrioCore/UI/Settings/PopoverSectionView.swift
git commit -m "feat: add natural scrolling preference UI"
```

---

### Task 4: 完整验证与预检

**Files:**
- Verify only; no source changes expected.

**Interfaces:**
- Consumes: all changes from Tasks 1-3.
- Produces: green local test/build results and non-publishing release workflow preflight.

- [ ] **Step 1: 运行完整测试**

Run:

```bash
swift test
```

Expected: `Test run with 96 tests` or more, 0 failures.

- [ ] **Step 2: 运行 release 构建**

Run:

```bash
swift build -c release
```

Expected: `Build complete!`.

- [ ] **Step 3: 检查差异和分支状态**

Run:

```bash
git diff --check
git status --short --branch
```

Expected: no whitespace errors and a clean branch.

- [ ] **Step 4: 推送预检分支**

Run:

```bash
git push -u origin codex/natural-volume-scrolling
```

Expected: branch is available on `lingyired/status-trio`.

- [ ] **Step 5: 运行非发布 release workflow**

Run:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref codex/natural-volume-scrolling \
  -f version=1.2.0 \
  -f build=9 \
  -f publish=false
```

Capture and wait for the run:

```bash
RUN_ID="$(
  gh run list \
    --repo lingyired/status-trio \
    --workflow release.yml \
    --branch codex/natural-volume-scrolling \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId'
)"
gh run watch "$RUN_ID" --repo lingyired/status-trio --exit-status
```

Expected: workflow succeeds and does not publish a release or appcast item.
