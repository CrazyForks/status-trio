# 充电彗尾流光设计

## 目标

1. 充电时，菜单栏电量环上有一条**彗尾流光**：一条比填充更亮的尾巴，沿环从起点匀速扫到当前电量端点，末端收束成一次心跳。表达的是「电正在流进来」，而不只是「插着电」。
2. 尾巴颜色**默认可自动派生**，用户可在设置里从预设中挑，也可**自定义颜色**；浅色与深色外观只选一次。
3. 非充电状态、系统「减少动态效果」、屏幕休眠、或用户关掉开关时，渲染与今天**逐像素一致**，且没有任何额外重绘。
4. 开关、预设、自定义色都要进「设置 › 电池」，并随 12 语言发布；设置页预览卡能看到效果。
5. 实现分两步落地：**(1) 动效本体**（相位、时钟、几何、能耗）→ **(2) 颜色预设与自定义**（设置项、取色器、12 语言）。两步之间应用始终可发布。

## 背景（现状与依据）

- **渲染是「值渲染 + 值缓存」**：`StatusIconRenderer.image/render`（`Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift:36,133`）只吃值；菜单栏按 `StatusBarRenderKey` 去重（`UI/Icon/StatusBarRenderCache.swift:1`），Dock 按 `DockIconRenderKey`（`UI/Icon/DockIconRenderCache.swift:1`）。仓库里**没有任何帧驱动机制**，唯一的定时器是外观轮询（`App/SystemIconAppearanceMonitor.swift:17`）。所以「一直动」需要新增一条时间驱动的重绘管线。
- **已有的节流器可复用**：`IconRenderCoalescer` 默认 20 次/秒、`now`/`sleep` 可注入（`UI/Icon/IconRenderCoalescer.swift:12`），测试用 `ManualEventSleeper`。
- **电量环几何**：半径 `51.5`、圆心 `(59.5, 61.487)`、起始角 `148.69°`、扫角 `242.62°`、描边 `8`、画布 `120`（`UI/Icon/StatusIconGeometry.swift:5-10`）。环从**左下**起、顺时针经顶端缺口到右下，所以「从左到右」成立。
- **顶端缺口很大**：`batteryChargingBoltTopGapWidth = 50` 占整弧 **22.9%**，`batteryValueTopGapWidth = 64` 占 **29.3%**（同上 :12-13）。`batteryArc` 已经会按缺口把弧**切成两段**（同文件 :362）。顶部既不显示闪电也不显示数字时 `hasTopGap == false`，弧是**完整连续**的（`Models/StatusMappings.swift:78-95`）。
- **配色已有两套**：充电绿浅色 `(52,199,89)`、深色 `(31,143,61)`，与临界红、低电量模式黄同在 `StatusIconRenderer.color(for:...)`（同文件 :394-417）；`BatteryColorRole` 里 `.critical` 优先于 `.charging`（`Models/StatusMappings.swift:68-77`），所以「低电量 + 充电」时填充是红的。
- **开关先例**：`showsChargingIndicator` 已经在 `BatteryIconOptions` 里、并被 `SettingsStore.batteryIconOptions` 带进两个 render key（`Models/BatteryIconOptions.swift:5`、`Settings/SettingsStore.swift:432`）。尾巴开关走同一条路，**开关一动两个缓存自动失效**。
- **Dock 平价要求**：菜单栏图标的渲染改动必须同步 Dock，除非在 spec 里显式声明为 menu-bar-only 并加测试（`AGENTS.md`）。本设计选择「菜单栏常动、Dock 仅事件驱动」，见「Dock 平价」一节。
- **Reduce Motion 先例**：`UI/IconGuideView.swift:456` 已有 `reduceMotion` 分支。
- **参考实现**：`charging-effects-demo.html`（未跟踪、丢弃件）1:1 移植了上述几何与调色板，用于定参数；本文所有实测数字来自它。规格定稿后删除（或按需留档）。

## 设计决策

