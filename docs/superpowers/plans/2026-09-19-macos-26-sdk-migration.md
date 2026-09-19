# macOS 26 SDK 迁移（原生 Liquid Glass）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 macOS 26+ 上的菜单栏面板用上系统原生 Liquid Glass，并让这个回归不可能再静默发生。

**Architecture:** 仓库里已有 `vtool` 修补 `LC_BUILD_VERSION.sdk` 的代码（`scripts/build-app.sh` 第 152-162 行），但它从未生效过——CI 的构建 SDK 一直是 15.5，`if SDK >= 26` 不成立。本次把 CI 升到 `macos-26` / Xcode 26.6 来激活它，同时硬化这段代码（不再硬编码 `minos`、SDK 过旧直接失败）、新增产物断言脚本，并同步规则、文档与发布说明。

**Tech Stack:** SwiftPM（Swift 6.x）、GitHub Actions（`macos-26` runner）、`vtool` / `lipo` / `otool`、bash。

**Spec:** `docs/superpowers/specs/2026-09-19-macos-26-sdk-migration-design.md`

## Global Constraints

- 最低系统版本保持 **macOS 15**：`Package.swift` 的 `platforms: [.macOS(.v15)]` 不动，产物 `minos` 必须是 `15.0`。
- 构建必须使用 **macOS 26+ SDK**；SDK 过旧时 `scripts/build-app.sh` 必须**直接失败**，不允许静默跳过。
- CI 目标：runner `macos-26`，`DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer`；Xcode 版本显式钉死。
- 保留 **x86_64** 切片（`UNIVERSAL_BUILD=1` 时 `arm64` + `x86_64`）。
- **不使用**私有 API（`set_variant:` / `set_scrim:` / `set_subdued:`）。
- **不引入第二套机制**：继续用既有的 `vtool` 路线，不添加 `-Xlinker -platform_version`。
- 不使用已弃用的 `--build-system native`。
- 发布说明文件语言名与 `Sources/StatusTrioCore/Resources/*.lproj` **同名且大小写一致**，必须含首行 `# <title>` 与 `%VERSION%`、`%BUILD%` 占位符。

## Review Focus

| 可能出问题的输入 / 条件 | 合理预期 | 由哪个任务钉住 |
|---|---|---|
| fat binary 只有一个切片被改对 | 断言必须**逐架构**校验，不能只看第一个 | Task 1（构造混合 slice 的反向用例） |
| `vtool` 输出格式变化或不可用 | 断言必须**失败**，不能因为解析不到就静默通过 | Task 1（反向用例） |
| 贡献者本机 SDK 低于 26 | 构建**大声失败**并说明理由，不允许产出旧观感的 app | Task 2（SDK 覆盖用反向用例） |
| 少写一种语言的发布说明 | `PUBLISH=true` 时校验必须失败 | Task 3（反向用例） |
| 改名后残留旧路径引用 | 除历史存档外，全仓库不得再出现旧文件名 | Task 5（`grep` 断言） |

---

### Task 1: 产物元数据断言脚本

**Files:**
- Create: `scripts/verify-platform-version.sh`
- Test: 本任务的步骤 3–5（用真实产物 + 构造的产物）

**Interfaces:**
- Produces: `verify-platform-version.sh <binary> <expected-minos> [minimum-sdk-major]`
  - 退出码 `0` = 每个架构都满足；`1` = 至少一个不满足；`2` = 参数或文件不可用
  - 成功时每个架构打印一行 `<arch>: minos <x>, sdk <y>`
  - Task 2 会以 `bash "$ROOT/scripts/verify-platform-version.sh" "$BINARY" "$BUILT_MINOS"` 调用它

- [ ] **Step 1: 写脚本**

创建 `scripts/verify-platform-version.sh`：

