# Continuous Dock Charging Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给用户主动选择的 Dock 图标增加持续充电光尾，在菜单栏与 Dock 同时播放时实测 Status Trio 平均 CPU 不超过 3%。

**Architecture:** 复用现有 20 fps `ChargingEffectClock`、相位策略和 Dock 渲染器；Dock 只取偶数稳态步形成 10 fps。用独立开关控制持续播放，独立有界帧缓存保存一个 Dock 状态的 18 帧。保留原有 Dock burst，先测当前 `applicationIconImage` 路径，未达预算才降到 5 fps；若仍失败则停止交付并另立 `NSDockTile.contentView` 原型计划。

**Tech Stack:** Swift 6、SwiftUI、AppKit、CoreGraphics、Combine、Swift Testing、Swift Package Manager。

**Spec:** `docs/superpowers/specs/2026-09-24-continuous-dock-charging-animation-design.md`

## Global Constraints

- 工作目录是 `.worktrees/charging-effects`，分支是 `feature/charging-effects`。起点已有「测试充电动画」的未提交改动；先 `git status --short`，保留这些改动，不清理工作树。
- CI 接受环境：`macos-26`、Xcode `26.6`、Swift `6.3.3`；应用必须用 macOS 26 SDK 或更新版本构建。
- 现有菜单栏 20 fps、Dock 插电 6 帧/0.6 秒与电量跳变 3 帧/0.3 秒、共享相位和所有停止条件都不能退化。
- Dock 持续动画初始为 10 fps（20 fps 相位每两步取一次），新选项默认关闭；仅 `.dock` / `.both` 真正启用。
- 新增设置文案覆盖 ar、de、en、es、fr、it、ja、ko、pt-BR、ru、zh-Hans、zh-Hant；不加第三方依赖。
- Swift 改动提交前运行 `swift test`、`swift build -c release`；合并/发布前做一次 `publish=false` release workflow。失败的 Actions 记录写入 `docs/swift-ci-compatibility.md`。

## Review Focus

- 设置窗口临时唤出 Dock、图标位置仍为 `.menuBar`：静态 Dock 可以显示，但没有持续相位更新（Task 3）。
- `@Published` 在存储前发值、burst 与 steady 同一 tick 交替发布：burst 优先，无单帧静态闪烁或稳态插帧（Task 3）。
- 外观、图标选项、电量、网络或音量在动画中变化：缓存失效，下一帧用新状态且保持动画相位（Task 2–3）。
- 减少动态效果、息屏、拔电、关开关及隐藏 Dock：立即恢复静态图，隐藏期间不渲染（Task 3）。
- 心跳倍率从 1.35 回到 1：不能复用上一倍率的帧，也不能让缓存无限增长（Task 2）。

---

### Task 1: Dock 独立设置与本地化

**Files:**
- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift`
- Modify: `Sources/StatusTrioCore/UI/Settings/BatterySectionView.swift`
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift`
- Modify: `Sources/StatusTrioCore/Resources/{ar,de,en,es,fr,it,ja,ko,pt-BR,ru,zh-Hans,zh-Hant}.lproj/Localizable.strings`
- Modify: `Tests/StatusTrioCoreTests/ChargingEffectSettingsTests.swift`
- Modify: `Tests/StatusTrioCoreTests/ChargingEffectLocalizationTests.swift`

**Interfaces:**
- Produces: `SettingsStore.animatesDockChargingContinuously: Bool` and `SettingsStore.animatesDockChargingContinuouslyDefaultsKey = "animatesDockChargingContinuously"`.
- Produces: localization cases `settingsBatteryDockChargingEffect` and `settingsBatteryDockChargingEffectDescription`; existing `showsChargingEffect` remains the master effect switch.

- [ ] **Step 1: Add failing persistence test.** In `ChargingEffectSettingsTests`, create an isolated `UserDefaults` suite; assert missing key loads `false`, setting `true` persists, and a fresh store restores `true`. Also assert changing this key does not change `showsChargingEffect` or `testsChargingEffect`.

```swift
#expect(!first.animatesDockChargingContinuously)
first.animatesDockChargingContinuously = true
#expect(defaults.bool(forKey: SettingsStore.animatesDockChargingContinuouslyDefaultsKey))
#expect(SettingsStore(defaults: defaults).animatesDockChargingContinuously)
```

- [ ] **Step 2: Run `swift test --filter ChargingEffectSettingsTests`.** Expected: compile failure because the property does not exist.
- [ ] **Step 3: Add the stored `@Published` setting**, initializing it with `defaults.object(forKey:) as? Bool ?? false` and writing it in `didSet`, following `showsChargingEffect` immediately above it. Add a `SettingsToggleRow` below the main charging effect toggle and above the dev-only test switch; show it only when `store.showsChargingEffect` is true. The row binds directly to `$store.animatesDockChargingContinuously`.

