# Status Trio — macOS 13 Ventura 兼容性改造执行计划

> 目标仓库：`https://github.com/lingyired/status-trio`  
> 基线：执行时以仓库最新 `main` 为准，先检查本计划中提到的文件是否仍与源码一致。  
> 目标：把最低运行系统由 macOS 15.0 正式降低到 **macOS 13.0 Ventura**，保留 Apple Silicon / Intel Universal 发行方式，不影响 macOS 26+ 的原生界面。  
> 使用者：Codex / AI coding agent  
> 状态：待执行；本计划源于静态源码审查，**不代表已在 Ventura 编译或实机验收**。

## 0. 执行原则与非目标

### 必须遵守

1. **保留一套代码、一份 Universal App、一个自动更新渠道**。不要创建旧版 Lite App、永久性旧版分支或另一份用户配置目录。
2. 最低 Deployment Target 设为 **macOS 13.0**。编译继续使用仓库要求的 **macOS 26 SDK 或更高**。保留 `scripts/build-app.sh` 中用于确保新版 AppKit 视觉风格的 SDK 门禁，以及对 `LC_BUILD_VERSION` 的修正和验证。预期主程序每个架构切片均为 `minos 13.0` 且 `sdk >= 26.0`。
3. **保留现有 UI 与交互**：不能为了通过编译删除状态卡片、重画设置界面、默认关闭蓝牙、取消动画、放弃 Dock 或删除移动设备电量功能。
4. 对老系统缺失的 API 采用最低风险的局部兼容写法；优先使用从 macOS 13 起就可用的公共 API，仅在确实必要时加入 `#available(macOS 14/15/26, *)` 和兜底实现。
5. 不引入新的私有 API，不扩大系统权限，也不改变现有遥测默认策略和隐私行为。避免增加轮询、空闲 CPU/内存或额外的高频监控。
6. 保持现有 `StatusTrioCore` / Presentation / UI / Monitor 架构与菜单栏、Dock 图标状态同步约束；不要借兼容性任务做大规模重构。
7. **不自动发布** GitHub Release，不自动修改线上 `appcast.xml` 现有历史条目，不推送发布标签。可以在专用分支提交兼容性改动；任何线上发布均等待用户单独授权。
8. 不覆盖工作区的既有未提交修改。开始前记录当前 `HEAD`、dirty 状态、测试工具链；如工作区有用户修改，使用隔离 worktree 或保留原修改。

### 不在本次范围

- macOS 12 Monterey 及以下兼容。
- 为 Intel Mac 新实现 DDC/CI 外接显示器音量驱动。现有 `DDCDisplayTransport.swift` 是 `#if arch(arm64)` 的 Apple Silicon 路径，Intel 上原本不支持的 DDC 能力不属于本次回归。
- 改写整个 SwiftUI 设置窗口或推翻现有 `Swift 6` 工具链。
- 引入与兼容性无关的新功能、服务或依赖版本升级。

## 1. 开工前基线与检查（P0）

### 步骤

1. 更新代码并记录 `git rev-parse HEAD`、分支名称、`git status --short`；在干净分支或新 worktree 执行，推荐 `codex/macos13-compatibility`。
2. 阅读 `AGENTS.md`、`Package.swift`、`release.json`、`Support/Info.plist`、`.github/workflows/release.yml`、`scripts/build-app.sh`、`scripts/verify-platform-version.sh`、`scripts/verify-mobile-battery-bundle.sh`。以实际约束为准。
3. 核实 CI 的接受环境：`macos-26`、Xcode 26.6、Swift 6.3.3。继续保留编译时 SDK 26+ 约束。
4. 运行基线：`swift test`、`swift build -c release`。记录结果、失败项目和已有 warning，不将既有失败伪称为本次引入。
5. 先全面扫描版本常量、可用性及新 API。至少执行：