```bash
#!/usr/bin/env bash
# Guards the LC_BUILD_VERSION metadata that macOS reads when deciding whether an
# app adopts the current design language.
#
# AppKit keys that decision off the `sdk` field, not `minos`. SwiftPM's build
# system can record the deployment target in that field instead of the real SDK
# version, which silently keeps the pre-Tahoe appearance for the menu bar
# popover. See docs/swift-ci-compatibility.md and issue #40.
#
# Usage: verify-platform-version.sh <binary> <expected-minos> [minimum-sdk-major]
# Exit codes: 0 = every architecture satisfies the expectations,
#             1 = at least one architecture does not,
#             2 = the arguments or the binary are unusable.

set -euo pipefail

BINARY="${1:-}"
EXPECTED_MINOS="${2:-}"
MINIMUM_SDK_MAJOR="${3:-26}"

if [[ -z "$BINARY" || -z "$EXPECTED_MINOS" ]]; then
    echo "Usage: $0 <binary> <expected-minos> [minimum-sdk-major]" >&2
    exit 2
fi

if [[ ! -f "$BINARY" ]]; then
    echo "Error: no such file: $BINARY" >&2
    exit 2
fi

ARCHS="$(lipo -archs "$BINARY" 2>/dev/null || true)"
if [[ -z "$ARCHS" ]]; then
    ARCHS="unknown"
fi

FAILED=0
for arch in $ARCHS; do
    if [[ "$arch" == "unknown" ]]; then
        BUILD_INFO="$(vtool -show-build "$BINARY" 2>/dev/null || true)"
    else
        BUILD_INFO="$(vtool -show-build -arch "$arch" "$BINARY" 2>/dev/null || true)"
    fi

    minos="$(awk '/^[[:space:]]*minos[[:space:]]/ {print $2; exit}' <<<"$BUILD_INFO")"
    sdk="$(awk '/^[[:space:]]*sdk[[:space:]]/ {print $2; exit}' <<<"$BUILD_INFO")"

    if [[ -z "$minos" || -z "$sdk" ]]; then
        echo "Error: ${arch}: unable to read LC_BUILD_VERSION from $BINARY." >&2
        FAILED=1
        continue
    fi

    sdk_major="${sdk%%.*}"
    if [[ "$minos" != "$EXPECTED_MINOS" ]]; then
        echo "Error: ${arch}: deployment target is ${minos}, expected ${EXPECTED_MINOS}." >&2
        FAILED=1
    fi
    if (( sdk_major < MINIMUM_SDK_MAJOR )); then
        echo "Error: ${arch}: built against SDK ${sdk}, but the current design language requires SDK ${MINIMUM_SDK_MAJOR} or newer." >&2
        FAILED=1
    fi

    printf '%s: minos %s, sdk %s\n' "$arch" "$minos" "$sdk"
done

if (( FAILED != 0 )); then
    echo "LC_BUILD_VERSION check failed for $BINARY" >&2
    exit 1
fi

echo "LC_BUILD_VERSION check passed for $BINARY"
```

- [ ] **Step 2: 给执行权限并准备真实产物**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio/.worktrees/build/macos-26-toolchain
chmod +x scripts/verify-platform-version.sh
swift build -c release
```

- [ ] **Step 3: 反向用例 A —— 部署目标不匹配必须失败**

```bash
bash scripts/verify-platform-version.sh .build/release/StatusTrio 99.0; echo "exit=$?"
```

预期：打印 `Error: <arch>: deployment target is 15.0, expected 99.0.`，
最后 `LC_BUILD_VERSION check failed ...`，`exit=1`。

- [ ] **Step 4: 反向用例 B —— SDK 过旧必须失败；正向用例必须通过**

```bash
cp .build/release/StatusTrio /tmp/vpv-old
xcrun vtool -set-build-version macos 15.0 15.5 -replace -output /tmp/vpv-old-tmp /tmp/vpv-old
mv /tmp/vpv-old-tmp /tmp/vpv-old
bash scripts/verify-platform-version.sh /tmp/vpv-old 15.0; echo "old_exit=$?"

