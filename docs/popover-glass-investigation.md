# 菜单栏面板玻璃通透度调研（issue #40）

状态：**调研完成，待决策**。本文是调查记录，不是已批准的设计规格。方案定下来之后，
设计规格应写到 `docs/superpowers/specs/`，实施计划写到 `docs/superpowers/plans/`。

关联 issue：[#40 菜单栏展开玻璃透明度与原生透明度不一致](https://github.com/lingyired/status-trio/issues/40)

## 背景

issue #40 反馈菜单栏面板的模糊「太重了，没有原生菜单栏展开那么通透」，报告环境是
macOS 27.0 浅色模式。维护者当时的回复是「后面会使用自带的面板效果」。

2026-09-19 追加的需求：希望**加选项让用户自由选择**通透度，并且**考虑旧版本兼容**。

## 结论摘要

1. **NSPopover 的玻璃由私有视图绘制，公开 API 改不了通透度。** 面板内部加任何视图都只能
   叠加材质（更不透明），不能削弱系统底盘。因此「用户可选通透度」只能靠自绘 `NSPanel` 实现。
2. **macOS 26+ 的公开 `NSGlassEffectView(.clear)` 已经足够通透**，不需要私有 API 就能满足
   #40 的诉求。
3. **双路径兼容是生态标准做法**：macOS 26+ 用 `NSGlassEffectView`，macOS 15–25 退回
   `NSVisualEffectView`。本项目 `platforms: [.macOS(.v15)]`，这条路必须实现。
4. 是否接受「换成自绘面板」这一较大改动，**尚无结论**，见文末未决问题。

## 探针实测：NSPopover 的背景到底由谁绘制

### 方法

一次性 AppKit 探针（非产品代码，已移到 `backups/popover-glass-probe-20260919/probe.swift`）：
建一个锚点窗口 + 带 SwiftUI 内容的 `NSPopover`，显示后打印整条视图层级（类名、`material`、
`blendingMode`、`isOpaque`），再逐一切换内嵌 `NSVisualEffectView` 的材质与混合模式并重新 dump。

环境：macOS 27.0（26A428）、macOS 27 SDK、本地 Swift 6.4。与 #40 报告者系统一致。

复现：

```bash
cd backups/popover-glass-probe-20260919
swiftc -O probe.swift -o probe && ./probe ./out
```

### 实测视图树（现状 variant，未插入任何自定义材质）

```
_NSPopoverWindow            isOpaque=false, backgroundColor=全透明
└─ NSPopoverFrame           ← 私有的 NSVisualEffectView 子类, material=0 (.titlebar)
   ├─ NSGlassView           ← 私有的 Liquid Glass 渲染层
   │  ├─ ContentHolderView
   │  └─ _NSCoreHostingView<RootView>
   └─ NSView frame=(13,13,360,260)
      └─ NSHostingView<SampleContent>
```

`ancestor chain from contentView: NSPopoverFrame`——也就是说窗口的 `contentView` 就是我们的内容
视图（内缩 13pt 给箭头留位），而 `window.contentView.superview` 才是私有的 `NSPopoverFrame`。

### 结构性结论

1. 窗口本身就是 `isOpaque=false` + 全透明背景，**改 `isOpaque` / `backgroundColor` 没有任何效果**。
2. 真正画玻璃的是 `NSPopoverFrame`（私有 `NSVisualEffectView` 子类）+ 私有 `NSGlassView`。
3. 内容视图是这层玻璃的**上层兄弟视图**。因此在内容上叠加材质是加法，只能更不透明。
4. 实测了 7 种材质 × `.behindWindow` / `.withinWindow` 两种混合模式，**都不影响 `NSPopoverFrame`**；
   屏幕上的观感差异只来自叠加层本身。
5. SDK 里没有任何公开 API 能调整 popover 边框玻璃：`NSPopover` 的公开外观接口只有
   `appearance`（切 vibrant 浅/深），`NSGlassEffectView` 是**内容级**玻璃，管不到窗口 chrome。
6. 唯一能改的路径是私有 `NSPopoverFrame.material` 或隐藏 `NSGlassView`。
   **不建议采用**：会随系统更新静默失效，且无法纳入本项目的 CI 覆盖（见下）。

### 方法论警告：截图不能替代肉眼

探针里的 `cacheDisplay` 截图**不能反映真实观感**——它不合成窗口背后被模糊的内容。现状 variant
被渲染成一片浅色，白色标题几乎看不见。**不要用这类截图判断「是否够通透」**，只能靠真机肉眼。

## GitHub 生态调研

### 共识一：想要自定义玻璃的菜单栏面板，没人用 NSPopover

- [Maccy](https://github.com/p0deje/Maccy) 的 `Maccy/FloatingPanel.swift` 是最完整的替代品参考：
  `class FloatingPanel<Content: View>: NSPanel, NSWindowDelegate`，`styleMask`
  为 `[.nonactivatingPanel, .resizable, .closable, .fullSizeContentView]`、`isFloatingPanel = true`、
  `level = .screenSaver`、`backgroundColor = .clear`，内容用 `NSHostingView` 装 SwiftUI。
  定位与本项目 popover 几乎 1:1。
- [iSapozhnik/Popover](https://github.com/iSapozhnik/Popover)（MIT）同样以 NSPanel 重写 popover，
  并把 `backgroundColor` / `borderColor` 作为配置项暴露，说明「背景要可控 ⇒ 自己实现」是领域共识。
  评估：可作为参考实现，但引入依赖不如自己写百来行；本项目现有依赖只有 Sparkle。

### 共识二：双路径兼容（26+ 玻璃 / 否则 visual effect）

- [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) 的 `AppDesign.modernEffectView`：
  `guard #available(macOS 26.0, *), modernStyle else { return NSVisualEffectView.self }`。
- [alt-tab-macos](https://github.com/lwouis/alt-tab-macos) 的
  `src/switcher/main-window/TilesPanelBackgroundView.swift` 用 `protocol EffectView` + `hostView`
  抹平差异：`NSVisualEffectView.hostView = self`，`NSGlassEffectView.hostView = contentView!`。
  注释点明 **`contentView` 是 Apple 唯一保证会被放进玻璃里的位置**，与本项目 SDK 头文件一致。
- [Maccy](https://github.com/p0deje/Maccy) 则是最朴素的写法：两个 `NSViewRepresentable`，
  `.popover` + `.behindWindow`，以及 26+ 的 `NSGlassEffectView(.regular)`。

### 共识三：`.clear` 就是「通透」档，公开 API 已够用

alt-tab-macos 的注释原话：`style = .clear` alone renders nearly fully transparent。
他们额外使用私有 `set_variant:` / `set_scrim:` / `set_subdued:`，只是为了做 Dock / Cmd-Tab
那种「很通透但仍有存在感」的额外档位；[MenuBarLG](https://github.com/parishkar-singh/MenuBarLG)
把私有 variant 列成了全表（regular / clear / dock / avPlayer / controlCenter /
notificationCenter / monogram）。

**本项目建议不碰私有 API**：会随系统更新静默失效，CI 只覆盖 macOS 15 / 26 / 27 三个点，无法覆盖
小版本回归；而公开 `.clear` 已能满足 #40 的诉求。若日后确实需要，必须带
`class_getInstanceMethod` 探测 + 优雅降级，并作为明确的实验性档位标注。

### 共识四：持久化与迁移写法

[MenuBarLG](https://github.com/parishkar-singh/MenuBarLG) 的 `BlurStyleManager` 与
`GlassTuningManager` 提供了直接可抄的结构：`BlurMode { liquidGlass, backdropBlur }`、
`defaultBackdropMaterial = .hudWindow`、材质/混合模式/alpha/intensity 的上下界常量、
`legacyCornerRadiusUserDefaultsKey` 这类 **legacy key 迁移**、0.3s debounce 落盘。

与本项目 `SettingsStore` 现有模式同构：

```swift
self.volumeDisplayStyle = storedVolumeDisplayStyle
    .flatMap(VolumeDisplayStyle.init(rawValue:))
    ?? Self.defaultVolumeDisplayStyle
```

**向后兼容因此天然成立**：老用户没有新 key → 落默认档；新版本写入了未来版本的值 → 落默认档；
旧版本 App 根本不读这个 key。

### 共识五：macOS 27 特有的两个坑

本项目目标系统正好是 27，需要提前处理：

- alt-tab-macos 记录：macOS 27 上玻璃裁剪会在形状之外画出一条直边轮廓（其 issue #5757），
  修法是**同时**设置 `layer.cornerRadius`。
- `NSVisualEffectView` 用 `layer.cornerRadius` 做圆角会有锯齿，成熟做法是 `maskImage` +
  `capInsets` 拉伸的圆角蒙版（alt-tab-macos 中引用的 StackOverflow 方案）。

### 共识六：辅助功能必须让路

MarkEdit 的
`reduceTransparency = AppPreferences.Window.reduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`。
系统开启「降低透明度」时不能硬套玻璃。

## 方案对比

### 方案 A（推荐）：自绘 NSPanel + 公开双路径玻璃 + 用户可选档位

- macOS 26+：`NSGlassEffectView(.regular / .clear)`。
- macOS 15–25：`NSVisualEffectView(material: .popover / .hudWindow / .underWindowBackground,
  blendingMode: .behindWindow)`。
- 复用现有的 `popoverDismissMonitor`、`popoverToggleGate`、`dockAnchor`、`PopoverContentRetention`，
  只把 show/close 从 `NSPopover` 改接到 panel。
- 代价：原生箭头、`.transient` 语义、系统弹出动画需要自己处理；`StatusBarController` 与
  `PopoverLifecycleTests` 等测试需要改写。
- 这是唯一能真正满足「用户可选通透度」的路径。

### 方案 B：保留 NSPopover，只在内容层加玻璃

探针已证明系统 `NSPopoverFrame` 永远在最底下，内容层只能叠加，**只能更不透明**。解决不了 #40，
最多算换个观感。不推荐。

### 方案 C：不换面板，只暴露公开语义

例如跟随系统「降低透明度」、跟随浅/深色（`popover.appearance`）。实现小、零风险，但答不了
「更通透」这个诉求。

## 兼容性维度（需要明确「旧版本兼容」指哪一层）

1. **macOS 版本**：15–25 没有 `NSGlassEffectView`，只能给材质档；26+ 才有 glass 档。
   档位命名要避免让旧系统用户看到不存在的选项。
2. **旧版 App 的偏好写入**：新 key 在旧版本中被忽略即可，不会破坏旧版行为。
3. **已有用户升级后的默认值**：默认档决定他们是「保持现状的观感」还是「直接变通透」，
   两者体验差异很大，属于需要拍板的产品决定。
4. **辅助功能「降低透明度」**：系统级设置优先级最高，任何档位都要让路。

## 若走方案 A 需要改动的代码面

- `Sources/StatusTrioCore/UI/`：新增自绘面板（NSPanel + 玻璃宿主视图，含双路径与圆角掩码）。
- `Sources/StatusTrioCore/UI/StatusBarController.swift`：`presentPopover` / `togglePopover` /
  Dock 锚定 / 关闭监视改接 panel。
- `Sources/StatusTrioCore/Settings/SettingsStore.swift`：新选项、默认值、`stored.flatMap(...) ?? default`
  兼容读取、上下界夹取。
- `Sources/StatusTrioCore/UI/Settings/`：`PopoverSectionView` 增加选择行（现有 `SettingsMenuRow`
  可直接复用）。
- `Sources/StatusTrioCore/Resources/*.lproj`（12 种语言）：新增文案，术语需与该语言现有字符串一致。
- `Tests/StatusTrioCoreTests/`：选项派生、兼容读取、档位映射、面板生命周期回归。

按 AGENTS.md，改动涉及 `@MainActor`、SwiftUI 绑定与 `Bundle.module` 资源时，除 `swift test` 与
`swift build -c release` 外，还要跑一次 `publish=false` 的 release workflow 预检。

## 复现方式

### 探针（结构证据）

```bash
cd backups/popover-glass-probe-20260919
swiftc -O probe.swift -o probe && ./probe ./out
```

试过的 11 个 variant：现状、`.popover` × `.behindWindow` / `.withinWindow`、`.menu`、`.hudWindow`、
`.underWindowBackground`、`.sidebar`、`.headerView`、`.popover` + `vibrantLight` 外观、
以及清空窗口背景的两组。所有结果都只影响叠加层，不改变 `NSPopoverFrame`。

### 可视原型（观感判断）

```bash
cd backups/popover-glass-probe-20260919
./prototype          # 或 swiftc -O prototype.swift -o prototype 后运行
```

- `P1`：右上角真实的现状 `NSPopover`，作为基准（原型的 popover 用 `.applicationDefined`
  以便停留对比，产品里是 `.transient`）。
- `P2`：`NSGlassEffectView(.clear)`；`P3`：`.regular`；`P4`：`.popover`；
  `P5`：`.hudWindow`；`P6`：`.underWindowBackground`；`P7`：无背景。
- 面板后方垫有高对比条纹底图，否则 `behindWindow` 混合没有可显示的内容。
- 按 Esc 关闭，8 分钟自动退出，整块对比板可拖动。
- 该目录已被 `.gitignore` 覆盖（`backups/`），不属于产品代码，不会进提交。

## 未决问题（等决策）

1. 是否接受方案 A（换成自绘 NSPanel）？
2. 「旧版本兼容」具体指哪一层：旧 macOS、旧版 App 的偏好、还是老用户升级后的观感？
3. 默认档位是什么；老用户升级后是保持现状还是直接变通透？
4. 提供几档、如何命名（例如「跟随系统 / 通透」，还是再拆出「高对比」）？
5. macOS 15–25 上只有材质档、没有 `.clear`，这个降级是否可接受？
6. 是否需要在方案 A 之前先做真机观感确认（原型 `P2` vs `P1`）？