```bash
rg -n 'macOS\(\.v15\)|LSMinimumSystemVersion|MINIMUM_MACOS|EXPECTED_MINOS|minimumMacOS|min_system_version|MINIMUM_SYSTEM_VERSION|minimumSystemVersion|15\.0' \
  Package.swift Support scripts release.json .github Sources Tests README* AGENTS.md

rg -n '#available\(macOS|@available\(macOS|\.onChange\(|\.onKeyPress\(|\.focusEffectDisabled\(|\.onGeometryChange\(|\.scrollPosition\(|\.glassEffect\(|\.symbolEffect\(|\.contentTransition\(|\.sensoryFeedback\(' Sources Tests
```

注意：上述 `15.0` 的结果中有历史文档、Apple API 可用性判断、已发布 appcast 条目和用户可见变更记录；**不得全局替换**。

### 完成标准

- 有可复现的基线测试记录。
- 明确工作分支及基线 SHA。
- 列出所有已发现的编译阻塞点和运行时风险，标注文件与行号；未确认项标记为待验证。

## 2. 统一最低版本与构建元数据（P1）

### 必改文件

| 文件 | 当前基线 | 目标修改 |
|---|---|---|
| `Package.swift` | `platforms: [.macOS(.v15)]` | 改为 `.macOS(.v13)` |
| `Support/Info.plist` | `LSMinimumSystemVersion = 15.0` | 改为 `13.0` |
| `release.json` | `min_system_version = 15.0` | 改为 `13.0` |
| `scripts/build-mobile-battery-helper.sh` | `MINIMUM_MACOS="15.0"` | 改为 `13.0` |
| `Support/mobile-battery-dependencies.json` | `minimumMacOS = 15.0` | 改为 `13.0` |
| `scripts/verify-mobile-battery-bundle.sh` | `EXPECTED_MINOS="15.0"` | 改为 `13.0`，继续校验所有架构/动态库 |
| `scripts/update-appcast.rb` | CLI 兜底 `options[:minimum] ||= "15.0"` | 改为 `13.0`；新增版本仍以明确传参为准 |
| `scripts/validate-appcast-notes.sh` | 默认 `MINIMUM_SYSTEM_VERSION=15.0` | 改为 `13.0`，不修改旧版本记录 |

如现有代码已引入统一配置入口，优先复用；不要为了本次改造引入过度复杂的配置生成框架。

### 特别约束

- **保留** `scripts/build-app.sh` 要求 SDK >= 26 的检查和 `vtool -set-build-version macos "$BUILT_MINOS" 26.0` 逻辑；新的 `$BUILT_MINOS` 应自动成为 `13.0`。
- `scripts/verify-platform-version.sh` 继续对主程序每个架构切片验证 `minos` 和 `sdk`；建议增强为拒绝非预期架构或缺少切片（如现有验证已覆盖，则不要重复实现）。
- Bundle `LSMinimumSystemVersion` 与 Mach-O `minos` 必须一致。
- 必须检查嵌入的 Sparkle Framework、Sparkle helper/XPC 可执行文件、MobileBattery Helper 及 dylibs 的最低 OS 和架构，不能只看 `.app/Contents/MacOS/StatusTrio`。
- `appcast.xml` **历史 item 继续保留原 `minimumSystemVersion=15.0`**；只允许未来新版本的 item 采用 `13.0`。任何测试更新源必须写入临时路径，不得覆盖线上 appcast。

### 完成标准

- 对 macOS 13 Deployment Target 的 SwiftPM 编译可以进入 Swift 编译/链接阶段；若失败，准确记录源文件、API 和诊断，不通过修改 SDK 版本字段掩盖不兼容。
- 构建和发布元数据没有互相冲突的版本声明。

## 3. SwiftUI 13 兼容改造（P1）

### 3.1 把 17 处新式 `onChange` 改成 macOS 13 兼容写法

macOS 14 引入的新形式 `.onChange(of:) { oldValue, newValue in ... }` 不应直接用于 macOS 13 Deployment Target。这里已定位到 6 个源码文件、共 17 个调用：