cp .build/release/StatusTrio /tmp/vpv-new
xcrun vtool -set-build-version macos 15.0 26.0 -replace -output /tmp/vpv-new-tmp /tmp/vpv-new
mv /tmp/vpv-new-tmp /tmp/vpv-new
bash scripts/verify-platform-version.sh /tmp/vpv-new 15.0; echo "new_exit=$?"
```

预期：`old_exit=1`（提示 SDK 15.5 需要 ≥26）；`new_exit=0` 且打印 `arm64: minos 15.0, sdk 26.0`。

- [ ] **Step 5: 反向用例 C —— 读不出元数据时必须失败，不能静默通过**

```bash
printf 'not a mach-o binary\n' > /tmp/vpv-junk
bash scripts/verify-platform-version.sh /tmp/vpv-junk 15.0; echo "junk_exit=$?"
bash scripts/verify-platform-version.sh /tmp/definitely-missing 15.0; echo "missing_exit=$?"
```

预期：`junk_exit` 非 0（`unable to read LC_BUILD_VERSION` 或 `lipo`/`vtool` 失败），
`missing_exit=2`（`no such file`）。两者都**不能**是 0。

- [ ] **Step 6: 反向用例 D —— fat binary 只有一个切片达标必须失败**

这是最关键的一条：证明断言是逐架构校验的，而不是只看第一个切片。

```bash
cp .build/release/StatusTrio /tmp/vpv-fat
xcrun vtool -set-build-version macos 15.0 26.0 -replace -output /tmp/vpv-fat-tmp /tmp/vpv-fat
mv /tmp/vpv-fat-tmp /tmp/vpv-fat
lipo /tmp/vpv-fat -thin arm64 -output /tmp/vpv-a64
lipo /tmp/vpv-fat -thin x86_64 -output /tmp/vpv-x64
xcrun vtool -set-build-version macos 15.0 15.5 -replace -output /tmp/vpv-x64-old /tmp/vpv-x64
lipo -create /tmp/vpv-a64 /tmp/vpv-x64-old -output /tmp/vpv-mixed
lipo -archs /tmp/vpv-mixed
bash scripts/verify-platform-version.sh /tmp/vpv-mixed 15.0; echo "mixed_exit=$?"
```

预期：`lipo -archs` 输出 `arm64 x86_64`；断言打印 arm64 通过、x86_64 报 SDK 15.5，
`mixed_exit=1`。

> 注：本机 `.build/release/StatusTrio` 是 thin（默认单架构），所以步骤 6 先人为补上
> `sdk 26.0` 再拆 slice。若该产物本来就是 fat，步骤 6 的前两行可省略。

- [ ] **Step 7: 提交**

```bash
git add scripts/verify-platform-version.sh
git commit -m "build: assert the LC_BUILD_VERSION metadata of the app binary"
```

---

### Task 2: 硬化 `build-app.sh` 的既有修补

**Files:**
- Modify: `scripts/build-app.sh`（第 148-162 行区域）
- Test: 本任务步骤 3–5

**Interfaces:**
- Consumes: `scripts/verify-platform-version.sh`（Task 1）
- Produces: `build-app.sh` 在 SDK < 26 时以退出码 `2` 失败；成功后 `dist/StatusTrio.app/Contents/MacOS/StatusTrio` 的每个架构都是 `minos == 15.0` 且 `sdk >= 26`

- [ ] **Step 1: 替换既有的 vtool 代码块**

把 `scripts/build-app.sh` 中现有的这一段（`chmod +x "$CONTENTS/MacOS/StatusTrio"` 之后、
`SIGNING_IDENTITY=` 之前）：

```bash
# SwiftPM can record the deployment target as the SDK version in LC_BUILD_VERSION.
# macOS uses that field to decide whether an app adopts the current design system,
# so restore the real SDK version before signing.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "${SDK_VERSION%%.*}" -ge 26 ]]; then
    TOOLCHAIN_PLATFORM_VERSION="26.0"
    VTMP_BINARY="$(mktemp "${TMPDIR:-/tmp}/StatusTrio.vtool.XXXXXX")"
    xcrun vtool         -set-build-version macos 15.0 "$TOOLCHAIN_PLATFORM_VERSION"         -replace         -output "$VTMP_BINARY"         "$CONTENTS/MacOS/StatusTrio"
    mv "$VTMP_BINARY" "$CONTENTS/MacOS/StatusTrio"
    chmod +x "$CONTENTS/MacOS/StatusTrio"
fi
```

替换为：

```bash
# SwiftPM's build system can record the deployment target in LC_BUILD_VERSION's
# `sdk` field. macOS reads that field to decide whether an app adopts the current
# design language, so a wrong value silently keeps the pre-Tahoe popover
# appearance. Carry the deployment target through unchanged (instead of hardcoding
# it, which would silently reset it if Package.swift's platform ever changes) and
# declare the macOS 26 design language explicitly.
#
# STATUS_TRIO_SDK_VERSION_OVERRIDE exists only so the guard below can be tested.
SDK_VERSION="${STATUS_TRIO_SDK_VERSION_OVERRIDE:-$(xcrun --sdk macosx --show-sdk-version)}"
if [[ "${SDK_VERSION%%.*}" -lt 26 ]]; then
    echo "Error: Status Trio must be built with the macOS 26 SDK or newer; found ${SDK_VERSION}." >&2
    echo "       An older SDK silently ships the pre-Tahoe popover appearance." >&2
    exit 2