| # | 决策 | 依据 |
|---|---|---|
| D1 | **只有 `battery.isCharging` 时运行**。接通电源但未充电（已充满、优化充电暂停）保持静止 | 图标在动却「没在充电」是骗人的 |
| D2 | 相位沿**整弧**匀速（progress 空间），**缺口消耗时间**，头部在缺口内不绘制 | 头尾两侧都好看：瞬时穿越会读成「从左边直接跳到右边」 |
| D3 | 填充末端落在缺口里时，行程终点取**缺口左沿**，收束心跳也落在那里 | 否则心跳会发生在看不见的地方 |
| D4 | `hasTopGap == false`（顶部无闪电也无数字）时不产生任何空白 | 弧本身连续，没有缺口 |
| D5 | **低电量抑制**：可见填充短于可见弧长 25% 时抑制尾巴，只留端点心跳 | 填充只剩一小段茬时尾巴会占满它，看着像坏了 |
| D6 | 尾巴长度上限 `min(设定值, 78% 可见填充)` | 尾巴不能比填充本身还长 |
| D7 | 周期 = 行程 + **收束心跳**（端点亮斑） | 心跳把「最新电量处」指出来，是这条动效的「生命体征」 |
| D8 | 插电瞬间播一轮 **0.6s 压缩轮**（同一 20fps 时钟、周期压缩）；电量整数跳变把**下一次心跳亮斑加成 ×1.35**，不打断常驻节奏 | 事件驱动才有「插上去那一下」的反馈，且不增加帧率 |
| D9 | **默认一律提亮**（往白混）；预设里保留一个压暗项供选择，但默认不选中 | 压暗的绿尾巴读起来像污渍（用户实测结论），所以默认提亮；8 个预设用户都认可，因此都作为选项保留 |
| D10 | 尾巴颜色**可配置**：内置预设 + 自定义取色器；只作用于充电态；两个外观共用一次选择 | 见「颜色系统」 |
| D11 | 菜单栏常动 20fps；**Dock 只事件驱动** | Dock 一帧 512×512（`DockIconRenderer.pixelSize`），是菜单栏的约 135 倍像素 |
| D12 | Reduce Motion、屏幕休眠 → `phase = nil`，等于今天的静态渲染 | 不新增需要单独测试的视觉变体 |
| D13 | 开关默认**开启**，新装与升级一致，不写迁移代码 | 纯视觉、一键可逆、充电时开销由适配器承担 |

## 组件与改动面

**新增**（`Sources/StatusTrioCore/UI/Icon/`）

| 组件 | 职责 |
|---|---|
| `ChargingEffectPhase` | 相位值：`step`、`stepsPerCycle`、`.burst`/`.steady` 两种时间轴；`nil` 表示静止 |
| `ChargingEffectPolicy` | 纯策略：**何时该动**（真值表）+ 给定相位产出**帧**（尾巴区间、渐变端点、亮珠、心跳） |
| `ChargingEffectTimeline` | 纯函数：`(t, kind) → 相位`；含插电压缩轮与电量跳变加成 |
| `ChargingEffectEvent` | 纯检测：前后两个电量 → `.pluggedIn` / `.levelAdvanced` / `nil` |
| `ChargingEffectClock` | `@MainActor` 20fps 步进器，`sleep`/`now` 可注入（照 `IconRenderCoalescer` 的写法） |
| `ChargingEffectPalette` | 颜色解析：角色 × 外观 × 用户选择 → 尾巴色 + 实测对比度 + 可见性下限 |
| `ChargingTailColorSetting` | 用户选择的值类型：`preset(id)` 或 `custom(hue:saturation:brightness:)` |
| `DisplaySleepMonitor`（`App/`） | 息屏即停，照 `SystemIconAppearanceMonitor` 的通知 + 轮询先例 |

**改动**

