# macOS 13 Compatibility Implementation Plan

> **For agentic workers:** 使用 `executing-plans` 逐任务执行；只有用户明确选择并行代理后才使用 `subagent-driven-development`。实现必须交给用户指定的 `gpt-6-luna`，不要在其他模型上开始实现。下面的复选框追踪执行状态；本轮仅制定计划。

**Goal:** 同一个 Universal App 真正运行于 macOS 13+，保持 macOS 26+ 原生外观、现有功能和同一更新渠道。

**Architecture:** 降低部署目标而不降低构建 SDK；对 SwiftUI 缺失 API 做局部兼容，保持现有状态与呈现架构。主程序、原生 MobileBattery 依赖链和 Sparkle 子程序分别检查二进制元数据及运行行为；构建成功不等同于 Ventura 运行成功。

**Tech Stack:** Swift 6、SwiftUI / AppKit、SwiftPM、Objective-C/C 原生 Helper、Sparkle 2.9.6、Bash/Ruby；CI 为 macos-26 / Xcode 26.6 / Swift 6.3.3。

**Spec:** `docs/superpowers/specs/2026-10-08-macos13-compatibility-reference.md`。这是用户参考文档的原样副本，不是追加的执行授权；文档中的发布、提交、最终汇报指令不得扩大本轮“新建分支/worktree、列计划”的请求范围。冲突时以当前用户请求和 AGENTS.md 为准。

## Global Constraints

- 最低运行系统 13.0，构建 SDK >= 26.0；主程序每个 slice 为 minos 13.0 / sdk >= 26.0，保留 build-app 的 SDK 门禁与平台验证。
- 单代码库、单 Universal App、同一配置目录及 Sparkle 渠道；不支持 macOS 12，不实现 Intel DDC 驱动，不升级无关依赖。
- 不删除功能，不扩大权限，不改变遥测隐私默认值；菜单栏 / Dock 图标兼容修改必须同批同步。
- 禁用 isolated deinit、实验性绕过及 weak let；MainActor / bindings / generics / resources 修改后必须完成非发布 CI 预检再合并。
- 本轮和默认后续执行均不发布、不写线上 appcast、不推标签。实施提交前运行 swift test 和 swift build -c release；每次 CI 失败登记 docs/swift-ci-compatibility.md。

## Review Focus

1. 音量拖动及设备切换：变化监听不能导致双写、反馈循环或将不可读值显示为可调节。归 Task 2 自动测试 + Task 5 实机。
2. Ventura 原生按键：方向键 LTR/RTL、首尾循环、Space/Return、Tab 和 VoiceOver 不抢占其他控件。归 Task 2 测试 + Task 5 实机。
3. 旧 Helper 缓存及一个切片仍为 15.0：必须检测并拒绝错误产物，不能改 load command 冒充重新编译。归 Task 3 负例。
4. 不存在的 SF Symbol 或不可装载的 DDC 符号：保留文字/不可用状态，主程序不得启动崩溃。归 Task 4 检查 + Task 5 实机。
5. 更新 feed 历史记录及 Sparkle XPC：旧版本最低要求不变，子程序可在 Ventura 启动，签名参数不变。归 Task 1 临时 feed 测试 + Task 4/5。

## 已建立的隔离与基线

- 日期：2026-10-08（Asia/Shanghai）。
- 分支：`codex/macos13-compatibility`。
- Worktree：`/Users/lingsmbp/.codex/worktrees/macos13-compatibility/status-trio`。
- 基线：fetch 后 `origin/main` = `be80a4ce12d691cb9696127eacd94c0040694965`。
- 原工作区停留在 `codex/integrate-2.0-as-1.5.0` / `d84238d39feeab6e2e8a3ac1972d8ccb55b1ffc1`；原有 `dist-test/` 与 `docs/superpowers/plans/2026-10-01-app-telemetry-integration.md` 未触碰。
- 本地：Apple Swift 6.4 / macOS SDK 27.0 / arm64-apple-macosx27.0.0；不代表 CI 或 Ventura 验收。
- 本轮基线结果写于末尾，执行者仍需在开始实现前确认 Git 状态。

```bash
cd /Users/lingsmbp/.codex/worktrees/macos13-compatibility/status-trio
git status --short
git branch --show-current
git rev-parse HEAD
swift --version
xcrun --sdk macosx --show-sdk-version
```

## 文件与边界