fi

BUILT_MINOS="$(vtool -show-build "$CONTENTS/MacOS/StatusTrio" | awk '/^[[:space:]]*minos[[:space:]]/ {print $2; exit}')"
if [[ -z "$BUILT_MINOS" ]]; then
    echo "Error: unable to read the deployment target from the built binary." >&2
    exit 1
fi

VTMP_BINARY="$(mktemp "${TMPDIR:-/tmp}/StatusTrio.vtool.XXXXXX")"
xcrun vtool -set-build-version macos "$BUILT_MINOS" 26.0 -replace -output "$VTMP_BINARY" "$CONTENTS/MacOS/StatusTrio"
mv "$VTMP_BINARY" "$CONTENTS/MacOS/StatusTrio"
chmod +x "$CONTENTS/MacOS/StatusTrio"

bash "$ROOT/scripts/verify-platform-version.sh" "$CONTENTS/MacOS/StatusTrio" "$BUILT_MINOS"
```

- [ ] **Step 2: 确认改动位置正确**

```bash
bash -n scripts/build-app.sh && echo "syntax ok"
grep -n "verify-platform-version\|STATUS_TRIO_SDK_VERSION_OVERRIDE\|BUILT_MINOS" scripts/build-app.sh
```

预期：`syntax ok`，并列出 3 处以上匹配行。

- [ ] **Step 3: 正向用例 —— 真实构建必须通过并写出正确元数据**

```bash
bash scripts/build-app.sh release no-open; echo "exit=$?"
vtool -show-build dist/StatusTrio.app/Contents/MacOS/StatusTrio | grep -E "architecture|minos|sdk"
```

预期：`exit=0`，出现 `LC_BUILD_VERSION check passed ...`，
且每个架构都是 `minos 15.0 / sdk 26.0`。

- [ ] **Step 4: 反向用例 —— SDK 过旧必须失败**

```bash
STATUS_TRIO_SDK_VERSION_OVERRIDE=15.5 bash scripts/build-app.sh release no-open; echo "exit=$?"
```

预期：打印两行 `Error: Status Trio must be built with the macOS 26 SDK or newer; found 15.5.`
与说明，`exit=2`，且**没有**产出 `dist/StatusTrio.app`（脚本在断言前退出）。

- [ ] **Step 5: universal 构建必须两个切片都正确**

```bash
UNIVERSAL_BUILD=1 bash scripts/build-app.sh release no-open; echo "exit=$?"
lipo -archs dist/StatusTrio.app/Contents/MacOS/StatusTrio
vtool -show-build dist/StatusTrio.app/Contents/MacOS/StatusTrio | grep -E "architecture|minos|sdk"
```

预期：`exit=0`；`arm64 x86_64`；两个架构均为 `minos 15.0 / sdk 26.0`。
x86_64 可能出现弃用告警，属于预期（见 Global Constraints）。

- [ ] **Step 6: 提交**

```bash
git add scripts/build-app.sh
git commit -m "build: require the macOS 26 SDK and preserve the deployment target"
```

---

### Task 3: 发布说明（12 种语言）

**Files:**
- Modify: `Support/Info.plist`（`CFBundleShortVersionString` → `1.3.0`，`CFBundleVersion` → `10`）
- Create: `release-notes/1.3.0/en.md`、`zh-Hans.md`，以及 `ar de es fr it ja ko pt-BR ru zh-Hant` 共 10 个文件
- Test: `bash scripts/validate-appcast-notes.sh`（正向 + 反向）

**Interfaces:**
- Produces: `release-notes/1.3.0/` 覆盖全部 12 种语言；Task 4 的预检以 `version=1.3.0 build=10` 触发

> 版本号说明：线上 appcast 最新为 `Version 1.2.0 (Build 9)`，`Support/Info.plist` 同为
> `1.2.0 / 9`。观感变化对用户可见，按 minor 递增取 **1.3.0**，构建号 **10**。

- [ ] **Step 1: 写英文说明**

创建 `release-notes/1.3.0/en.md`：

```markdown
# Version %VERSION% (Build %BUILD%)

## Native Liquid Glass on macOS 26 and later
- The popover now uses the system's own Liquid Glass material instead of the frosted
  look carried over from earlier macOS releases, so it matches the menus and panels
  around it.