| 文件 | 改动 |
|---|---|
| `UI/Icon/StatusIconGeometry.swift` | 弧线加 `[from, to]` 区间版本（`batteryFill` 变成它的特例）；新增 `batteryHighlight`；新增可见弧映射 `visibleFraction`/`progress(forVisibleFraction:)`；`lastVisibleProgress` |
| `UI/Icon/StatusIconRenderer.swift` | 四个入口都吃 `phase`（默认 `nil` = 今天的行为）；`drawBattery` 叠加尾巴、亮珠、心跳 |
| `Models/BatteryIconOptions.swift` | 加 `showsChargingEffect`、`tailColor` |
| `UI/StatusBarController.swift` | 订阅时钟；`StatusBarRenderKey` 加 `phase`；`StatusBarController.swift:476` 的渲染调用带上相位 |
| `App/AppIconController.swift` | 订阅同一个时钟，但只在 burst 窗口内重绘；`DockIconRenderKey` 加 `phase` |
| `App/AppEnvironment.swift` | 持有共享时钟与 `DisplaySleepMonitor`（**一个时钟、两个订阅者**，各自带闸门） |
| `Settings/SettingsStore.swift` | `showsChargingEffect`（默认开）、`chargingTailColor`，进 `batteryIconOptions` |
| `UI/Settings/BatterySectionView.swift` | 开关行 + 颜色区（预设网格、取色器、恢复默认） |
| `Localization/LocalizationKey.swift` + 12×`Resources/*.lproj/Localizable.strings` | 新增键（见「设置与本地化」） |

## 几何与相位规则

**可见弧映射**。缺口居中对称，所以可见段是两段等长区间 `[0, (1-g)/2]` 与 `[(1-g)/2, 1-g]`，其中 `g = topGapWidth / (半径 × 扫角弧度)`（闪电缺口 `g ≈ 0.2293`，百分比 `0.2935`）。映射是纯函数：单调、可往返、边界可测。

**相位**。`head` 从 `0` 线性走到 `headMax`：

- `headMax = progress`（正常）或 `min(progress, 0.5 - g/2)`（填充末端落在缺口里，D3）。
- 尾巴 `tail = max(0, head - L)`，`L = min(tailRatio × (1-g), 0.78 × vFill)`。
- 光带路径 = `batteryHighlight(from: tail, to: head)`，**复用缺口的切分逻辑**，所以跨缺口时自然断成两段、在缺口内时整个不绘制。
- 渐变沿 `tail → head` 的**弦方向**线性：`CGPath.copy(strokingWithWidth:)` 转裁剪区 + `drawLinearGradient`。梯度透明度曲线可选线性／缓入／缓出。
- 亮珠：`head` 处半径 `描边 × headScale / 2` 的实心圆（`fillEllipse`），随收束淡出。
- 心跳：收束 `0.25s`，端点实心圆半径 `0.95 × 描边 × (1 + 0.55 × (1 - α))`、`α: 0 → 峰值 → 0`。

**22pt 下的换算**：画布 120 单位整体映射到 22pt，所以 **1 个 progress 单位 ≈ 39.98pt**。整弧 ≈ 40.0pt，可见弧 30.8pt（闪电缺口）／28.2pt（百分比缺口），描边 ≈ 1.47pt，尾巴 32% ≈ 9.9pt（有效可见 ≈ 8.4pt）。

## 颜色系统

**解析顺序**：`角色 × 外观` 决定填充色 → 用户选择决定尾巴色 → 可见性下限兜底。

1. **默认（无用户选择）**：尾巴 = 填充色往白混到对比度 ≥ 1.8:1（**只对充电态**）。低电量红 → 浅粉，低电量模式黄 → 浅黄，单色 → 浅灰。这条规则不写死绿色，任何状态色都成立。
2. **预设**：每个预设 = `(方向, 对比度, 色相偏移)`，先对填充色做 HSL 色相偏移（明度/饱和度不变），再往白混到目标对比度。**两个外观各自派生**，所以一次选择两边都对。内置 8 个（实测值，浅色／深色）：

   | 预设 | 浅色（填充 `#34c759`） | 深色（填充 `#1f8f3d`） | 参数 |
   |---|---|---|---|
   | 同色 · 淡 | `#97e2aa` | `#57ab6d` | 0° / 1.45 |
   | 同色 · 白 | `#c4efcf` | `#72b885` | 0° / 1.75 |
   | **偏青 · 能量（默认）** | `#a4e6ca` | `#60af90` | +20° / 1.55 |
   | 偏黄 · 暖光 | `#ade7a8` | `#65af60` | −20° / 1.55 |
   | 薄荷 · 白 | `#e1f7ef` | `#7fbfab` | +25° / 1.95 |
   | 纯白 · 上限 | `#fdfefd` | `#96caa4` | 0° / 2.20 |
   | 偏蓝 · 越界 | `#b8e3eb` | `#72abb8` | +55° / 1.60 |
   | 深色尾巴（对照） | `#269141` | `#156029` | 0° / 1.80（压暗） |

   注：浅色绿往白最多只能到 **2.24:1**（`#34c759` 对纯白），所以「纯白 · 上限」取 2.20。任何方向够不到设定对比度时**回退到反方向并在设置里报出来**，不允许静默退化（这个坑在 demo 里踩过：2.30 会让浅色外观悄悄变成深绿尾巴）。