| 单元 | 修改或新增文件 | 责任 |
|---|---|---|
| 版本与更新约束 | Package.swift、Support/Info.plist、release.json、Support/mobile-battery-dependencies.json、scripts/build-mobile-battery-helper.sh、scripts/verify-mobile-battery-bundle.sh、scripts/update-appcast.rb、scripts/validate-appcast-notes.sh | 运行目标统一为 13.0；历史 feed 不动 |
| SwiftUI 监听 | UI/BluetoothDeviceList.swift、BluetoothStatusView.swift、VolumeControlsView.swift、AudioInputControlsView.swift、IconGuideView.swift、Settings/StatusIconPreviewCard.swift（均在 Sources/StatusTrioCore/） | 17 处变化监听的低版本兼容 |
| 设置键盘 | Sources/StatusTrioCore/UI/Settings/SettingsChrome.swift；必要时新建 Settings/SettingsKeyboardCompatibility.swift | 方向、激活、焦点；不加全局监听 |
| 包与风险审计 | scripts/build-app.sh、verify-platform-version.sh、verify-mobile-battery-bundle.sh、.github/workflows/release.yml；仅确认缺陷后修改 DDCPrivateAPI / DDCDisplayTransport / BluetoothBatteryLevelText | 全包二进制 / 强链接 / 缺符号检查 |
| 证据与验收 | docs/macos13-compatibility-verification.md、README.md / README-*.md（以实际文件为准）、AGENTS.md、release-notes/<选定版本>/；Tests/StatusTrioCoreTests/ 与 scripts/test-*.sh | 自动测试、实机记录、准确兼容声明 |

## Task 1 — 版本契约与 appcast 回归（预计 45–75 分钟）

**Files:** 修改上表“版本与更新约束”8 个文件；新增 `scripts/test-macos13-deployment-contract.sh` 与 `scripts/test-appcast-minimum-system-version.sh`。

**Interfaces:** 消费现有 release.json / plist / CLI 参数；产出一致的 13.0 目标与 exit 0/非零的契约测试，不增加 Swift 公共 API。

- [ ] 1. 先写版本契约测试：检查 `.macOS(.v13)`、plist `LSMinimumSystemVersion`、JSON `min_system_version` / `minimumMacOS` 和两个 Helper 常量均为 13.0；保留 SDK 26 门禁。使用 Python json、PlistBuddy、grep 精确匹配，不对任意 `15.0` 全局替换。

```bash
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Support/Info.plist
python3 -c 'import json; assert json.load(open("release.json"))["min_system_version"] == "13.0"; assert json.load(open("Support/mobile-battery-dependencies.json"))["minimumMacOS"] == "13.0"'
grep -F 'platforms: [.macOS(.v13)]' Package.swift
```

- [ ] 2. 在基线上运行新契约脚本，确认因 15.0 而失败，保存输出；此阶段失败是预期 red，不是基线失败。
- [ ] 3. 更新精确常量：Package `.v15 → .v13`；plist / JSON / Helper `15.0 → 13.0`；Ruby `options[:minimum] ||= "13.0"`；notes 脚本默认 `MINIMUM_SYSTEM_VERSION` 改 13.0。不改 CoreAudioOutputController 的 macOS 15 availability 分支。
- [ ] 4. 临时 feed 测试必须创建独立 fixtures：历史 build 1 / min 15.0 + 新 build 2 / min 13.0；准备 en / zh-Hans notes（标题含 `%VERSION%`、`%BUILD%`），用 `--appcast` 和 `--output` 指向 mktemp 目录。断言旧 item 不变、新 item 13.0、en 在前且 xml:lang 完整、签名保留；另测显式 minimum 参数覆盖默认值。不得读取线上 feed 后直接写回仓库。
- [ ] 5. 运行下列测试。此时 Swift 编译预期暴露新 API 错误，记录文件/行号交 Task 2，不能靠抬高 target 解围。

```bash
bash scripts/test-macos13-deployment-contract.sh
bash scripts/test-appcast-minimum-system-version.sh
swift build -c release
```

**Gate:** 配置和临时 appcast 测试通过；Swift availability 错误清单完整。此任务与 Task 2 共用一次 Swift 验证后的提交，避免提交不能编译的中间状态。

## Task 2 — SwiftUI 监听与局部键盘兼容（预计 90–150 分钟）

**Files:** 上表 6 个监听文件 + SettingsChrome.swift；测试扩展 `SettingsPictureRowTests.swift`、`AudioInputControlsViewTests.swift`、`BluetoothDeviceListPresentationTests.swift`、`ChargingEffectSettingsTests.swift`；新增 `MacOS13UICompatibilityTests.swift`。

**Interfaces:** 保留现有 `SettingsPictureRowSelection.wrapped(in:from:offset:)`、`selectRelative(offset:)`、`selectOption(_:)`。允许新增局部 View 修饰器，但不改变 Monitor / Store 的公开契约。

