# macOS 26 SDK 迁移（原生 Liquid Glass）设计

状态：**待评审**。评审通过后再写实施计划（`docs/superpowers/plans/`），然后才动代码。

关联 issue：[#40 菜单栏展开玻璃透明度与原生透明度不一致](https://github.com/lingyired/status-trio/issues/40)
调查记录：[菜单栏面板玻璃通透度调研](../../popover-glass-investigation.md)

## 目标

1. 让 macOS 26+ 上的菜单栏面板使用**系统原生 Liquid Glass**，而不是 Tahoe 之前的磨砂材质。
2. 保持 macOS 15 最低支持不变（`platforms: [.macOS(.v15)]` 不动，产物 `minos` 仍是 15.0）。
3. 让这种回归**不可能再静默发生**：构建脚本必须自己校验产物，而不是依赖人工核对。

## 非目标（YAGNI）

- **不换掉 `NSPopover`**：原生 chrome 就能满足诉求；自绘 `NSPanel` 只在「无法升级构建 SDK」时才需要。
- **不在 app 内新增通透度选项**：系统已有「液体玻璃：透明 / 色调」（`NSGlassTintAmount`）总开关，
  再叠一层 app 级选项会与系统设计语言打架。
- **不使用私有 API**（`set_variant:` / `set_scrim:` 等）。
- **不引入第二套机制**：仓库已经有 `vtool` 修补（见下），不再叠加链接参数方案。
- 不重构 `SettingsChrome.SidebarMaterial` 等既有 `NSVisualEffectView` 用法。

## 关键背景：机制早已存在，只是从未生效

`scripts/build-app.sh` 第 152-162 行**已经有**这段修补（由 `b728e6c`「feat: redesign settings window」
于 2026-09-13 引入，在 `main` 上）：

```bash
# SwiftPM can record the deployment target as the SDK version in LC_BUILD_VERSION.
# macOS uses that field to decide whether an app adopts the current design system,
# so restore the real SDK version before signing.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "${SDK_VERSION%%.*}" -ge 26 ]]; then
    TOOLCHAIN_PLATFORM_VERSION="26.0"
    ... vtool -set-build-version macos 15.0 "$TOOLCHAIN_PLATFORM_VERSION" -replace ...
fi
```

它**从未在任何一次发布中生效过**：

- `.github/workflows/release.yml` 固定 `runs-on: macos-15` + `Xcode_16.4`（SDK 15.5），
  `if` 条件不成立，修补被跳过；
- `git log -S 'macos-26'` / `-S 'Xcode_26'` 对 workflow 均无结果——CI 从未用过 26 工具链；
- 直接证据：已安装的 `/Applications/Status Trio.app` 是 `minos 15.0 / **sdk 15.5**`，
  而 `vtool` 修补会写成 `sdk 26.0`。

所以 #40 的根因不是「缺了什么代码」，而是**已有的修复因为 CI 工具链太旧而一直休眠**。
本设计的主体因此是：激活它、给它加护栏、把规则与文档同步过去。

## 已验证的事实

在 macOS 27.0（26A428）+ 本地 Swift 6.4 上实测。

| # | 事实 | 证据 |
|---|---|---|
| 1 | AppKit 是否采纳新设计语言，取决于 `LC_BUILD_VERSION` 的 **`sdk` 字段** | `sdk 27.0` → `NSPopoverFrame` 子树含私有 `NSGlassView`；`sdk 15.5` → `material=6`（`.popover`） |
| 2 | **`minos` 不参与**该判定 | `minos 15.0 + sdk 27.0` 仍是原生 Liquid Glass |
| 3 | 新版 Swift Build 后端（新工具链默认）把 `sdk` 写成部署目标 | `swift build` → `minos 15.0 / sdk 15.0` |
| 4 | 经典后端写真实 SDK 版本，但**已弃用** | `--build-system native` → `sdk 27.0` + 弃用警告 |
| 5 | `vtool -set-build-version` 对 **fat binary 两个切片都改写**且保留架构 | universal 产物：`x86_64` 与 `arm64` 均为 `minos 15.0 / sdk 26.0` |
| 6 | 链接参数 `-Xlinker -platform_version …` 也能写对 | 实测有效；但见「非目标」——不引入第二套机制 |
| 7 | x86_64 在新 SDK 下有弃用告警但仍可构建 | "The x86_64 architecture is deprecated for your deployment target" |
| 8 | 新工具链下基线干净 | `swift build` 通过；589 XCTest（3 skipped，0 失败）+ 146 Swift Testing 全绿 |
| 9 | CI runner 可用 | `macos-26` 镜像预装 Xcode 26.0.1–26.6（默认 26.6）；另有 `xcode-27-arm64` 预览 |

第 1、2 条的复现见调查记录；第 3–6 条的复现见本文末。

## 设计

### 变更 1：CI 工具链升级（激活既有修补）

`.github/workflows/release.yml`：

| 项 | 现在 | 改为 |
|---|---|---|
| `runs-on` | `macos-15` | `macos-26` |
| `DEVELOPER_DIR` | `/Applications/Xcode_16.4.app/Contents/Developer` | `/Applications/Xcode_26.6.app/Contents/Developer` |

Xcode 版本显式钉死（沿用现有做法），不依赖镜像默认值。`Show toolchain` 步骤保持不变。

### 变更 2：硬化既有的 `vtool` 步骤

现有实现有两个问题：

1. **`minos` 被硬编码成 `15.0`**。若 `Package.swift` 的 `platforms` 将来抬高（例如 `.v16`），
   这一行会把产物静默改回 15.0——app 会声称支持一个它并非为此构建的系统版本。
2. **SDK < 26 时静默跳过**。这正是本次故障模式：构建成功、发布成功、观感悄悄退回旧版。

改为：

```bash
# SwiftPM's build system can record the deployment target in LC_BUILD_VERSION's
# sdk field. macOS reads that field to decide whether an app adopts the current
# design system, so a wrong value silently keeps the pre-Tahoe appearance.
# Carry the deployment target through unchanged and declare the macOS 26 design
# language explicitly. Requires the macOS 26 SDK; see AGENTS.md.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "${SDK_VERSION%%.*}" -lt 26 ]]; then
    echo "Error: Status Trio must be built with the macOS 26 SDK or newer; found ${SDK_VERSION}." >&2
    echo "       Building with an older SDK silently ships the pre-Tahoe popover appearance." >&2
    exit 2
fi

BINARY="$CONTENTS/MacOS/StatusTrio"
BUILT_MINOS="$(vtool -show-build "$BINARY" | awk '/minos/ {print $2; exit}')"
if [[ -z "$BUILT_MINOS" ]]; then
    echo "Error: unable to read the deployment target from $BINARY." >&2
    exit 1
fi

VTMP_BINARY="$(mktemp "${TMPDIR:-/tmp}/StatusTrio.vtool.XXXXXX")"
xcrun vtool -set-build-version macos "$BUILT_MINOS" 26.0 -replace -output "$VTMP_BINARY" "$BINARY"
mv "$VTMP_BINARY" "$BINARY"
chmod +x "$BINARY"

bash "$ROOT/scripts/verify-platform-version.sh" "$BINARY" "$BUILT_MINOS"
```

为什么 `BUILT_MINOS` 从产物读、而不是从 `Package.swift` 解析：产物才是事实来源，
而 SwiftPM 已经按 `platforms` 写好了 `minos`（实测 15.0）。读回来再原样写回去，
两边不可能漂移，也不需要脆弱的 manifest 解析。

### 变更 3：新增产物断言脚本

新建 `scripts/verify-platform-version.sh <binary> <expected-minos>`：

- 用 `vtool -show-build` 取每个架构的 `minos` 与 `sdk`；
- 断言 **每个架构** 的 `minos` 等于 `expected-minos`，且 `sdk` 主版本 **≥ 26**；
- 任一不满足 → 打印实测值并 `exit 1`；全部满足 → 打印一行摘要并 `exit 0`。

独立成脚本而不是内联，是为了让**反向用例可复现**（见验证第 4 条）：正向证明它通过，
反向证明它不是形同虚设。它同时被 `build-app.sh` 调用，因此本地构建与 CI 预检都会执行。

### 变更 4：规则与文档

- `AGENTS.md`
  - 「Highest Priority: Match the CI Toolchain」：runner `macos-15` → `macos-26`，
    Xcode `16.4` → `26.6`，Swift `6.1.2` → 以 Xcode 26.6 自带版本为准（实施时从预检日志确认后填入）。
  - 新增一条硬性要求：**构建必须使用 macOS 26+ SDK**，理由写清（第 1、3 条事实 + 休眠历史），
    并指明 `scripts/build-app.sh` 会在 SDK 过旧时直接失败。
  - 「Swift 6.1 Compatibility Rules」去掉版本号，改为与版本无关的表述：保留 `isolated deinit`、
    `weak let`、`Bundle.module`、IRGen 崩溃处理等经验条款；**删除「不得使用 Swift 6.2+ 语法」**——
    该条随旧 CI 编译器一起失效。
  - 两处链接指向新文件名。
- **重命名** `docs/swift-6.1-ci-compatibility.md` → `docs/swift-ci-compatibility.md`
  （去掉版本号：覆盖范围已从 Swift 6.1.2 扩展到 Xcode 26.x）。用 `git mv` 保留历史，
  标题改为「Swift 工具链 CI 兼容性与失败记录」，「结论」段更新工具链描述。

  已全量排查引用点（workflow 与 `scripts/` 均未引用该文件）：

  | 文件 | 位置 | 要改什么 |
  |---|---|---|
  | `AGENTS.md` | 「Every failed GitHub Actions run…」段 | 链接文字与路径 |
  | `AGENTS.md` | 文末「See …」 | 链接文字与路径 |
  | `docs/github-actions-release.md` | 第 11 行 | 链接文字、路径、工具链版本 |
  | `docs/popover-glass-investigation.md` | 第 68、69、227、271 行 | 路径与工具链版本 |
  | `docs/wifi-status-responsiveness.md` | 第 35 行 | 「Xcode 16.4 / Swift 6.1.2」 |
  | `docs/superpowers/plans/2026-09-17-natural-volume-scrolling.md` | 第 21 行 | **不改**：历史计划属存档 |

### 变更 5：修正调研文档

`docs/popover-glass-investigation.md`（本次调查的记录）需要按新事实修正，否则会误导后续会话：

- 补上「`build-app.sh` 已有 `vtool` 修补、因 CI SDK 15.5 而休眠」这一关键事实与其出处（`b728e6c`）；
- 修正「方案 0：代码里一行玻璃相关的东西都不用写」的表述——实际需要激活并硬化既有修补；
- 修正「若走方案 0 需要改动的面」中「产品代码理论上零改动」的说法。

### 变更 6：发布说明（本次一并完成）

macOS 26+ 用户升级后会**一次性看到新观感**，且 app 内无法回退到旧磨砂；macOS 15–25 观感不变。
写进下一个版本的 `release-notes/<version>/`：

- 必写 `en.md` 与 `zh-Hans.md`（同时构成 GitHub Release 正文）；`publish=true` 还需要全部 12 种语言，
  语言名与 `Sources/StatusTrioCore/Resources/*.lproj` 同名且大小写一致。
- 每个文件首行 `# <title>`，含 `%VERSION%` 与 `%BUILD%` 占位符；术语与对应语言现有 `.lproj` 一致。
- 措辞要点：本次是采用系统原生 Liquid Glass 的结果——macOS 26 及以上外观更通透、与系统一致；
  macOS 15–25 不受影响。不承诺可在 app 内切回旧观感。
- 校验：`bash scripts/validate-appcast-notes.sh`。
- 版本号与构建号显式给出，且构建号必须大于线上 appcast 当前值。

## 验证

1. `swift test`（新工具链；全绿基线已确认）。
2. `swift build -c release`。
3. `bash scripts/build-app.sh release no-open` → 断言脚本通过；再确认产物：
   `vtool -show-build dist/StatusTrio.app/Contents/MacOS/StatusTrio` 显示 `minos 15.0 / sdk 26.0`。
4. **反向用例**（证明断言不是形同虚设）：
   `bash scripts/verify-platform-version.sh <binary> 26.0` 必须失败（minos 不匹配）；
   另用 `sed` 临时把脚本里的 26 改成 27 制造不可能满足的条件，确认会失败——或直接对
   一个 `sdk` 为 15.5 的旧产物运行断言。同时确认 SDK 守卫：把 `xcrun --show-sdk-version`
   的取值临时替换为 `15.5`（用一个仅测试用的环境变量覆盖）时 `build-app.sh` 以退出码 2 失败。
5. `UNIVERSAL_BUILD=1 bash scripts/build-app.sh release no-open` → **两个切片**都是 `sdk 26.0`（事实 5）。
6. `publish=false` 的 release workflow 预检（`macos-26` / Xcode 26.6）：日志中确认实际
   Xcode/Swift 版本，确认测试、通用构建、断言、DMG 全部通过；把 run ID 与结果记进
   `docs/swift-ci-compatibility.md`。
7. **真机观感确认**：在 macOS 26+ 上打开 Status Trio 面板，确认是原生 Liquid Glass。
   只有人能判定，需要维护者执行。
8. macOS 15 兼容性复核：断言中的 `minos == 15.0` 即证明可加载；另确认没有未加
   `#available` 守卫的 macOS 26+ API（新 SDK 会把这类调用变成编译错误，天然兜底）。

## 风险与回滚

| 风险 | 处理 |
|---|---|
| Xcode 26.x 的构建后端行为与本地 Swift 6.4 不同 | 预检是唯一权威；断言会在 CI 上直接暴露 |
| 新 SDK 让现有代码报错（弃用升级为错误等） | 基线证明当前只产生弃用**告警**；若预检报错就按错误修，不用 `-warnings-as-errors` 之类绕过 |
| `vtool` 在未来工具链里行为变化 | 断言会失败（这正是它存在的意义），而不是静默通过 |
| x86_64 在未来 SDK 中不可用 | 本次保留；若变成错误，另开 issue 讨论是否放弃 Intel |
| 迁移整体失败 | 回滚 = 还原 workflow 两处值 + `build-app.sh` 的硬化；分支独立，`main` 不受影响 |

## 已定决策（2026-09-19 维护者确认）

1. **发布说明本次一并写**（变更 6 属于本次范围）。
2. **保留 x86_64 切片**：macOS 15 用户里仍有 Intel 机器；新 SDK 的弃用告警可接受。
3. **重命名** `docs/swift-6.1-ci-compatibility.md` → `docs/swift-ci-compatibility.md`，
   并同步全部引用点（见变更 4）。

至此本文没有未决问题。下一步是实施计划。

## 附：事实 3–6 的复现

最小 SwiftPM 包（`platforms: [.macOS(.v15)]`，与本仓库同条件）：

```bash
swift build -c release                                  # -> minos 15.0 / sdk 15.0
swift build -c release --build-system native            # -> sdk 27.0（后端已弃用）
swift build -c release \
  -Xlinker -platform_version -Xlinker macos -Xlinker 15.0 -Xlinker 26.0   # -> sdk 26.0

# fat binary 的 vtool 改写（事实 5）
swift build -c release --arch arm64 --arch x86_64
vtool -show-build .build/release/<product> | grep -E "architecture|minos|sdk"
xcrun vtool -set-build-version macos 15.0 26.0 -replace -output /tmp/out .build/release/<product>
vtool -show-build /tmp/out | grep -E "architecture|minos|sdk"
```
