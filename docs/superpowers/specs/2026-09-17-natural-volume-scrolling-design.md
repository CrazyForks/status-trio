# 自然滚动音量调节设计

## 目标

用独立的“自然滚动”开关替代现有的“向上/向下”音量滚动方向选项，使鼠标和触控板在开启该选项时都表现为物理上滚增大音量；关闭时，音量方向跟随 macOS 当前报告的滚动方向。

MOS 等外部滚动工具不在应用内做特殊检测。用户可以按应用排除 Status Trio。该策略避免依赖第三方工具会变化的合成事件特征。

## 用户行为

新增布尔设置 `popupVolumeNaturalScrolling`，默认关闭，保持原有音量滚动行为。

### 开启

- 鼠标滚轮向远离用户的方向滚动时，音量增大。
- 触控板双指向上滑动时，音量增大。
- 行为不受 macOS“自然滚动”系统偏好影响。
- 实现上使用 `NSEvent.isDirectionInvertedFromDevice` 还原设备方向，再将“物理上滚”映射为增大。

### 关闭

- 不再还原系统对滚动方向的反转。
- 音量直接跟随 `NSEvent.scrollingDeltaY` 的方向。
- 当系统开启“自然滚动”时，触控板物理上滚会减小音量。
- 当系统关闭“自然滚动”时，触控板物理上滚会增大音量。
- 鼠标遵循相同的系统事件方向规则。

## 设置界面

状态面板设置的“面板滚动”分组中：

- 移除现有“调整方向”菜单行及其 `Up/Down` 选项。
- 新增“自然滚动”开关行。
- 开关位置放在“调整范围”之后。
- 关闭“调整音量”总开关时，不显示“调整范围”和“自然滚动”等从属设置。
- 旧的滚动方向持久化值保留，但不再由运行时代码读取。

用户文案：

- 英文标题：`Natural Scrolling`
- 英文说明：`When on, scrolling up on a mouse or trackpad increases volume. When off, volume follows the system's scrolling direction. If scrolling up still lowers the volume after turning this on, configure MOS, Scroll Reverser, LinearMouse, or a similar app to leave Status Trio unchanged, usually through an exception/ignore list (sometimes called an allowlist).`
- 简体中文标题：`自然滚动`
- 简体中文说明：`开启后，鼠标和触控板上滚都会增大音量；关闭后，音量跟随系统的滚动方向。如果开启后鼠标上滚仍然减小音量，请在 MOS、Scroll Reverser、LinearMouse 等应用中将 Status Trio 设为不处理，通常可加入例外/忽略列表（部分应用称为白名单）。`

以上英文和简体中文为基准文案；`Sources/StatusTrioCore/Resources/*/Localizable.strings` 中的本地化资源文件是最终文案权威来源。

## 数据模型与接口

`SettingsStore` 新增：

- `static let defaultPopupVolumeNaturalScrolling = false`
- `static let popupVolumeNaturalScrollingDefaultsKey = "popupVolumeNaturalScrolling"`
- `@Published var popupVolumeNaturalScrolling: Bool`

规则：

- 未保存该值时使用 `false`。
- 非布尔持久化值回退到 `false`。
- 修改后立即持久化。
- 保留 `popupVolumeScrollDirection` 字段、键和类型，以降低改动范围并为未来重新启用保留可能；生产代码不再读取该字段。

`PopupVolumeScrollAdjustment.volumeDelta` 的输入由 `direction: PopupVolumeScrollDirection` 改为 `usesNaturalScrolling: Bool`。

计算规则：

```swift
let scrollUpDelta = usesNaturalScrolling
    ? (isDirectionInverted ? -deltaY : deltaY)
    : deltaY
return scrollUpDelta * volumePerUnit
```

`StatusBarController` 从 `SettingsStore.popupVolumeNaturalScrolling` 传入该值。

## 测试

单元测试覆盖以下矩阵：

- 自然滚动开启、系统自然滚动开启、物理上滚：音量增大。
- 自然滚动开启、系统自然滚动关闭、物理上滚：音量增大。
- 自然滚动关闭、系统自然滚动开启、物理上滚：音量减小。
- 自然滚动关闭、系统自然滚动关闭、物理上滚：音量增大。
- 精确滚动和离散滚轮继续使用现有灵敏度。
- 非有限值和零增量继续被忽略。

设置测试覆盖：

- 默认值为关闭。
- 修改后跨实例持久化。
- 非布尔存储值回退为关闭。
- 旧的 `popupVolumeScrollDirection = .down` 不再影响音量调节入口。
- 现有 `popupScrollAdjustsVolume` 和 `popupVolumeScrollScope` 行为不变。

验证要求：

- `swift test`
- `swift build -c release`
- 因为改动涉及 SwiftUI 绑定，合并前运行 `publish=false` 的 release workflow 预检。

## 不在本次范围内

- 在应用内检测或兼容 MOS 的合成事件。
- 自动识别鼠标、触控板或具体硬件型号。
- 删除旧的 `PopupVolumeScrollDirection` 类型和持久化数据。
- 改变音量滚动区域或滚动灵敏度。