- [ ] 1. 先加行为断言：方向键首尾循环、LTR/RTL 方向、空选项不崩溃；输入设备变化时草稿同步、不可读 scalar 不变为可写；充电开启/停止与 Reduce Motion 仍触发现有状态路径。复用现有纯状态测试，不能只用字符串检索宣称交互通过。
- [ ] 2. 单独写兼容结构测试检查 6 个文件不再有两参数 onChange；运行失败测试后迁移 17 处。所有当前 oldValue 都未使用，保持调用体原样，例：

```swift
.onChange(of: draftVolume) { newValue in updateVolume(newValue) }
```

- [ ] 3. 现代系统优先保留现有 `.onKeyPress` 交互，将 macOS 14+ 链放进局部 availability 分支；Ventura 分支使用 `.onMoveCommand`，按已有 backwardStep/forwardStep 处理左右、-1/+1 处理上下。`.focusEffectDisabled()` 同样仅进入 macOS 14+ 分支；Ventura 保留系统焦点环。
- [ ] 4. Ventura 先保留原生 Button 的 Space / Return 激活，Task 5 用实际按键确认。若任一按键失败，使用局部 `NSViewRepresentable` 适配器仅处理当前 focus 的未修饰 Space/Return，其他事件交回 responder；不加 NSEvent 全局/常驻监听，不把 Return 绑定为整个窗口默认按钮。适配器需增加只触发一次、失焦不处理、TextField 输入不被吞的测试后再使用。
- [ ] 5. 以最低目标编译继续发现剩余 API 问题，逐个最小修复。测试 target 自身也需兼容；不因现代 SDK 提示弃用就重新引入 14+ API。运行：

```bash
swift test --filter SettingsPictureRowTests
swift test --filter AudioInputControlsViewTests
swift test --filter ChargingEffectSettingsTests
swift test --filter MacOS13UICompatibilityTests
swift test
swift build -c release
```

**Gate:** 13.0 部署目标下编译及全测试通过；监听无新轮询/双写。实际 Ventura 键盘仍为 NOT RUN，不能用新系统 NSHostingView 冒充。Task 1+2 可提交为 `feat: lower deployment target with Ventura UI compatibility`。

## Task 3 — Universal 主程序与原生 Helper（预计 60–180 分钟，取决于首次原生编译）

**Files:** Helper 构建 / 验证脚本；必要时 `Support/MobileBatteryHelper/` 中实际报错文件；新增 `scripts/test-macos13-bundle-contract.sh`。

**Interfaces:** 保留 `UNIVERSAL_BUILD=1 bash scripts/build-app.sh release no-open`；输出实际默认路径 `dist/Status Trio.app`（参考文档的 `dist/StatusTrio.app` 与当前默认不符）。

- [ ] 1. 先写 bundle 负例测试：一片为 minos 15.0、缺 x86_64、dylib 绝对 Homebrew 路径、缺合法 RPATH、错误签名分别必须拒绝。可用命令 shim 测试脚本判断，但真实验收必须读取真实 Mach-O。
- [ ] 2. 核实 Helper BUILD_KEY 含 MINIMUM_MACOS，更新至 13.0 后双架构原生依赖必须重建；只清理本 worktree 的对应 native cache，保留 pinned manifest、LICENSE/NOTICE。不能拿原 15.0 binary 用 vtool 降 minos。
- [ ] 3. 构建 App；主程序 SDK 修正机制保留，修改后二次签名与验证顺序不变。

```bash
UNIVERSAL_BUILD=1 bash scripts/build-app.sh release no-open
APP="$PWD/dist/Status Trio.app"
BIN="$APP/Contents/MacOS/StatusTrio"
lipo -archs "$BIN"
bash scripts/verify-platform-version.sh "$BIN" 13.0 26
UNIVERSAL_BUILD=1 bash scripts/verify-mobile-battery-bundle.sh "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
```

- [ ] 4. 记录主程序/Helper/每个动态库的 arm64、x86_64：架构、minos、sdk、LC_RPATH、otool -L、签名。source-built Helper 链按现有严格契约为 minos 13.0 / sdk >=26；Sparkle 的预构建文件可为 minos <=13 且旧 SDK，不强行改第三方 SDK metadata。
- [ ] 5. 运行原生单元与解析器测试：

```bash
bash scripts/test-mobile-battery-helper.sh
bash scripts/test-mobile-battery-rpaths.sh
bash scripts/test-otool-dependencies.sh
bash scripts/test-macos13-bundle-contract.sh
swift test --filter MobileBatteryHelperReaderTests
```