| 文件 | 数量 | 当前审查位置（可能随提交变化） |
|---|---:|---|
| `Sources/StatusTrioCore/UI/BluetoothDeviceList.swift` | 5 | 约 124–138 行 |
| `Sources/StatusTrioCore/UI/BluetoothStatusView.swift` | 3 | 约 208–212 行 |
| `Sources/StatusTrioCore/UI/VolumeControlsView.swift` | 2 | 约 67–68 行 |
| `Sources/StatusTrioCore/UI/AudioInputControlsView.swift` | 2 | 约 114–117 行 |
| `Sources/StatusTrioCore/UI/IconGuideView.swift` | 2 | 约 417–420 行 |
| `Sources/StatusTrioCore/UI/Settings/StatusIconPreviewCard.swift` | 3 | 约 26–36 行 |

改法示例：

```swift
// Before — macOS 14+
.onChange(of: draftVolume) { _, newValue in
    updateVolume(newValue)
}

// After — macOS 13 可用
.onChange(of: draftVolume) { newValue in
    updateVolume(newValue)
}
```

- 对未使用 `oldValue` 的调用，直接采用旧版单参数形式。
- 如果未来代码有真正依赖旧值的调用，请用单独的 `@State` 或可重用的兼容逻辑保留旧值语义，避免监听顺序变化和重复回调。
- 这些位置涉及蓝牙可见列表授权、音量草稿值、麦克风输入、充电动画及首次引导；不能因为迁移而造成自触发循环、重复监听、额外轮询。
- 更新和新增对应单元测试。完成后用 `rg` 确认没有遗漏的两参数新写法。

### 3.2 设置选项卡的键盘快捷交互

目标：`Sources/StatusTrioCore/UI/Settings/SettingsChrome.swift` 的预览选项按钮附近，当前有：

- `.focusEffectDisabled()`（新 API；需兼容隔离）。
- `.onKeyPress(.leftArrow/.rightArrow/.upArrow/.downArrow/.space/.return)` 6 处（macOS 14+）。

实施要求：

1. 优先以 macOS 13 支持的 `.onMoveCommand` 统一处理方向键，调用现有 `selectRelative(offset:)`，保持左右 RTL 适配及循环选项行为。
2. `Space` 和 `Return` 优先使用原生 Button 焦点/激活行为。**必须真机验证两种按键**；不能假定 `.onMoveCommand` 自动处理它们。
3. 如 macOS 13 的原生 Button 无法满足 Enter/Space 的完整体验，再引入**局部** AppKit `NSViewRepresentable` / 明确限定的键盘处理适配器；不要添加全局事件监听器、常驻键盘钩子或抢占其他 App 的快捷键。
4. `.focusEffectDisabled()` 放进 `#available(macOS 14, *)` 的局部修饰器封装；macOS 13 可保留系统焦点环。优先保持可访问性，不可为了外观去掉键盘聚焦。
5. 保留 `accessibilityLabel`、`isSelected`、按钮语义、降低动态效果和焦点行为。
6. 为 LTR/RTL 导航、选项选择、可访问性添加测试；对原有测试做最小更新。

### 3.3 扩大 SwiftUI API 可用性审查

- 在整个 `Sources/`（不仅 UI）扫描所有 API 可用性，使用**真实的 macOS 13 Deployment Target 编译结果**作为最主要判据。
- 针对 `NavigationStack`、`focusable`、`scroll`、`safe area`、SF Symbols、设置窗口内容和新样式逐项确认；只有确实报错或运行行为异常时才增加分支。
- 保留 macOS 26+ 的正常视觉外观，不能把 macOS 26 SDK 构建换成 macOS 13 SDK。

### 完成标准

- `swift build -c release` 在 `Package.swift` 最低 macOS 13 下通过。
- 既有 macOS 26+ UI 行为与布局不退化，Ventura 上键盘和菜单交互可以使用。
- SwiftUI 改动的所有相关测试通过。

## 4. MobileBattery 原生 Helper 与依赖链（P1，高风险）

涉及：

- `scripts/build-mobile-battery-helper.sh`
- `scripts/verify-mobile-battery-bundle.sh`
- `Support/mobile-battery-dependencies.json`
- `Support/MobileBatteryHelper/*`
- `Sources/StatusTrioCore/Monitoring/MobileBatteryHelperReader.swift`
- 现有打包的 OpenSSL、libplist、libimobiledevice-glue、libusbmuxd、libtatsu、libimobiledevice 等动态库。