```swift
@Published var animatesDockChargingContinuously: Bool {
    didSet {
        defaults.set(
            animatesDockChargingContinuously,
            forKey: Self.animatesDockChargingContinuouslyDefaultsKey
        )
    }
}

SettingsToggleRow(
    symbol: "dock.rectangle",
    tint: .green,
    title: localization.string(.settingsBatteryDockChargingEffect),
    subtitle: localization.string(.settingsBatteryDockChargingEffectDescription),
    isOn: $store.animatesDockChargingContinuously
)
```

- [ ] **Step 4: Add both keys to `LocalizationKey` and all 12 `.strings` files.** Use the following two values, in order, for `settings.battery.dockChargingEffect` and `settings.battery.dockChargingEffectDescription`. Extend `ChargingEffectLocalizationTests`' key collection and run the existing parity suite.

| Locale | Title | Description |
|---|---|---|
| ar | تحريك أيقونة Dock باستمرار | يستمر أثناء الشحن؛ وقد يزيد استخدام المعالج. |
| de | Dock-Symbol durchgehend animieren | Läuft während des Ladens; kann die CPU-Auslastung erhöhen. |
| en | Animate Dock icon continuously | Plays while charging; may increase CPU usage. |
| es | Animar continuamente el icono del Dock | Se reproduce durante la carga; puede aumentar el uso de CPU. |
| fr | Animer l’icône du Dock en continu | S’anime pendant la charge ; peut augmenter l’utilisation du processeur. |
| it | Anima continuamente l’icona nel Dock | Si anima durante la ricarica; può aumentare l’uso della CPU. |
| ja | Dock アイコンを常時アニメーション表示 | 充電中に再生します。CPU 使用率が上がる場合があります。 |
| ko | Dock 아이콘 계속 애니메이션 | 충전 중 계속 재생되며 CPU 사용량이 증가할 수 있습니다. |
| pt-BR | Animar o ícone do Dock continuamente | Reproduz durante o carregamento; pode aumentar o uso da CPU. |
| ru | Непрерывная анимация значка Dock | Воспроизводится во время зарядки; может повысить нагрузку на ЦП. |
| zh-Hans | 持续播放 Dock 充电动画 | 充电时持续播放，可能增加 CPU 占用。 |
| zh-Hant | 持續播放 Dock 充電動畫 | 充電時持續播放，可能增加 CPU 使用率。 |
- [ ] **Step 5: Run `swift test --filter ChargingEffectSettingsTests` and `swift test --filter LocalizationParityTests`.** Expected: PASS。完成 `swift test`、`swift build -c release` 后只提交本任务文件，保留现有测试开关的未提交改动范围；若文件与该改动交叉，暂缓提交到最后统一整理，不能用 `git add .` 混入其它文件。