**Gate:** 双架构齐全，无本机绝对依赖；Helper 失败不会卡住主程序已有 reader 行为。提交 `build: verify Ventura universal helper dependency chain`；仍不宣称真机读取成功。

## Task 4 — 强链接 / 符号兜底与 CI 预检（预计 60–120 分钟 + CI 排队/构建时间）

**Files:** `Sources/DDCPrivateAPI/include/DDCPrivateAPI.h`、`Audio/DDCDisplayTransport.swift`、`Monitoring/BluetoothBatteryReader.swift`、`UI/BluetoothBatteryLevelText.swift`（后 3 个在 Sources/StatusTrioCore，下述只在发现缺陷时改）；`.github/workflows/release.yml`；相关 Dock 测试；`docs/swift-ci-compatibility.md`。

**Interfaces:** 保留 Intel DDC nil fallback；读取不可用返回原有不可用状态。CI 接入 Task 1/3 脚本，不改变 runner / Xcode / Swift。

- [ ] 1. 检查 `airpods.chargingcase` 不存在时的文字 fallback，加可注入“symbol absent”的测试，电量文字仍存在。任何影响图标的改动同时检查 StatusBarController / AppIconController / DockIconRenderKey / DockIconRenderer，补双方输出测试。
- [ ] 2. 逐架构检查 DDC IOAVService 强链接及新系统 framework/symbol：当前头文件是 extern，不应声称已有 dlopen 保护。静态扫描不能证明 Ventura 系统导出，Task 5 必须验证。若证据确认缺符号，限定原有符号做动态加载/能力探测，无符号返回不可调节；不得新增私有能力，不修改 Intel 行为。
- [ ] 3. 枚举 Sparkle framework 内 Mach-O、XPC 与 helper，每个要求 minos <=13；支持 LC_VERSION_MIN_MACOSX 的旧 load command，不误用主程序要求“精确 13.0 / SDK26”的验证器。包启动与 updater 启动留给 Task 5。
- [ ] 4. 在 CI 中运行新契约及 parser/native 测试，打包后检查真实双架构产物；保存 artifact。选定版本/build 前先读取已发布 Release、appcast、plist 与仓库 notes；把明确且递增的值写入验证报告，版本不在计划阶段猜定。预检前至少建立 en / zh-Hans notes 草案，防止 publish=false 缺目录静默跳过验证。
- [ ] 5. 全测试/release 通过后提交、推专用分支，再触发唯一非发布 workflow 并 watch。执行命令先从报告读出已选定值：

```bash
# 实施时写入 .build/macos13-preflight.env，内容仅为实际选定的 VERSION/BUILD。
source .build/macos13-preflight.env
test -n "$VERSION" && test -n "$BUILD"
VERSION="$VERSION" BUILD="$BUILD" PUBLISH=false bash scripts/validate-appcast-notes.sh
gh workflow run release.yml --repo lingyired/status-trio --ref codex/macos13-compatibility \
  -f version="$VERSION" -f build="$BUILD" -f publish=false
gh run list --repo lingyired/status-trio --workflow release.yml --branch codex/macos13-compatibility --limit 5
# 从列表核对 head SHA、触发时间及本次 run ID，再对该实际 ID 执行 gh run watch。
```

**Gate:** macos-26 / Xcode26.6 / Swift6.3.3 预检通过；确认 tests、Universal、DMG 和 artifact 成功，Release upload / appcast publication 被跳过。每个失败 run 记录原因/修复/重跑 ID，不当 flaky 忽略。不合并、不发布。

## Task 5 — Ventura 真机验收及准确文档（预计每种架构 45–90 分钟，设备准备另计）

**Files:** 新增 `docs/macos13-compatibility-verification.md`；README 各现有语言、AGENTS.md；选定版本对应 12 种语言 notes 草案。首次自动实现开始就建立报告，最后完善，不等到末尾丢失日志。

**Interfaces:** 消费同一 CI artifact / SHA；产出逐设备 PASS / FAIL / BLOCKED / NOT RUN 与人工复现步骤。不用 ARM Rosetta 代替 Intel Ventura 验收。