### 步骤

1. 不改变已固定的上游版本/commit（除非确认某个已固定版本无法以 Deployment Target 13.0 构建，此时先记录原因，再提出局部修复）。
2. 清理或使构建缓存重新生成。确认缓存键含最低系统版本（现有脚本 `BUILD_KEY` 已含 `MINIMUM_MACOS`），避免复用以 15.0 编译的依赖。
3. 对 `arm64` 和 `x86_64` 分别编译 Helper 以及**全部**原生依赖；保留现有 RPATH 重写、签名和 NOTICE / 第三方许可证机制。
4. 用 `vtool -show-build -arch ...` 核实 Helper 和每个 Mach-O dylib 的 `minos <= 13.0`，不能只确认编译器参数写了 13.0。
5. 用 `lipo -archs` 检查 Universal 架构切片；用 `otool -L`、`otool -l` 检查路径、加载命令和动态库链接。核实所使用的系统框架/符号在 macOS 13 可用；仅修改 `minos` 不能修复新的系统符号依赖。
6. 保留并运行 `verify-mobile-battery-bundle.sh`、`test-mobile-battery-helper.sh`、现有 RPATH 相关测试。检查这些脚本的静态断言是否仍针对 15.0，并更新目标值。
7. 在 macOS 13 上实际验证 Helper **能启动、能退出、不会崩溃**，以及已配对/已信任 iPhone/iPad 的电量读取。不得只以空设备列表的成功返回当作完整功能通过。
8. 如果单个设备/系统场景不可用，先调查具体协议和系统权限差异；确实无法解决时提供**局部功能不可用状态**，不得阻断主 App 启动，也不得默认关闭全部蓝牙功能。

### 完成标准

- Helper 和所有 bundled dylib 双架构符合最低版本与签名要求，构建/验证脚本通过。
- Ventura 上 Helper 正常启动，错误路径不会拖垮主进程。
- 物理设备读取能在具备测试条件时通过；如果尚无设备，则明确标记该项 **BLOCKED / 未验证**，不能宣称完整支持。

## 5. 硬件与系统行为专项测试（P2）

### 5.1 CoreAudio / 麦克风

源码 `Sources/StatusTrioCore/Audio/CoreAudioOutputController.swift` 已在 `#available(macOS 15.0, *)` 之外提供传统 CoreAudio 兜底：

- **保留** macOS 15+ `AudioHardwareDevice` / `AudioHardwareSystem` 实现。
- 确认 Ventura 下执行 `setLegacyDefaultOutputDevice()` 和 `audioDeviceCanBeDefault()`。
- 检查音量、静音、输出设备列表、默认输出切换、蓝牙音频中途断开、HDMI/显示器音箱不可调音量时的 UI 表现。
- 对输入设备验证默认设备选择、输入音量、静音、状态监听和重启后恢复；旧系统不支持的控制应正确显示为不可用，而不是成功但无效果。
- 切换设备之后菜单栏与 Dock 的状态必须保持一致。

### 5.2 Wi-Fi、网络和 VPN

- 使用 Ventura 真机验证 Wi-Fi 名称授权、连接状态、RSSI、5/6GHz 频段显示、Wi-Fi 开关、附近网络扫描与网络列表。
- 验证有线网络、主链路、网络异常优先级、VPN 状态以及代理状态（若对应功能已在 main 中）。
- 重点检查系统设置页跳转：`StatusBarController.wifiSettingsURLs`、Network、Bluetooth、Battery、Sound、Location。
- 对 URL 路由的判断要以**实际打开的设置页**为准；单凭 `NSWorkspace.open()` 返回 `true` 不能证明进入了正确 pane。不要为了本次兼容重新引入已修复的 Wi-Fi 错误路由。
- 不触碰或读取 Wi-Fi 密码，不添加 Keychain 访问。

### 5.3 Bluetooth、AirPods、移动设备