3. **自定义**：取色器给的是**具体颜色**，按用户所选**原样**用于两个外观，只有与填充的 WCAG 对比度低于**可见性下限 1.2:1** 时才朝提高对比度的方向抬起，并在设置页显示实测对比度。理由：预设是「规则」（自动适配两个外观），自定义是「用户的明确选择」，若也强行重算，取色器就在骗人。
4. **单色模式**（`usesStatusColors == false`）：填充是前景色（黑/白），此时**忽略自定义色的色相**，只保留亮度差，避免在一个刻意无彩色的模式里引入绿色。这是**有意限制**，设置页文案说明并由测试锁定。
5. 自定义色存 **HSB 三分量**（`hue/saturation/brightness` + `mode` 标记）而不是 hex：派生与下限计算都在 HSB/HSL 里做，避免来回转换丢精度。

## 时间与事件

```
BatteryMonitor → snapshot 变化
   ├─ ChargingEffectEvent.between(prev, cur) → 启动/停时钟、打 burst 标记
   └─ 每 tick：Timeline → Phase → Policy.frame(progress, phase) → Renderer → 菜单栏 image（phase 进 key）
                                                                        → Dock image（仅 burst 窗口内）
```

**不变量（测试钉死）**

1. `phase == nil` 的渲染与今天**逐像素一致**。
2. `phase == nil` 时两个 render key 与今天一致；**没有插电事件时 Dock 一次都不重绘**。
3. 时钟 tick 直接渲染，不再过 `IconRenderCoalescer`（否则相位会被抽帧）；状态/设置变化仍走 coalescer。

## 能耗、降级与预算

- 只在充电时运行；**屏幕休眠立刻停**（`DisplaySleepMonitor`）；Reduce Motion → `phase = nil`。
- 菜单栏 20fps；Dock burst 10fps（插电 6 帧 / 0.6s，与菜单栏的压缩轮同时长；电量跳变 3 帧）。
- **预算：菜单栏动画 < 单核 1%**。实现后必须实测（`top` 采样 60 秒，对比开关关闭时）并把数字写进本文件。超预算则改上「预渲染帧表」（进入充电态时预渲 36 帧、之后只换图），本设计不做是因为当前 22pt 位图重绘本就很便宜。
- Dock 512px 不参与常驻重绘（见下）。

## 设置、本地化与预览

- **开关**：`showsChargingEffect`，默认 `true`（`defaults.object(forKey:) == nil` 回落，沿用 `SettingsStore.swift:525` 的写法）。放在「设置 › 电池」的充电指示开关下方，`SettingsToggleRow(symbol: "sparkles", tint: .green)`，副标题写明「仅在充电时运行；系统开启减少动态效果时自动静止」。
- **颜色区**：与 8 个预设一致的网格（每格用真实渲染器画浅色/深色两个 44pt 图标）+ `ColorPicker` 自定义 + 「恢复默认」。当前在用的那格高亮。设置页实时显示实测对比度；低于下限被抬起时给出提示。
- **新增本地化键**（12 个 `.lproj`：ar / de / en / es / fr / it / ja / ko / pt-BR / ru / zh-Hans / zh-Hant）：
  `settingsBatteryChargingEffect`、`…ChargingEffectDescription`、`settingsBatteryTailColor`、`…TailColorDescription`、`settingsBatteryTailColorCustom`、`…TailColorReset`、`…TailColorContrastFormat`、`settingsBatteryTailColorPresetSameSoft` / `SameWhite` / `Cyan` / `Warm` / `Mint` / `White` / `Blue` / `Dark`、`settingsBatteryTailColorMonoNote`。
  文案必须沿用各语言既有 `.lproj` 的术语（充电／Charging 等）。