### Task 2: 稳态相位 key 与 18 帧有界缓存

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift`
- Modify: `Tests/StatusTrioCoreTests/ChargingEffectRenderCacheTests.swift`
- Modify: `Tests/StatusTrioCoreTests/DockIconRenderCacheTests.swift`

**Interfaces:**
- Consumes: `DockIconRenderKey(status:options:connectionOptions:volumeOptions:bluetoothAudioOptions:backgroundStyle:phase:)` and `ChargingEffectPhase`.
- Produces: `@MainActor final class DockChargingFrameCache` with `func image(for baseKey: DockIconRenderKey, phase: ChargingEffectPhase) -> NSImage?`, `func store(_ image: NSImage, for baseKey: DockIconRenderKey, phase: ChargingEffectPhase)`, `func reset()` and `var count: Int { get }` for tests. The caller supplies `baseKey` built with `phase: nil`; a changed base key or `heartbeatMultiplier` empties the 18-frame group.

- [ ] **Step 1: Replace the old steady-key test with a failing key test.** `dockKey` built with steady steps 2 and 4 must differ; two identical steady phases must dedupe; `phase: nil` must still equal an omitted phase.

```swift
let first = dockKey(phase: .init(step: 2, stepsPerCycle: 36, kind: .steady))
let second = dockKey(phase: .init(step: 4, stepsPerCycle: 36, kind: .steady))
#expect(first != second)
```

- [ ] **Step 2: Add failing cache tests** with 18 distinct even steps, an appearance/status base-key change, and multiplier `1` → `1.35` → `1`. Each change must miss the old image; `count` never exceeds 18. Assert `reset()` sets `count == 0`.
- [ ] **Step 3: Run `swift test --filter ChargingEffectRenderCacheTests` and `swift test --filter DockIconRenderCacheTests`.** Expected: the key assertion fails and `DockChargingFrameCache` does not compile.
- [ ] **Step 4: Change `DockIconRenderKey` to retain the supplied phase** (`self.phase = phase`). Add `DockChargingFrameCache` beside `DockIconImageCache`; keep only one base key and one multiplier at a time. Insert lazily on a miss, evict oldest if a malformed or future phase sequence would exceed 18 images. Keep the existing 12-entry static/burst cache untouched.

```swift
private var baseKey: DockIconRenderKey?
private var heartbeatMultiplier: Double?
private var frames: [ChargingEffectPhase: NSImage] = [:]
var count: Int { frames.count }
```

- [ ] **Step 5: Re-run both focused suites, then `swift test` and `swift build -c release`.** Expected: PASS。单独查看 `git diff --check` 和缓存实例的内存生命周期；只提交该任务文件。

### Task 3: 控制器订阅、burst 优先与立即停止

**Files:**
- Modify: `Sources/StatusTrioCore/App/AppIconController.swift`
- Modify: `Sources/StatusTrioCore/UI/Icon/ChargingEffectClock.swift`
- Modify: `Tests/StatusTrioCoreTests/ChargingEffectControllerTests.swift`
- Modify: `Tests/StatusTrioCoreTests/AppIconControllerTests.swift` (test harness only)

**Interfaces:**
- Consumes: `SettingsStore.animatesDockChargingContinuously`, `DockChargingFrameCache`, `ChargingEffectClock.phase`, `ChargingEffectClock.dockPhase`.
- Produces: controller-computed effective Dock phase. Burst wins; otherwise, steady phase is accepted only when `showsChargingEffect && animatesDockChargingContinuously && currentPlacement.showsDockIcon && isDockTileVisible` and the phase is an even step. All other cases use `nil`.

- [ ] **Step 1: Extend `AppIconControllerHarness`** with `initialAnimatesDockChargingContinuously: Bool = false` and set it before `controller.start()`. Update `steadyClockPhasesDoNotRedrawTheVisibleDockTile` to explicitly use `false`, preserving the old default behavior.
- [ ] **Step 2: Add failing controller tests** using the existing injected `ChargingEffectTestTime` and `ManualEventSleeper`: `.dock` and `.both` render steady steps `[0,2,4,6]` for the first 0.4 seconds; `.menuBar` renders none, including when `activationPolicy.isRegularApp` becomes true because a settings window opened; switching the new setting off immediately renders static; switching it on at step 7 begins with the next eligible step, not a fresh cycle.

```swift
let steady = harness.log.renderedPhases.compactMap { $0 }.filter { $0.kind == .steady }
#expect(steady.map(\.step) == [0, 2, 4, 6])
```

- [ ] **Step 3: Add failing transition tests** for a level-advance burst while steady is active (3 burst frames followed by current steady; no `nil` between them), snapshot/options changes while active (new key, still non-nil phase), and stop causes (unplug, master switch, Reduce Motion, display sleep, Dock hidden, controller stop). Keep the existing plug-in 6-frame and level-advance 3-frame assertions. Also assert the shared clock/menu-bar stream still publishes every 20 fps step while Dock draws every other step.
- [ ] **Step 4: Run `swift test --filter ChargingEffectControllerTests`.** Expected: the new steady and transition assertions fail.
- [ ] **Step 5: Implement one effective-phase path in `AppIconController`.** Subscribe to `$phase` for steady and `$dockPhase` for burst, plus the new settings publisher. Store the values delivered by the publishers because `@Published` emits before its property is updated. On each 20 fps steady event, update Dock only for even steps; on a burst, update only even burst steps and hold that displayed burst frame between them. Route snapshot, option, theme, visibility and new-setting changes through the same effective-phase decision so they cannot insert a static frame. Use `DockChargingFrameCache` only for effective steady phases; draw/cache at most one new frame per accepted tick. On steady option off, Dock hidden or controller stop, clear the steady frame cache and restore static when the Dock is visible. Preserve the current Dock behavior when the new setting is off.

```swift
private var dockContinuousEnabled = false
private var displayedSteadyPhase: ChargingEffectPhase?
private var displayedBurstPhase: ChargingEffectPhase?

private var effectiveDockPhase: ChargingEffectPhase? {
    if let displayedBurstPhase { return displayedBurstPhase }
    guard dockContinuousEnabled,
          currentAppearance.batteryOptions.showsChargingEffect,
          currentPlacement.showsDockIcon,
          isDockTileVisible else { return nil }
    return displayedSteadyPhase
}