- 断连/重连事件、蓝牙音频图标替代、蓝牙开关、设备类别、鼠标/键盘等断开确认、蓝牙设备电量。
- 有真实 AirPods 时验证 L/R/Case 电量与降噪/通透/自适应控制（受型号支持能力约束）。
- `Monitoring/BluetoothBatteryReader.swift` 的 `"airpods.chargingcase"` 源码注释注明该 SF Symbol 自 macOS 14 提供；核查 `UI/BluetoothBatteryLevelText.swift` 的文字 fallback，并覆盖旧版系统 SF Symbols 不存在的场景。图标/符号不可用不能出现空白按钮或丢失电量数值。
- 测试设备缺失、权限拒绝和睡眠唤醒，确保不会触发无上限的重试与 CPU 占用。

### 5.4 DDC 和硬件差异

- `Audio/DDCDisplayTransport.swift` 当前核心访问使用 `#if arch(arm64)`，Intel 为 `nil` fallback。本次不得为了 Ventura 改造成新的 Intel DDC 驱动。
- **特别检查 Apple Silicon Ventura 的 DDC 私有/非公开符号是否能动态装载**；必要时通过实际运行、`otool` 或动态符号检查确认，不允许把只在较新系统存在的必需符号放到 13.0 App 启动时的强依赖中。
- DDC 硬件不支持时，保留已有“无法调节”的清晰状态；不要假报为成功。

### 5.5 原生窗口与性能

- 分别验证菜单栏模式、Dock 模式和两者同时显示。
- 验证状态弹窗定位、全屏应用下打开、屏幕缩放/刘海区域、设置窗口、首次引导、系统深浅模式。
- 验证充电动画/静止状态与 `Reduce Motion`；旧设备上必须特别关注空闲 CPU、内存和唤醒频率，不能因兼容层引入定时轮询。
- 确保 macOS 26+ 原生外观和现有行为无退化。

## 6. Sparkle、发布流程与历史版本（P2）

1. 保留现有 `Package.resolved` 锁定的 Sparkle 版本（审查时为 2.9.6），除非实证出现与 Ventura 相关的限制。先测试，后决定升级依赖。
2. 确认被复制进 `.app` 的 Sparkle Framework 和自带 helper/XPC 可执行文件符合 macOS 13 的最低支持约束；主程序可运行但 Sparkle 子进程不能启动视为验收失败。
3. 新的 release 的 `sparkle:minimumSystemVersion` 应为 `13.0`。历史 `appcast.xml` 条目必须保留原始兼容要求；不要为旧 DMG 伪造 13.0 支持。
4. 使用**独立临时 appcast** 测试新 item、历史 item 保留、各语言内容、签名参数；不要直接写入线上 feed。
5. 不修改现有 appcast 公钥与更新签名密钥配置，保留版本/build 单调递增约束。
6. `.github/workflows/release.yml` 的原构建机与工具链保留，必要时增加不发布的编译验证、二进制 Metadata 检查及 Artifact 产出。
7. 如需要预检，沿用 `AGENTS.md` 的非发布工作流方式，在准备好**新且不冲突**的版本号与 build 后执行：

```bash
# 示例模板：请替换为真实的、严格递增且尚未发布的版本/build，且保持 publish=false。
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref codex/macos13-compatibility \
  -f version=<UNRELEASED_VERSION> \
  -f build=<UNRELEASED_BUILD> \
  -f publish=false
```

8. 该 workflow 预检只证明 CI 构建和打包通过，不能替代 Ventura 上的运行验证。

## 7. 自动测试与正式验收标准（P2）

### 7.1 自动化命令

```bash
set -euo pipefail
swift test
swift build -c release
UNIVERSAL_BUILD=1 bash scripts/build-app.sh release no-open

APP="dist/StatusTrio.app"
BIN="$APP/Contents/MacOS/StatusTrio"

lipo -archs "$BIN"
bash scripts/verify-platform-version.sh "$BIN" 13.0 26
bash scripts/verify-mobile-battery-bundle.sh "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# 人工进一步审查动态链接库及 SDK / minos
otool -L "$BIN"
```