- This is the system appearance, not an app-specific style: it follows your system
  settings, including Reduce Transparency and the system glass tint.
- macOS 15 and later are unaffected; the deployment target is unchanged, so no user
  has to update macOS to keep using Status Trio.
```

- [ ] **Step 2: 写简体中文说明**

创建 `release-notes/1.3.0/zh-Hans.md`：

```markdown
# 版本 %VERSION%（构建 %BUILD%）

## macOS 26 及以上的原生 Liquid Glass
- 弹出面板改用系统自带的 Liquid Glass 材质，不再沿用旧版 macOS 的磨砂观感，与周围的菜单和面板保持一致。
- 这是系统外观而非 app 自定义样式：它跟随系统设置，包括「降低透明度」与系统的玻璃色调。
- macOS 15 及以上不受影响；最低系统版本未变，用户无需升级 macOS 即可继续使用 Status Trio。
```

- [ ] **Step 3: 写其余 10 种语言**

按同一结构创建：`ar.md`、`de.md`、`es.md`、`fr.md`、`it.md`、`ja.md`、`ko.md`、
`pt-BR.md`、`ru.md`、`zh-Hant.md`。

规则：
- 第一行必须是 `# <该语言标题>`，且包含 `%VERSION%` 与 `%BUILD%`；
  可参照 `appcast.xml` 中同语言的 `<title xml:lang="…">` 写法（如 ja 用
  `バージョン %VERSION%（ビルド %BUILD%）`、ko 用 `버전 %VERSION%(%BUILD%)`、
  zh-Hant 用 `版本 %VERSION%（構建 %BUILD%）`）。
- 术语必须与该语言现有 `Sources/StatusTrioCore/Resources/<lang>.lproj/Localizable.strings`
  一致；找不到对应术语时保留英文专有名词（Liquid Glass、macOS）。
- 不新增功能承诺，不提「可切回旧观感」。

- [ ] **Step 4: 更新 `Support/Info.plist`**

```bash
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.3.0' Support/Info.plist
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 10' Support/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Support/Info.plist
```

预期：打印 `1.3.0` 与 `10`。

- [ ] **Step 5: 正向校验**

```bash
bash scripts/validate-appcast-notes.sh; echo "exit=$?"
```

预期：`exit=0`，覆盖 12 种语言。

- [ ] **Step 6: 反向校验 —— 缺语言必须被发现**

```bash
PUBLISH=true bash scripts/validate-appcast-notes.sh; echo "publish_true_exit=$?"
mv release-notes/1.3.0/ja.md /tmp/ja.md.bak
PUBLISH=true bash scripts/validate-appcast-notes.sh; echo "missing_exit=$?"
mv /tmp/ja.md.bak release-notes/1.3.0/ja.md
PUBLISH=true bash scripts/validate-appcast-notes.sh; echo "restored_exit=$?"
```

预期：`publish_true_exit=0`；`missing_exit` 非 0 并指出缺 `ja`；
`restored_exit=0`（确认文件已还原）。

- [ ] **Step 7: 提交**

```bash
git add release-notes/1.3.0 Support/Info.plist
git commit -m "docs: add the 1.3.0 release notes for the native glass change"
```

---

### Task 4: CI 工具链升级 + 非发布预检

**Files:**
- Modify: `.github/workflows/release.yml`（第 36 行 `runs-on`、第 39 行 `DEVELOPER_DIR`）
- Test: 本任务步骤 4 的预检

**Interfaces:**
- Consumes: Task 2 的构建断言、Task 3 的 `release-notes/1.3.0/`
- Produces: 一次成功的 `publish=false` 预检 run ID（Task 6 会把它写进兼容性文档）

- [ ] **Step 1: 改 runner 与 Xcode**

`.github/workflows/release.yml`：

```yaml
    runs-on: macos-26
...
      DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer
```

- [ ] **Step 2: 确认只改了这两处**

```bash
git diff .github/workflows/release.yml
grep -nE "runs-on|DEVELOPER_DIR" .github/workflows/release.yml
```

预期：diff 只有两行；`runs-on: macos-26`、`DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer`。

- [ ] **Step 3: 提交并推送分支**

```bash
git add .github/workflows/release.yml
git commit -m "ci: build releases with the macOS 26 toolchain"
git push -u origin build/macos-26-toolchain
```