private func acceptSteadyPhase(_ phase: ChargingEffectPhase?) {
    guard let phase else {
        displayedSteadyPhase = nil
        if displayedBurstPhase == nil { renderLatestDockIcon() }
        return
    }
    guard phase.kind == .steady, phase.step.isMultiple(of: 2) else { return }
    displayedSteadyPhase = phase
    guard dockContinuousEnabled,
          currentPlacement.showsDockIcon,
          isDockTileVisible,
          displayedBurstPhase == nil else { return }
    renderLatestDockIcon()
}
```

The burst subscriber sets `displayedBurstPhase` only for even burst steps; on a `nil` event it clears the burst and calls `renderLatestDockIcon()` once. The main render method passes `effectiveDockPhase` into `DockIconRenderKey` and `renderDockIcon`, and uses the Task 2 cache for `.steady` phases. Clear `displayedSteadyPhase` when the option turns off; handle `@Published` settings using the delivered `Bool`, not a read of `settings` inside the sink.
- [ ] **Step 6: Publish `dockPhase` before `phase` in all three `ChargingEffectClock` update sites.** This makes the controller know about a new burst before it handles the same tick's steady phase. Tests must pin burst priority at the start and end of an event.
- [ ] **Step 7: Run `swift test --filter ChargingEffectControllerTests`, `swift test --filter AppIconControllerTests`, `swift test` and `swift build -c release`.** Expected: PASS。Check 10 fps by rendered phase sequence, not `Task.sleep` wall time. Commit only after both full commands pass.

### Task 4: 实机性能门槛和交付决策

**Files:**
- Create: `docs/performance/continuous-dock-charging-animation.md` (measurements and decision)
- Modify only if 10 fps misses target: `Sources/StatusTrioCore/App/AppIconController.swift` and the step-sequence tests from Task 3

**Interfaces:**
- Consumes: the Task 3 feature and the existing nonpersistent test-charging switch.
- Produces: repeatable 60-second A/B evidence, 10 fps acceptance or a tested 5 fps fallback decision. No unmeasured CPU claim.

- [ ] **Step 1: Build the `.dev.` app with `bash scripts/build-worktree.sh debug no-open`**, then verify the generated binary with `bash scripts/verify-platform-version.sh dist/StatusTrio.app/Contents/MacOS/StatusTrio 15.0 26` and launch that app. The build script already runs this assertion; the second command records the result beside the measurements. Do not alter `scripts/build-app.sh` or remove the SDK assertion.
- [ ] **Step 2: Select `.both`, turn on the test charging input, then close Settings and record three alternating 60-second A/B pairs** with Dock steady toggle off/on. Open Settings only between runs to change the toggle, close it again before sampling, and allow the same short settling interval each time. Keep power, brightness, other foreground apps and icon settings constant. For each run record Status Trio average/peak CPU, Dock process average/peak CPU, Status Trio RSS, observed fps, and date/machine/build. Use Activity Monitor or `top -l 61 -s 1` with the same sampling method for every pair; save raw samples or screenshots under the performance document's cited local artifact paths.
- [ ] **Step 3: Compare the median of the three 60-second means.** Pass only if Status Trio mean is ≤3%, RSS increment ≤40 MiB, Dock process increment is documented and visually smooth. Manually inspect menu/Dock phase alignment, light/dark background, low battery, level advance and Reduce Motion. This is the performance gate, not a unit-test substitute. If 10 fps fails, change the steady sampling predicate from `step.isMultiple(of: 2)` to `step.isMultiple(of: 4)`, update the expected sequence to `[0,4,8,...,32]`, and repeat all six 60-second runs. Keep burst sampling at 10 fps.
- [ ] **Step 4: If 5 fps still misses CPU/memory or looks visibly jerky, stop the feature at this gate.** Document measurements and keep the new option off by default; do not merge/release continuous playback. Record a separate design decision to prototype `NSDockTile.contentView` with explicit `display()` and compare both application and Dock CPU before choosing that architecture. Do not assert that `contentView` is cheaper without measurements.
- [ ] **Step 5: If a measured mode passes, run final `swift test` and `swift build -c release`, then complete the non-publishing `release.yml` preflight before merge/publish.** Use a version and build number that exceed the currently published build, record the workflow run ID and result; log every failed Actions run in `docs/swift-ci-compatibility.md` with stage, cause, fix and verification. Review the combined branch diff, the Dock/menu parity rule and 12-language coverage before deciding merge route.

## Completion criteria

The feature is ready for review only when the controller, cache and settings tests pass; the `.dev.` app shows a visibly synchronized Dock and menu bar while Settings is closed; the six-run A/B meets the stated budget at 10 or 5 fps; and the CI preflight passes. If the performance gate fails, the deliverable is the measurements and next prototype decision, not an unmeasured feature claim.

## Execution outcome

Tasks 1–3 and the performance probe were implemented and verified. The 10 fps mode measured a 16.60% median Status Trio CPU mean; a 5 fps sample measured 7.78%, so neither meets the 3% limit. Per the user's final instruction, all Dock charging animation paths are removed, including short event bursts; only menu bar animation remains. The development test switch continues to simulate charging for menu bar testing. See `docs/performance/continuous-dock-charging-animation.md` for the measurements and raw captures. No release preflight was run because this change is being committed without merging or publishing.