- 上述仅在能够使用 macOS 26+ SDK 与 Xcode 26.6 的 Mac 构建机上运行。
- 继续执行现有相关的测试脚本；以其现有参数约定为准，不能编造命令参数。
- 建议增加静态回归测试，断言主程序/Helper/manifest/release config 所声明的最低系统一致；以及 appcast 旧 item 不被改写。

### 7.2 运行系统验收矩阵

| 系统 / 架构 | 必测程度 | 验收重点 |
|---|---|---|
| macOS **13.x / x86_64**（Intel） | **正式支持必须测试** | 启动、菜单栏、Dock、Wi-Fi、蓝牙、音量、系统设置、Sparkle、睡眠唤醒 |
| macOS **13.x / arm64**（Apple Silicon） | **正式支持必须测试** | 同上，加 DDC 兼容性和移动设备电量 Helper |
| macOS 14.x / Intel 或 ARM | 回归 | 现代 SwiftUI 兼容行为、SF Symbol fallback |
| macOS 15.x | 回归 | CoreAudio 新旧路径、原有状态逻辑 |
| macOS 26 / 27 | 回归 | 新版 SDK 原生窗口外观、动画、Dock/菜单栏一致性 |

可在可用的物理设备、受控 VM 或测试者机器完成，不要求 CI 本身直接提供 `macos-13` runner。但**没有跑过的系统必须明示未验证**。不要仅凭 `minos=13.0` 和编译成功对外宣称全面支持。

### 7.3 必须新增或调整的测试

- `onChange` 转换前后对于 Volume、Bluetooth visible list / authorization、Charging effect、Audio Input 的状态行为不变。
- macOS 13 Settings option keyboard 行为：LTR/RTL 左右方向、上下方向、Space、Return、焦点和 accessibility。
- SF Symbol 缺失时 AirPods Case 有文字兜底，蓝牙及音频设备图标有通用 fallback。
- 部分系统硬件 API 不可用时不会使菜单栏、Dock 或整个 App 崩溃。
- Main/App Bundle/Helper/dylib `minos` 与架构一致，主程序 `sdk >= 26`。
- 保留菜单栏与 Dock 图标渲染/设置同步相关的现有测试。
- 新 appcast item 的最低版本为 13.0；旧 item 原封不动。

## 8. 文档、版本说明与质量门禁（P3）

1. 更新 `README.md`、`README.zh-Hans.md` 以及其他 README 本地化文件的下载徽章、系统要求与必要注释：`macOS 13 Ventura or later` / `macOS 13 Ventura 或更高版本`。
2. 修改 `AGENTS.md` 明确新的部署目标 `13.0`、仍须使用 26+ SDK、测试/Helper/旧系统规则，不删现有 CI 工具链和发布安全约束。
3. 更新需要描述支持范围的当前维护文档。不要批量重写历史计划、历史 release notes 或已发布 appcast 文本。
4. 新 release 的多语言说明应强调“最低支持版本扩展到 macOS 13”，仅在完成实机验收后使用“正式支持”；若部分硬件能力有限，准确列明。
5. 新增 `docs/macos13-compatibility-verification.md`（名称可调整），记录：baseline SHA、环境、修改文件、构建/测试命令、CI run ID、两种架构的二进制检查、真机测试结果、未验证功能、已知限制。

## 9. 分阶段执行 / Codex 工作顺序

Codex 需按以下顺序处理；**每个阶段有可验证输出后再进入下一阶段**。发现新兼容点可追加到记录，但不要跳过验证。

- [ ] **Phase A — Baseline**：记录 `HEAD`/工具链、运行原始测试、代码检索、创建专用分支/工作树。
- [ ] **Phase B — Deployment target**：修改配置、主程序/Helper 校验的版本常量、保持 SDK 26 门禁。
- [ ] **Phase C — SwiftUI**：17 处 `onChange`、6 处 `.onKeyPress`、`.focusEffectDisabled` 和其余编译 API 问题；添加相应测试。
- [ ] **Phase D — Build**：构建 release + Universal，修复最低版本下的编译/链接错误；校验主程序每个 slice。
- [ ] **Phase E — Helper**：完整重新编译原生依赖、检查所有内嵌 Mach-O 的 `minos`/架构/RPATH/签名，并运行相关脚本。
- [ ] **Phase F — Regression**：Swift tests、功能测试、静态文档和 appcast 生成测试、非发布 CI 预检。
- [ ] **Phase G — Ventura runtime**：macOS 13 Intel + Apple Silicon 测试，解决真实旧系统运行问题；其他 OS 回归。
- [ ] **Phase H — Documentation**：更新 README、AGENTS 与验证报告，准备 release notes 草案（不发布）。