- [ ] **Step 4: 触发非发布预检并等待**

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref build/macos-26-toolchain \
  -f version=1.3.0 \
  -f build=10 \
  -f publish=false

sleep 20
gh run list --repo lingyired/status-trio --workflow release.yml --limit 3
```

拿到 run ID 后：

```bash
gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

预期：成功。并在日志中确认：

```bash
gh run view <run-id> --repo lingyired/status-trio --log | grep -E "Swift version|Xcode [0-9]|LC_BUILD_VERSION check|minos [0-9]"
```

- 必须看到 Xcode 26.x 与它自带的 Swift 版本（把实际版本记下来，Task 5 要写进 `AGENTS.md`）。
- 必须看到 `LC_BUILD_VERSION check passed`。

- [ ] **Step 5: 失败时的处理（不可跳过）**

若预检失败：按 `AGENTS.md` 的要求把该 run 记进 `docs/swift-6.1-ci-compatibility.md`
（此时尚未改名，Task 5 会改名），字段为 run ID、失败阶段、根因、修复方式、验证结果；
修好后重新触发，直到预检通过。**预检没有通过之前不要进入 Task 6。**

---

### Task 5: 规则、文档改名与调研文档修正

**Files:**
- Rename: `docs/swift-6.1-ci-compatibility.md` → `docs/swift-ci-compatibility.md`
- Modify: `AGENTS.md`、`docs/github-actions-release.md:11`、
  `docs/popover-glass-investigation.md`（第 68、69、227、271 行及事实性修正）、
  `docs/wifi-status-responsiveness.md:35`
- Test: 本任务步骤 6 的 `grep` 断言

**Interfaces:**
- Consumes: Task 4 预检日志里的实际 Xcode / Swift 版本
- Produces: 全仓库（除历史存档）不再引用旧文件名；`AGENTS.md` 声明新工具链与 macOS 26 SDK 要求

- [ ] **Step 1: 改名**

```bash
git mv docs/swift-6.1-ci-compatibility.md docs/swift-ci-compatibility.md
```

- [ ] **Step 2: 更新改名的文档自身**

标题改为 `# Swift 工具链 CI 兼容性与失败记录`；「结论」段把工具链描述从
`Xcode 16.4 / Swift 6.1.2` 改为 Task 4 预检日志中的实际版本，并把「本机使用较新的
Xcode 27 / Swift 6.4……」这句更新为与新工具链一致的表述。
文档末尾新增一节 `## 工具链迁移记录`，写入本次预检的 run ID、日期、结论
（旧修补因 CI SDK 15.5 休眠、升级后生效、断言已加）。

- [ ] **Step 3: 更新 `AGENTS.md`**

- 「Highest Priority: Match the CI Toolchain」的 runner / Xcode / Swift 三项改为
  `macos-26` / `26.6` / Task 4 日志中的实际 Swift 版本。
- 新增一条硬性要求：

```markdown
- The app must be built with the macOS 26 SDK or newer. macOS reads the
  `LC_BUILD_VERSION` `sdk` field to decide whether an app adopts the current design
  language, so building with an older SDK silently ships the pre-Tahoe popover
  appearance. `scripts/build-app.sh` fails when the SDK is older than 26, and
  `scripts/verify-platform-version.sh` asserts the result; do not remove either.
```

- 「Swift 6.1 Compatibility Rules」标题去掉版本号（改为 `## Swift Toolchain Compatibility Rules`），
  **删除**「Do not add syntax or language features that require Swift 6.2 or newer」这一条，
  其余各条保留。
- 两处链接（「Every failed GitHub Actions run…」段与文末「See …」）的路径与文字改为
  `docs/swift-ci-compatibility.md` / `Swift toolchain CI compatibility`。

- [ ] **Step 4: 更新其余引用点**

| 文件 | 改动 |
|---|---|
| `docs/github-actions-release.md:11` | 链接文字与路径改为新文件名；工具链版本改为 `macos-26` / Xcode 26.6 |
| `docs/popover-glass-investigation.md` | 第 68、69、227、271 行的路径与版本引用 |
| `docs/wifi-status-responsiveness.md:35` | `Xcode 16.4 / Swift 6.1.2` 改为新工具链 |
| `docs/superpowers/plans/2026-09-17-natural-volume-scrolling.md:21` | **不改**（历史存档） |

- [ ] **Step 5: 修正调研文档中被推翻的结论**

`docs/popover-glass-investigation.md` 必须补上并改正：