- [ ] 1. Intel macOS 13 和 Apple Silicon macOS 13 分别从 artifact 安装并启动。记录精确 OS / CPU / build / SHA / 权限状态；确认主程序、Helper、Sparkle 子程序正常。Ad-hoc 签名，不能称 Developer ID/notarized。
- [ ] 2. 在每台设备测试同一功能清单：Wi-Fi 名称/扫描/开关/有线/VPN；Bluetooth 重连/断开确认/电量；音量滚轮/静音/输出切换、麦克风输入；系统电池、充电/低电量。权限拒绝、无设备、睡眠唤醒各验证无崩溃/无无限重试。真实 iPhone/iPad 需已信任配对；空列表不是读取成功。AirPods/DDC 依硬件明确记录限制。
- [ ] 3. 设置卡片方向键、Tab、Space/Return、LTR/RTL、VoiceOver/Reduce Motion；菜单栏 / Dock / 两者模式，深浅色、全屏、多屏、首次引导与设置窗口；macOS26/27 对照外观和空闲 CPU/内存/唤醒频率，不能因兼容层增加定时器。
- [ ] 4. 实际验证 Wi-Fi / Network / Bluetooth / Battery / Sound / Location pane。Wi-Fi extension 永远优先，不依系统版本分流；打开 URL 后用 `pgrep -fl 'ExtensionKit/Extensions'` 记录实际 pane，保留 `StatusMenuBuilderTests.testSystemSettingsURLFallbackOrder`。Sparkle 使用隔离测试 feed 验证更新发现、下载/签名、子进程启动与安装，不改线上 feed 或签名公钥。
- [ ] 5. 完善系统矩阵及 README / notes：只有两种 Ventura 架构验收完成才声明“正式支持 13”；没有设备则写“部署目标降至13，运行验收未完成”，提供 checklist。14、15、26/27 未运行逐行 NOT RUN。12 语言 notes 标题含 `%VERSION%`/`%BUILD%`，en 第一、GitHub 英文后中文、首次启动命令仅 GitHub body；本任务只准备草案，不发布。

**Gate:** 真机证据齐备或明确标记未验证；同一 SHA 全自动验证通过。UI/API 未知问题修复后重跑 Task 2–4。正式支持被设备缺口阻塞时停止宣称，不虚构通过。

## 最终可执行验收命令

```bash
cd /Users/lingsmbp/.codex/worktrees/macos13-compatibility/status-trio
set -euo pipefail
swift test
swift build -c release
bash scripts/test-macos13-deployment-contract.sh
bash scripts/test-appcast-minimum-system-version.sh
bash scripts/test-mobile-battery-helper.sh
bash scripts/test-mobile-battery-rpaths.sh
bash scripts/test-otool-dependencies.sh
UNIVERSAL_BUILD=1 bash scripts/build-app.sh release no-open
APP="$PWD/dist/Status Trio.app"
bash scripts/verify-platform-version.sh "$APP/Contents/MacOS/StatusTrio" 13.0 26
UNIVERSAL_BUILD=1 bash scripts/verify-mobile-battery-bundle.sh "$APP"
bash scripts/test-macos13-bundle-contract.sh
codesign --verify --deep --strict --verbose=2 "$APP"
git diff --check
```

## 交付与执行边界

执行交付必须包含文件变更、测试数量/命令、二进制矩阵、CI run ID、逐 OS 实机矩阵、硬件限制、baseline/final SHA、Git 状态和未发布声明。本轮只新增参考副本与本计划；不修改 Swift、最低系统版本、依赖或产物，不运行 release workflow。

实施建议：Luna 按 Task 1→2→3→4→5 串行执行；Task 1/2 有编译依赖，Helper 与 CI 依赖最终最低目标，不提前并行开发。人工 Ventura 验收缺设备时可完成自动阶段并交付明确 checklist，但不能标为全面完成。

## 本轮基线验证结果

- `swift test`：exit 0；XCTest 执行 1382 项，7 skipped / 0 failures；Swift Testing 570 项 / 90 suites 通过。
- `swift build -c release`：exit 0，Build complete，32.72 秒；这是未降低 target 的基线，不是 macOS13 兼容编译证明。
- 日志保留于本 worktree 的 `.build/macos13-plan-baseline/baseline-test.log` 和 `baseline-release.log`（忽略的本地文件，不提交）。
- 本轮未打包 Universal，未检查产物 LC_BUILD_VERSION，未触发 CI，未执行任何实机验收。

| 运行系统 | 状态 | 说明 |
|---|---|---|
| macOS13 Intel | NOT RUN | 后续需要实际 Intel Ventura |
| macOS13 Apple Silicon | NOT RUN | 后续需要 ARM Ventura |
| macOS14 | NOT RUN | 未运行 App 功能验收 |
| macOS15 | NOT RUN | 未运行 App 功能验收 |
| macOS26 | NOT RUN | 未运行 App 功能验收 |
| macOS27 | NOT RUN | 仅本地编译/单元测试，未运行完整 App 验收 |