若 Codex 所在环境**没有** Ventura 真机/VM：必须完成能完成的实现与静态/CI 检查，生成一份清晰的人工验收 checklist 和未验证项目清单，**不得用“通过”代替实际运行验证**。

## 10. 交付与验收定义（Definition of Done）

满足全部以下条件才能标记为“正式支持 macOS 13”：

- [ ] `Package.swift`、Info.plist、release config 和原生 Helper 配置最低版本一致为 13.0。
- [ ] Swift 构建与测试通过，所有在 Deployment Target 13.0 下的 API 可用性报错已解决。
- [ ] 主程序、Helper、所有捆绑动态库/相关辅助二进制的部署目标及动态符号满足 Ventura，Universal 切片完整。
- [ ] 仍使用 SDK 26+ 构建，原有新版 macOS 原生外观要求通过。
- [ ] 旧版 SwiftUI 键盘、变化监听、可访问性、SF Symbol 兜底工作正常。
- [ ] Wi-Fi、VPN/网络、蓝牙、CoreAudio、麦克风、电池、Dock/菜单栏主要功能通过 macOS 13 验收。
- [ ] MobileBattery Helper 在 Ventura 上可启动且故障不影响主程序；真实手机读取经过测试或被清晰标注为已知限制（若限制影响核心承诺，不能宣称全面无差异）。
- [ ] 在 **Intel macOS 13** 和 **Apple Silicon macOS 13** 实际启动并执行测试；不存在已知致命问题。
- [ ] Sparkle 的新版本更新路径、历史更新兼容、签名与 appcast 校验通过。
- [ ] 所有现有 CI、测试及新的兼容性检查通过，旧版用户与 macOS 26+ 功能没有回归。
- [ ] 文档、测试日志、已知问题完整；未进行自动发布。

### Codex 最终回复必须包含

1. **具体变更清单**：文件路径、修改内容、必要性。
2. **验证结果**：命令、通过/失败数、构建的架构和 `LC_BUILD_VERSION` 值、CI 结果（如执行过）。
3. **运行验证矩阵**：分别列出 macOS 13 Intel、macOS 13 ARM、14、15、26/27 的 `PASS / FAIL / BLOCKED / NOT RUN`，不得推定通过。
4. **已知限制、后续需要真人/硬件测试的项目**。
5. **Git 状态**：基线 SHA、最终 HEAD、工作树状态、是否创建提交/PR、未发布声明。
6. **不相干改动说明**：保证没有删功能、替换遥测隐私默认值或改变新版原生外观。

## 11. 推荐立即开始的第一组命令

```bash
# 从仓库根目录开始；先检查工作区，以免覆盖现有修改
git status --short
git rev-parse HEAD
swift --version
xcrun --sdk macosx --show-sdk-version

# 若原仓库工作区已干净，可以创建专用分支：
git switch -c codex/macos13-compatibility

# 先验证基线再修改
swift test
swift build -c release

# 按 Phase B 修改平台和版本常量，然后让编译器指出剩余 API 阻塞
swift build -c release
```

> 执行补充：如果 `codex/macos13-compatibility` 已存在，使用合适的新分支名，不要强制覆盖。若当前存在未提交的用户修改，优先创建新 worktree 或请任务执行环境采取不会覆盖已有工作的方法。构建/CI 环境缺失时，不要伪造测试结果。

---

**最终目标**：让同一个 Status Trio Universal App **真正运行于 macOS 13+**，并继续保留 macOS 26+ 的 SDK 26 原生体验；兼容性声明必须以最低系统上的实机验证为依据，而非仅修改 `15.0 → 13.0`。