1. 新增一条关键事实：`scripts/build-app.sh` **已有** `vtool` 修补（由 `b728e6c` 于 2026-09-13 引入），
   但因 CI 的构建 SDK 一直是 15.5（`macos-15` + Xcode 16.4），`if SDK >= 26` 从未成立，
   **该修补从未在任何发布中生效**；线上 app 的 `sdk 15.5` 就是证据。
2. 修正「方案 0：不换组件，只把构建 SDK 升到 macOS 26+」段落里
   「代码里一行玻璃相关的东西都不用写」的说法——实际需要激活并硬化既有修补。
3. 修正「若走方案 0 需要改动的面」里「产品代码理论上零改动」的说法。

- [ ] **Step 6: 验证没有残留引用**

```bash
grep -rn "swift-6.1-ci-compatibility" --include="*.md" --include="*.yml" --include="*.sh" . \
  | grep -v "^./backups/" | grep -v "^./.worktrees/"
```

预期：只出现 `docs/superpowers/plans/2026-09-17-natural-volume-scrolling.md`（历史存档，
且其中只是文字、没有链接）。任何其它文件出现旧文件名都是漏改。

```bash
ls docs/swift-ci-compatibility.md && ls docs/swift-6.1-ci-compatibility.md 2>&1 | tail -1
```

预期：第一个存在，第二个报 `No such file`。

- [ ] **Step 7: 提交**

```bash
git add -A AGENTS.md docs/
git commit -m "docs: move CI rules and docs to the macOS 26 toolchain"
```

---

### Task 6: 记录预检结果、端到端验收与合并

**Files:**
- Modify: `docs/swift-ci-compatibility.md`（若 Task 4 步骤 5 已写入则核对补齐）
- Test: 本任务步骤 1–4

- [ ] **Step 1: 本地全量验证**

```bash
swift test --disable-sandbox
swift build -c release --disable-sandbox
bash scripts/build-app.sh release no-open
vtool -show-build dist/StatusTrio.app/Contents/MacOS/StatusTrio | grep -E "architecture|minos|sdk"
```

预期：测试全绿（589 XCTest + 146 Swift Testing；本机沙箱会挡住钥匙串与 `cfprefsd`，
若出现 `testKeychainPasswordStoreAddsReadsUpdatesAndCleansItsOwnItem` 或
`removingATestSuiteDeletesItsPreferenceFile` 失败，那是沙箱限制而非代码问题）；
构建通过；每个架构 `minos 15.0 / sdk 26.0`。

- [ ] **Step 2: 复核 macOS 15 兼容性**

```bash
lipo -archs dist/StatusTrio.app/Contents/MacOS/StatusTrio
bash scripts/verify-platform-version.sh dist/StatusTrio.app/Contents/MacOS/StatusTrio 15.0
```

预期：`minos 15.0`（可加载 macOS 15）；断言通过。另外确认没有任何未加
`#available` 守卫的 macOS 26+ API——新 SDK 会把这类调用变成编译错误，所以构建通过本身就是证据。

- [ ] **Step 3: 真机观感确认（需要维护者执行）**

在 macOS 26+ 上打开 Status Trio 面板，确认是原生 Liquid Glass 而不是旧磨砂。
**这一条只有人能判定，不得由代码或截图代替。** 若观感不对，回到 Task 2 检查
`vtool` 是否真的改写了产物。

- [ ] **Step 4: 合并**

本次改动横跨 CI、构建脚本、文档与发布说明，按 `AGENTS.md` 建议走 PR 保留评审记录：

```bash
gh pr create --repo lingyired/status-trio \
  --base main --head build/macos-26-toolchain \
  --title "build: adopt the macOS 26 SDK for native Liquid Glass (#40)" \
  --body "Closes #40. Activates the dormant vtool LC_BUILD_VERSION fix by moving CI to
macos-26 / Xcode 26.6, hardens it, adds a binary metadata assertion, and syncs the rules,
docs and release notes. Deployment target stays macOS 15."
```

合并后删除 worktree：

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
git worktree remove .worktrees/build/macos-26-toolchain
git branch -d build/macos-26-toolchain
```

- [ ] **Step 5: 关闭 issue #40**

合并并发布后，在 #40 上说明：根因是 CI 构建 SDK 过旧导致既有修补休眠，
已在 macOS 26+ 上确认使用系统原生 Liquid Glass。
