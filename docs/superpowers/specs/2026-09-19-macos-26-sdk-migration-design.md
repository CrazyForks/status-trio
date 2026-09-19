# macOS 26 SDK 迁移（原生 Liquid Glass）设计

状态：**待评审**。评审通过后再写实施计划（`docs/superpowers/plans/`），然后才动代码。

关联 issue：[#40 菜单栏展开玻璃透明度与原生透明度不一致](https://github.com/lingyired/status-trio/issues/40)
调查记录：[菜单栏面板玻璃通透度调研](../../popover-glass-investigation.md)

## 目标

1. 让 macOS 26+ 上的菜单栏面板使用**系统原生 Liquid Glass**，而不是 Tahoe 之前的磨砂材质。
2. 保持 macOS 15 最低支持不变（`platforms: [.macOS(.v15)]` 不动，产物 `minos` 仍是 15.0）。
3. 让 CI 与本地构建都能稳定复现第 1 条——即不能出现「升了工具链但仍悄悄是旧观感」。

## 非目标（YAGNI）

- **不换掉 `NSPopover`**：调查已证明原生 chrome 就能满足诉求，自绘 `NSPanel`（原方案 A）
  只在「无法升级构建 SDK」时才需要，本次不做。
- **不在 app 内新增通透度选项**：系统已有「液体玻璃：透明 / 色调」（`NSGlassTintAmount`）总开关，
  再叠一层 app 级选项会与系统设计语言打架。若日后确有需求，另开 spec。
- **不使用私有 API**（`set_variant:` / `set_scrim:` 等）。
- 不重构 `SettingsChrome.SidebarMaterial` 等既有 `NSVisualEffectView` 用法；只在视觉回归中
  发现明确问题时单独立项。

## 已验证的事实（设计前提）

全部在 macOS 27.0（26A428）+ 本地 Swift 6.4 上实测，命令见调查记录。

| # | 事实 | 证据 |
|---|---|---|
| 1 | AppKit 是否采纳新设计语言，取决于 `LC_BUILD_VERSION` 的 **`sdk` 字段** | `sdk 27.0` → `NSPopoverFrame` 子树含私有 `NSGlassView`；`sdk 15.5` → `material=6`（`.popover`） |
| 2 | **`minos` 不影响**该判定 | `minos 15.0 + sdk 27.0` 仍是原生 Liquid Glass |
| 3 | **新的 Swift Build 后端（新版工具链默认）把 `sdk` 写成部署目标** | `swift build` → `minos 15.0 / sdk 15.0` |
| 4 | 经典后端写真实 SDK 版本，但**已弃用** | `--build-system native` → `sdk 27.0`，同时打印弃用警告 |
| 5 | 显式链接参数可强制写对，且默认后端下有效 | `-Xlinker -platform_version -Xlinker macos -Xlinker 15.0 -Xlinker 26.0` → `minos 15.0 / sdk 26.0` |
| 6 | `--sdk <path>` **不能**修好第 3 条 | 仍是 `sdk 15.0` |
| 7 | universal 构建下两个架构都会写对 | `lipo -info` 两条 `LC_BUILD_VERSION` 均为 `minos 15.0 / sdk 26.0` |
| 8 | x86_64 在新 SDK 下有弃用告警但仍能构建 | "The x86_64 architecture is deprecated for your deployment target" |
| 9 | 新工具链下基线干净 | `swift build` 通过；589 XCTest（3 skipped，0 失败）+ 146 Swift Testing 全绿 |
| 10 | CI runner 可用 | `actions/runner-images` 的 `macos-26` 镜像预装 Xcode 26.0.1–26.6（默认 26.6） |

**第 3 条是本次迁移的核心陷阱**：只把 CI 升到 Xcode 26.x 是不够的。若新工具链默认启用
Swift Build 后端，`sdk` 会被写成 15.0，AppKit 继续给旧观感，#40 一行都不会变。

### 复现第 3–8 条

最小 SwiftPM 包（`platforms: [.macOS(.v15)]`，与本仓库同条件），逐个组合量 `sdk` 字段：

```bash
# 默认后端
swift build -c release                       # -> minos 15.0 / sdk 15.0
# 经典后端（已弃用）
swift build -c release --build-system native # -> minos 15.0 / sdk 27.0
# 显式 --sdk：无效
swift build -c release --sdk "$(xcrun --show-sdk-path)"   # -> 仍是 sdk 15.0
# 强制平台版本：有效
swift build -c release \
  -Xlinker -platform_version -Xlinker macos -Xlinker 15.0 -Xlinker 26.0
# -> minos 15.0 / sdk 26.0（universal 下两个架构都对）

vtool -show-build .build/release/<product> | grep -E "minos|sdk"
```

第 1、2 条（观感是否切换成 `NSGlassView`）的复现方式见调查记录。

## 设计

### 变更 1：构建脚本强制写入正确的平台版本（核心）

`scripts/build-app.sh` 在现有 `SWIFT_BUILD_ARGS` 上追加链接参数：

```bash
MACOS_DEPLOYMENT_TARGET=15.0        # 必须与 Package.swift 的 platforms 一致

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SDK_MAJOR="${SDK_VERSION%%.*}"
if (( SDK_MAJOR < 26 )); then
    echo "Error: build with the macOS 26 SDK or newer; found ${SDK_VERSION}." >&2
    exit 2
fi

SWIFT_BUILD_ARGS+=(
    -Xlinker -platform_version -Xlinker macos
    -Xlinker "$MACOS_DEPLOYMENT_TARGET" -Xlinker "$SDK_VERSION"
)
```

要点：

- **用真实 SDK 版本而不是硬编码 26.0**：这个字段的语义是「链接时使用的 SDK 版本」，
  写真实值才诚实；下限由 `SDK_MAJOR < 26` 的硬失败保证。
- **SDK < 26 时硬失败**而不是告警后继续——继续就会静默退回旧观感，正是本设计要消灭的失败模式。
  代价是贡献者本地也需要 Xcode 26+，与 AGENTS.md「以 CI 工具链为准」的既有原则一致。
- `MACOS_DEPLOYMENT_TARGET` 与 `Package.swift` 的 `platforms` 是同一事实的两处表达，
  因此由变更 2 的产物断言兜底，防止漂移。

### 变更 2：产物元数据断言（新增验收项）

`build-app.sh` 在构建后、打包签名前，对产物断言：

- 每个架构的 `minos` **等于** `MACOS_DEPLOYMENT_TARGET`；
- 每个架构的 `sdk` **不小于** 26。

实现用 `vtool -show-build "$BIN" | awk '/minos|sdk/{print $1, $2}' | sort -u` 取去重后的
事实集合，与期望值比较；不匹配则 `exit 2`。

这是本仓库第一次对**二进制元数据**做断言，也是这次迁移唯一能防止「看似升级、实际没生效」的
自动检查。它同时覆盖本地构建与 CI 预检，因为两者都走 `build-app.sh`。

### 变更 3：CI 工具链

`.github/workflows/release.yml`：

| 项 | 现在 | 改为 |
|---|---|---|
| `runs-on` | `macos-15` | `macos-26` |
| `DEVELOPER_DIR` | `/Applications/Xcode_16.4.app/Contents/Developer` | `/Applications/Xcode_26.6.app/Contents/Developer` |

Xcode 版本显式钉死（沿用现有做法），不依赖镜像默认值。

第 52-54 行的 `Show toolchain` 步骤保持不变，它会在日志里留下实际版本，便于事后核对。

### 变更 4：规则与文档

- `AGENTS.md`
  - 「Highest Priority: Match the CI Toolchain」：runner `macos-15` → `macos-26`，
    Xcode `16.4` → `26.6`，Swift `6.1.2` → 以 Xcode 26.6 自带版本为准（实施时在预检日志中确认后填入）。
  - 「Swift 6.1 Compatibility Rules」标题与条款按新编译器重新表述：保留 `isolated deinit`、
    `weak let`、`Bundle.module` 等与版本无关的经验条款，删掉只对 6.1 成立的表述。
- `docs/swift-6.1-ci-compatibility.md`：追加本次工具链迁移的记录（含预检 run ID 与结果）。
  文件名保持不动以维持既有链接，文档内说明其覆盖范围已扩展到 Xcode 26.x。
- 新增/更新说明：`scripts/build-app.sh` 中「为什么需要 `-platform_version`」的注释必须写清楚
  （第 3 条事实），否则未来有人会当作多余参数删掉。

### 变更 5：发布说明

macOS 26+ 用户在升级后会**一次性看到新观感**，且 app 内无法回退到旧磨砂。
这属于用户可见变化，需要写进下一个版本的 `release-notes/<version>/{en,zh-Hans}.md`
（以及 `publish=true` 所需的全部 12 种语言）。macOS 15–25 用户观感不变。

## 验证

按 AGENTS.md 的顺序：

1. `swift test`（本地新工具链，全绿基线已确认）。
2. `swift build -c release`。
3. `bash scripts/build-app.sh release no-open`：确认**新的产物断言**通过，即
   `minos 15.0` 且 `sdk ≥ 26`；同时确认 universal（`UNIVERSAL_BUILD=1`）下两个架构都对。
4. `publish=false` 的 release workflow 预检（`macos-26` / Xcode 26.6），
   在日志中确认实际 Xcode/Swift 版本，并确认步骤 3 的断言在 CI 上同样通过。
5. **真机观感确认**：在 macOS 26+ 上打开 Status Trio 面板，确认是原生 Liquid Glass。
   这一条只有人能判定，需要维护者执行。
6. macOS 15 兼容性复核：`minos 15.0` 断言通过即可证明可加载；另外确认代码中没有任何
   未加 `#available` 守卫的 macOS 26+ API（新 SDK 会把这类调用变成编译错误，天然兜底）。

## 风险与回滚

| 风险 | 处理 |
|---|---|
| Xcode 26.x 的 SwiftPM 后端行为与本地 Swift 6.4 不同 | 预检是唯一权威；产物断言会在 CI 上直接暴露 |
| 新 SDK 让某处现有代码报错（弃用升级为错误等） | 基线已证明当前代码只产生弃用**告警**；若预检报错，按错误修，不引入 `-warnings-as-errors` 之类的绕过 |
| 版本号漂移（`platforms` 与脚本常量不一致） | 变更 2 的断言 |
| x86_64 在未来 SDK 中不可用 | 本次保留；若某天变成错误，另开 issue 讨论是否放弃 Intel |
| 迁移整体失败 | 回滚 = 还原 workflow 的两处值 + `build-app.sh` 的参数与断言；分支独立，`main` 不受影响 |

## 未决问题

1. 变更 5 的发布说明由本次一并写好，还是等发布时再写？（影响本次改动范围）
2. 是否保留 x86_64 切片？（当前结论：保留，因为 macOS 15 用户里有 Intel 机器）
3. `docs/swift-6.1-ci-compatibility.md` 是否改名（例如去掉 `6.1`）？
   倾向不改名以免破坏 AGENTS.md 与历史的链接，只在文档内扩展说明。
