# 菜单栏面板玻璃通透度调研（issue #40）

状态：**调研完成，待决策**。本文是调查记录，不是已批准的设计规格。方案定下来之后，
设计规格应写到 `docs/superpowers/specs/`，实施计划写到 `docs/superpowers/plans/`。

关联 issue：[#40 菜单栏展开玻璃透明度与原生透明度不一致](https://github.com/lingyired/status-trio/issues/40)

## 背景

issue #40 反馈菜单栏面板的模糊「太重了，没有原生菜单栏展开那么通透」，报告环境是
macOS 27.0 浅色模式。维护者当时的回复是「后面会使用自带的面板效果」。

2026-09-19 追加的需求：希望**加选项让用户自由选择**通透度，并且**考虑旧版本兼容**。

## 结论摘要

1. **决定性发现：popover 用的是不是原生 Liquid Glass，由「构建时链接的 SDK」决定，而不是运行的系统。**
   同一个 `NSPopover`，`LC_BUILD_VERSION.sdk = 27.0` 时 `NSPopoverFrame` 内部是私有 `NSGlassView`
   （原生 Liquid Glass）；`sdk = 15.5` 时退化成 `material = 6`（`.popover`，Tahoe 之前的磨砂材质）。
   本项目现状正是后者——已安装 app 的 `sdk` 字段是 15.5，CI 固定 Xcode 16.4。
   **因此「要原生液体玻璃」很可能只需把构建 SDK 升到 macOS 26+，不需要换掉 `NSPopover`。**
2. **`minos` 不影响这个判定**：实测 `minos 15.0 + sdk 27.0` 仍是原生 Liquid Glass。
   所以 `platforms: [.macOS(.v15)]` 与最低系统版本都可以原样保留。
3. 若不升级构建 SDK，则在 `NSPopover` 内部用什么招都做不出原生玻璃：玻璃由私有
   `NSPopoverFrame` 绘制，内容层只能叠加（更不透明）。那种情况下唯一出路是自绘 `NSPanel`。
4. 是否升级 CI 工具链（Xcode 16.4 → Xcode 26）尚无结论，见文末未决问题。

## 决定性发现：构建 SDK 决定是否使用原生 Liquid Glass

### 实验方法

不重装工具链，直接改写探针二进制的 `LC_BUILD_VERSION` 字段再运行：

```bash
cd backups/popover-glass-probe-20260919
vtool -set-build-version macos 15.0 15.5 -replace -output probe-sdk15 probe
codesign -s - --force probe-sdk15      # arm64 必须重新做 ad-hoc 签名
./probe-sdk15 ./out_sdk15
```

### 实测结果

| 二进制 | `LC_BUILD_VERSION` | `NSPopoverFrame` 实测 | 含义 |
|---|---|---|---|
| `probe` | minos 27.0 / **sdk 27.0** | `material=0`，子树含私有 `NSGlassView` + `ContentHolderView` + `_NSCoreHostingView<RootView>` | 原生 Liquid Glass |
| `probe-sdk15` | minos 15.0 / **sdk 15.5** | `material=6`（`.popover`）、`state=1`，子树只有我们的内容 | Tahoe 之前的磨砂材质 |
| `probe-min15sdk27` | minos 15.0 / **sdk 27.0** | `material=0` + `NSGlassView` | 原生 Liquid Glass |

第三行是关键：决定因素是 `sdk` 字段，不是 `minos`。

### 现状核对

- 已安装的 `/Applications/Status Trio.app`：`otool -l` 显示 `minos 15.0 / sdk 15.5`。
- CI：`.github/workflows/release.yml` 固定 `runs-on: macos-15` 与
  `DEVELOPER_DIR: /Applications/Xcode_16.4.app/Contents/Developer`（即 macOS 15 SDK）。

### CI 升级可行性（已核实）

GitHub Actions 的 `macos-26` 镜像已存在（见 `actions/runner-images` 的
`images/macos/macos-26-Readme.md`），预装 Xcode 26.0.1 / 26.1.1 / 26.2 / 26.3 / 26.4.1 /
26.5 / 26.6（默认 26.6），另有 `xcode-27-arm64` 预览镜像。runner 层面是现成的。

### 副作用（决策时需一并考虑）

- 用 macOS 26+ SDK 构建后，**整个 app 采纳新设计语言**，不只是 popover：设置窗口、按钮/控件、
  `SettingsChrome.SidebarMaterial` 这类 `NSVisualEffectView` 用法都会变样，需要一次视觉回归。
  参考文档亦建议新设计不要再拿 `NSVisualEffectView.material` 伪装。
- 与 AGENTS.md 的「Highest Priority: Match the CI Toolchain（macos-15 / Xcode 16.4 / Swift 6.1.2）」
  直接冲突：AGENTS.md 与 `docs/swift-6.1-ci-compatibility.md` 需要同步更新，Swift 6.2+ 的语法限制
  条款要重新评估。
- 构建 SDK 升级与「支持 macOS 15–25 老系统」并不矛盾：老系统上系统仍给旧的磨砂表现，
  这本身就是正确的原生行为，也是最干净的「旧版本兼容」。

### 用户可选性

系统全局键 `NSGlassTintAmount`（本机 = 1）就是 macOS 26/27 的「液体玻璃：透明 / 色调」总开关。
若目标是「原生」，正确做法是**跟随系统**，而不是在 app 内再造一个通透度选项——后者会与系统
设计语言打架。这一条属于产品决策。

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

### 补充调研（维护者提供的 `liquid-glass-macos-research.md`）

该文档给出的三条接入路径与本文结论一致：

- **路径 A（SwiftUI）**：`.glassEffect()` / `GlassEffectContainer` / `.glassEffectID(_:in:)`，
  加在 `.frame()` / `.padding()` 之后；`Button` 用 `.buttonStyle(.glass)` / `.glassProminent)`。
  适用于面板**内容内部**的玻璃卡片，管不到窗口 chrome。
- **路径 B（AppKit）**：公开的 `NSGlassEffectView`（`.regular` / `.clear` / `tintColor` /
  `cornerRadius`），窗口级做法是「窗口透明 + 根视图换成 `NSGlassEffectView`」
  （参考 [Aaron-212/CustomWindowBackgroundDemo](https://github.com/Aaron-212/CustomWindowBackgroundDemo)）。
  这正是方案 A 的背景实现方式。
- **路径 C（私有 API）**：beta 期的 `NSClassFromString` + `set_variant:` hack，文档自己也标注
  不建议，与本文结论一致。
- 其他要点：`#available(macOS 26, *)` 守卫 + `NSVisualEffectView` 降级；尊重
  `accessibilityDisplayShouldReduceTransparency`；不要再拿 `NSVisualEffectView.material`
  伪装新设计；Sheet 不要自定义 `presentationBackground`。

**注意**：该文档的前提是「必须用 Xcode 26 SDK 编译才能链接到新符号」。本文第一节的决定性实验
正是围绕这个前提做的——它同时解释了为什么现状是旧磨砂：**不是没写玻璃代码，而是构建 SDK 太旧**。

## 方案对比

### 方案 0（首选）：不换组件，只把构建 SDK 升到 macOS 26+

保留原生 `NSPopover`，CI 从 `macos-15` / Xcode 16.4 换成 `macos-26` / Xcode 26.x。
系统 chrome 由 AppKit 自己切换成原生 Liquid Glass，代码里一行玻璃相关的东西都不用写，
最少代码、最少回归面、也最符合「就要原生效果」的目标。

代价与前提：见上文「副作用」——需要改 CI 与 AGENTS.md 的工具链条款，并做一次全局视觉回归。
风险点是工具链升级本身（`docs/swift-6.1-ci-compatibility.md` 记录的历史崩溃属于旧编译器，
新编译器一般更好，但不能假定，需要真跑预检）。

### 方案 A（备选）：自绘 NSPanel + 公开双路径玻璃 + 用户可选档位

只有在「不能升级构建 SDK」时才需要走这条。macOS 26+ 用 `NSGlassEffectView(.regular / .clear)`，
macOS 15–25 退回 `NSVisualEffectView(material: .popover / .hudWindow / .underWindowBackground,
blendingMode: .behindWindow)`。

- 复用现有的 `popoverDismissMonitor`、`popoverToggleGate`、`dockAnchor`、`PopoverContentRetention`，
  只把 show/close 从 `NSPopover` 改接到 panel。
- 代价：原生箭头、`.transient` 语义、系统弹出动画需要自己处理；`StatusBarController` 与
  `PopoverLifecycleTests` 等测试需要改写。
- 如果同时不升级 SDK，`NSGlassEffectView` 只能用 `NSClassFromString("NSGlassEffectView")` 反射调用，
  失去编译期检查（生态里 Lunar、cmux 等就是这么做的）。

### 方案 B：保留 NSPopover，只在内容层加玻璃

探针已证明系统 `NSPopoverFrame` 永远在最底下，内容层只能叠加，**只能更不透明**。解决不了 #40，
最多算换个观感。不推荐。

### 方案 C：不换面板，只暴露公开语义

例如跟随系统「降低透明度」、跟随浅/深色（`popover.appearance`）。实现小、零风险，但答不了
「更通透」这个诉求。

## 兼容性维度（需要明确「旧版本兼容」指哪一层）

1. **构建 SDK**：这是唯一的开关。sdk ≥ 26 → 原生 Liquid Glass；sdk = 15.x → Tahoe 之前的磨砂。
   与 `minos` / `platforms: [.macOS(.v15)]` 无关（已实测）。
2. **运行的系统**：macOS 15–25 上没有 Liquid Glass，系统给旧表现，属于正确的原生降级，
   不需要产品代码处理——前提是走方案 0。
3. **旧版 App 的偏好写入**：只有走方案 A（自造选项）才会涉及。新 key 在旧版本中被忽略即可。
4. **已有用户升级后的默认值**：走方案 0 时，所有 macOS 26+ 用户会一次性看到新观感，
   无法用设置回退到旧磨砂；这一点需要在发布说明里讲清楚。
5. **辅助功能「降低透明度」**：系统级设置优先级最高，任何方案都要让路。
6. **系统「液体玻璃：透明 / 色调」（`NSGlassTintAmount`）**：走方案 0 时自动跟随，无需处理。

## 若走方案 0 需要改动的面

- `.github/workflows/release.yml`：`runs-on: macos-15` → `macos-26`，
  `DEVELOPER_DIR` → `/Applications/Xcode_26.x.app/Contents/Developer`。
- `AGENTS.md`：更新「Highest Priority: Match the CI Toolchain」的 runner / Xcode / Swift 版本，
  并重新评估 Swift 6.2+ 语法限制条款。
- `docs/swift-6.1-ci-compatibility.md`：追加本次工具链迁移的记录与预检结果。
- 视觉回归：设置窗口、按钮/控件、`SettingsChrome.SidebarMaterial`、`IconPreviewComponents`
  等所有 `NSVisualEffectView` / 自绘视图在 26+ 下的新表现。
- 产品代码理论上**零改动**；实际可能需要处理新 SDK 引入的弃用告警或 API 变化。

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

### 双 SDK 真机并排对比（方案 0 的观感证据）

同一个 `NSPopover`、同一份内容，只有 `LC_BUILD_VERSION.sdk` 不同，两个进程并排显示：

```bash
cd backups/popover-glass-probe-20260919
swiftc -O compare.swift -o cmp-modern
cp cmp-modern cmp-legacy
vtool -set-build-version macos 15.0 15.5 -replace -output tmp cmp-legacy && mv tmp cmp-legacy
codesign -s - --force cmp-legacy

./cmp-modern "A · macOS 27 SDK（原生 Liquid Glass）" 400 980 light &
./cmp-legacy "B · macOS 15 SDK（现状）"          1300 980 light &
```

第 4 个参数 `light` 会把进程外观强制为浅色，以复现 issue #40 报告时的条件；
省略则跟随系统。两个进程 5 分钟自动退出。

### 探针（结构证据）

```bash
cd backups/popover-glass-probe-20260919
swiftc -O probe.swift -o probe && ./probe ./out
```

试过的 11 个 variant：现状、`.popover` × `.behindWindow` / `.withinWindow`、`.menu`、`.hudWindow`、
`.underWindowBackground`、`.sidebar`、`.headerView`、`.popover` + `vibrantLight` 外观、
以及清空窗口背景的两组。所有结果都只影响叠加层，不改变 `NSPopoverFrame`。

### 可视原型（方案 A 的档位候选）

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

1. **是否采用方案 0**，即把 CI 从 Xcode 16.4 升到 Xcode 26 以换取原生 Liquid Glass？
   这会与 AGENTS.md 现行的工具链条款冲突，需要同步修改。
2. 真机并排对比的结论：A（新 SDK）是否就是 #40 想要的观感？
3. 若采用方案 0，是否还需要 app 内自造通透度选项？系统已有「液体玻璃：透明 / 色调」
   （`NSGlassTintAmount`），我的建议是跟随系统、不另造选项。
4. 若不能升级 SDK，是否接受方案 A（自绘 NSPanel，需要自造玻璃与面板生命周期）？
5. 现有用户升级后会一次性看到新观感且无法在 app 内回退，这个是否可接受、是否要写进发布说明？
