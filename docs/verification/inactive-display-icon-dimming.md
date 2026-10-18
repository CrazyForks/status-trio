# 非焦点显示器：彩色菜单栏图标未随系统灰化

状态：**系统灰化边界已实测确认，承载方案未验证，正式修复未实现**。生产代码
未改动，只记录证据和可行边界，等真实双屏实验选定方案后再改
`StatusBarAnimationLayerPresenter`。

## 现象

多显示器时 macOS 会把非焦点显示器的菜单栏整体调暗。Status Trio 的模板部分
（圆环底轨、电量数字、Wi-Fi 等）会跟着变暗，但 AirPods 蓝色、供电绿色、
低电量黄色、临界电量红色这些彩色区域保持原来的亮度。

## 实测环境

| 项目 | 值 |
| --- | --- |
| 机器 | MacBook Pro，Apple M3 Max，macOS 27.0.1（26A434） |
| 焦点屏 | 内建 Liquid Retina XDR，3456×2234 @2x（当时前台为 Edge） |
| 非焦点屏 | XV272U，2048×1152 @2x，144 Hz |
| Space | `spans-displays = 0`，两屏各自独立菜单栏 |
| 复现 | `screencapture -x -R <screen>` 同时抓两屏菜单栏后逐像素对比 |

焦点屏上 Status Trio 图标：环为明亮的绿色，AirPods 为明亮的蓝色。
非焦点屏上同一图标：数字 `80` 降到约 1/4 亮度，而环和 AirPods 仍是高饱和的
绿色和蓝色。两屏的直接对照见本目录的
`inactive-display-menubar-compare.png`（上：焦点屏；下：非焦点屏）。

## 代码侧已确认的事实

- `IconSceneState.chromaticRegions` 把 `critical`、`lowPower`、`powered`、
  `bluetooth` 以及充电动画区域划为彩色区域，其余进 `templateRegions`。
- `StatusIconRenderer.menuBarLayers` 把模板区域渲染成 `isTemplate = true` 的
  `button.image`，把彩色区域渲染成单独的 `CGImage`。
- `StatusBarAnimationLayerPresenter` 把该 `CGImage` 作为 `CALayer.contents`
  直接挂到 `NSStatusBarButton.layer` 上，之后每帧只换 `contents`。
- `StatusBarRenderKey` 不含任何屏幕焦点状态，`screenParametersCancellable`
  只在屏幕数量/分辨率变化时重绘。

AppKit 头文件对 `NSStatusBarButton` 的说明是：只有模板图片会拿到“正确的菜单栏
样式”；`NSStatusItem.view` 也被标注为次选方案，因为 button 才能自动调整外观。

## 阶段 A：最小实验（未完成）

独立 AppKit 探针（临时文件，未入库），每个 item 都同时包含一条模板横条和一个
彩色圆，一次对比多种承载方式：

| 策略 | 呈现方式 | 真实非焦点屏结论 |
| --- | --- | --- |
| A0 | 模板 `button.image` + 彩色 `CALayer`（现网做法） | **彩色不变暗，模板部分变暗** |
| A1 | 模板 `button.image` + layer-backed 子视图承载彩色 | 待验证 |
| A2 | 一整张非模板 `button.image` | 待验证 |
| A3 | 模板 `button.image` + 自绘 `NSView` | 待验证 |

本机合盖使用外接屏（`AppleClamshellState = Yes`），内建屏无法作为可操作屏幕。
尝试用私有 `CGVirtualDisplay` 造第二块屏后，系统只在该屏画自己的菜单项，
**不镜像任何第三方 status item**：真实 Status Trio 和独立探针都没有出现在
虚拟屏上，抓到的是一份停止更新的菜单栏快照。因此 A1–A3 在虚拟屏上的结果
全部作废，没有据此得出“各方案是否可行”的结论，也没有被当成双屏验收。

目前只能由实测确认 A0 的边界：**系统灰化模板内容，但不会灰化直接挂在
`NSStatusBarButton.layer` 上的彩色 overlay**。彩色内容改由子视图承载后，
系统是否接管其外观，仍必须在真实非焦点显示器上验证。

用探针把 A0 的彩色圆放进 `button.image`（整张非模板图）做对照时，该 item 在
非焦点屏上也没有渲染出来，说明 macOS 不会在非焦点菜单栏里为这个额外探针
创建副本。因此“非模板整图是否会被灰化”同样没有可信结论，不以这次 A2 观察
作为根因证据。

## 外部项目证据

- Stats #2131 的修复（`11b34498c4`）只针对**完全没有设置 image** 的自定义
  `NSStatusItem.view`：补一个空 `NSImage()` 让系统把它纳入菜单栏合成。
- Status Trio 的 `button.image` 一直非空，Stats 那个空图片修复不适用。
- 与本问题同源的报告（AlDente #1322 等）把彩色菜单栏图标不灰化归为
  Sequoia 起的系统行为差异，而非单个 app 的 bug。

## 为什么尚未改生产代码

计划要求“只有候选在真实双屏上确认彩色区域能与系统一致灰化，才推广”。
目前只有 A0 的边界被真实复现，A1/A3 没有可信实验条件；此时改
`StatusBarAnimationLayerPresenter`，等于把未经验证的承载方式直接发给用户。

现有公开 API 里没有“当前菜单栏是否处于非焦点显示器”的查询：
`NSApp.isActive` 表示 app 是否前台，`NSScreen.main` 表示键盘焦点屏幕，
`NSStatusBarButton.effectiveAppearance` 只在 Space 切换提交后更新，三者都不能
可靠推出系统针对**每个屏幕副本**的灰化状态。按计划，不能用鼠标位置或
`NSApp.isActive` 猜一个全局布尔值去调暗彩色层——同一 status item 在不同屏幕上
由系统分别合成，一个全局值会把焦点屏也调暗。

## 可选下一步（需要真实双屏确认）

1. **优先**：在真实双屏上重跑 A1/A3 探针，确认 AppKit 是否会对状态栏内的子视图
   应用非焦点外观；只有能读到逐屏状态时才接入 `StatusBarAnimationLayerPresenter`。
2. 若均不可行：把限制写进 `docs/known-limitations.md`，与 #112 的彩色区域限制
   并列，并附本文件和截图说明。
3. 不建议：常驻 `layer.opacity`、按 `NSApp.isActive`/`NSScreen.main` 调暗、
   整图改模板（会丢失状态色）、每帧换整张 `button.image`（破坏 20 fps 预算）。

## 回归边界

本次没有生产改动，因此未触发 Issue #30、Dock、充电动画的行为变化；恢复硬件
条件后仍需按计划运行 `swift test --filter Issue30WiFiAlignmentTests`、`swift test`
与 `swift build -c release`。