- **预览卡**：`StatusIconPreviewCard` 渲染的就是真图标，实时充电时会自己动。**待定项**：Mac 没插电时用户看不到效果，是否加「拨开开关时本地试播 2 轮（约 3.6s）」，约 10 行代码——建议要。

## Dock 平价（有意差异声明）

按 `AGENTS.md` 的要求在此**显式声明**：本设计**不是**菜单栏与 Dock 完全平价。

- 相同：几何、颜色解析、相位语义共用同一套纯函数与同一个渲染器。
- 不同：菜单栏 20fps 常驻；**Dock 只在插电与电量跳变时各播一次 burst**，其余时间静态。理由：Dock 一帧 512×512，常驻动画的像素量是菜单栏约 135 倍，而 Dock 图标并非总是可见。
- 由测试锁定：无事件时 `DockIconRenderKey` 不含相位、Dock 渲染调用次数为 0；插电时恰好 6 帧。

## 测试与验收

- **纯函数单测**：可见弧映射（往返/单调/边界）；`lastVisibleProgress`（含填充末端落在缺口内）；`Policy.frame` 在固定步下的尾巴区间（含低电量抑制、缺口不相交、收束塌缩）；`Timeline`（常驻周期、插电压缩轮、跳变加成）；`Event.between`；`shouldAnimate` 真值表（充电 / 接通未充电 / 已充满 / 关开关 / Reduce Motion / 息屏）。
- **颜色单测**：8 个预设 × 2 外观的解析色与实测对比度；自定义色两外观原样使用；低于 1.2:1 时被抬起且报告；单色模式忽略色相；方向不可达时的回退与披露。
- **像素测试**：`phase == nil` 与今天逐像素一致；**非充电状态喂任何相位，输出与 `phase == nil` 完全一致**；充电时相位差异只落在填充弧路径范围内。
- **控制器测试**：充电时菜单栏 key 每步变化、未充电不变；无事件时 Dock 不重绘；burst 帧数正确。沿用 `IconRenderCoalescerTests` 的注入式 sleeper。
- **本地化**：12 个 `.lproj` 键齐备（`scripts/` 里既有的校验脚本或新增断言）。
- **CI**：`swift test` + `swift build -c release`；本改动触及 `@MainActor`、SwiftUI binding、定时器，按 `AGENTS.md` 必须在合并前跑一次**非发布** release workflow（`-f publish=false`）。任何失败按规则写进 `docs/swift-ci-compatibility.md`。
- **发布**：release notes 需 `en.md` 与 `zh-Hans.md`（`publish=true` 才要求 12 语言齐全）。

## 迁移与默认值

- `showsChargingEffect` 默认开启：直接翻转回落值，**不写迁移代码**。影响：存量用户升级后一插电就会看到动效，可用一键关闭；Reduce Motion 用户看到的是静态图标。
- `chargingTailColor` 无历史值 → 默认「偏青 · 能量」预设，同样不需要迁移。
- README：`README.zh-Hans.md:61` 的电池能力描述需要补一句；12 语言与截图建议随发布一起过。

## 待你确认（spec review 项）

1. **参数默认值**：尾巴长度 **32%** 可见弧（有效可见 ≈ 8.4pt）／渐变**线性**／周期 **1.8s**（行程 1.55s + 收束 0.25s）／亮珠**开、1.18×**／心跳强度 **1.0**。这些是 demo 里看着最舒服的一组，你可以只改其中任意项。
2. **预览卡「本地试播」**（见「设置、本地化与预览」）：要，还是不要。
3. **README 12 语言**是否本次一起更新，或留到发布时。
4. Demo `charging-effects-demo.html` 是丢弃件：定稿后删除，还是随 spec 一起提交存档。
