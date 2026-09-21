# 蓝牙电量默认开启：剩余文档任务 Implementation Plan

> **For agentic workers:** 本文件是原始计划的**剩余部分**。原始计划 `2026-09-20-bluetooth-battery-level-default.md` 的 Task 1-3 已由 PR #60 合并进 `main`（`a42ae93`），其文件在本仓库一次未跟踪文件清理中被删除。本计划只覆盖尚未落地的文档与验证工作，逐任务用 `- [ ]` 跟踪。

**Goal:** 把已经合并进 `main` 的「显示蓝牙设备电量默认开启 + 详情页只在有电量时显示 + 读取失败列表级提示」补进用户可见文档：3 个 README 与 12 语言的 1.3.0 发布说明。

**Architecture:** 纯文档改动，不碰 Swift 源码。README 只在已有该句的三个语言里补默认值；发布说明按 `release-notes/1.3.0/` 既有的 12 个文件各追加一个小节，术语取自各自 `.lproj` 与同文件既有小节。

**Tech Stack:** Markdown、`scripts/validate-appcast-notes.sh`、git。

**Spec:** `docs/superpowers/specs/2026-09-20-bluetooth-battery-level-default-design.md`

## 前置状态（已核实）

- `origin/main` = `a42ae93`（Merge PR #60 `lingyired/fix/bluetooth-battery-level-default`），已快进本地 `main`。
- 已落地：`SettingsStore` 默认 `?? true`（`:559`）、`BluetoothBatteryReading` 回调可空、`BluetoothDeviceController.batteryLevelsReadFailed`、`BluetoothDevicePresentation.batteryLevelText(for:batteryLevels:)`、详情页列表级失败提示、`Tests/StatusTrioCoreTests/BluetoothDeviceRowBatteryTextTests.swift`、`docs/bluetooth-status.md` 写明默认值。
- 与原计划的偏差（由 PR #60 决定，本计划不再改动）：概要行改为给**每个已连接设备**显示电量并让 AirPods 排在前面（`46d3144`、`20e4e38`），原 `hasConnectedAirPods` 门控已移除；读数合并为单次 `system_profiler`。
- 1.3.0 **尚未发布**（`appcast.xml` 最高条目仍是 1.2.0 / build 9），因此说明写进 `release-notes/1.3.0/` 是正确的目标。
- 缺口：3 个 README 未说明该开关的默认值；12 个 1.3.0 说明都没有这次默认值翻转的小节。

## Global Constraints

- 不新增、不修改任何本地化键与 `.lproj` 文案；发布说明术语必须与对应语言 `.lproj` 一致。
- 发布说明 12 种语言齐全，每语言一个小节、标题用 `##`、文件首行 `%VERSION%` / `%BUILD%` 占位标题保持不变。
- 不新增 release-notes 版本目录，不发布、不打 tag、不推送。
- 不改动任何 Swift 源码；因此本次不需要 `swift test` / release 预检作为门槛（已合并的 Swift 改动已由其自身 CI 覆盖，见 `docs/swift-ci-compatibility.md` 的 build 23 记录），但仍运行一次测试与 release 构建作为本地健康检查。
- `bash scripts/validate-appcast-notes.sh` 必须通过。

## Review Focus

1. 10 种非中英语言的翻译是否与各自 `.lproj` 术语一致（尤其 `settings.bluetooth.batteryLevels` 的开关名）。
2. 每个文件只追加一个 `##` 小节，不得把两种语言写进同一文件，首行占位标题不得被改动。
3. README 三种语言只改「是否读取电量」那一句，不改动同段其它说明（蓝牙面板仍默认关闭）。
4. 已有小节「Bluetooth no longer polls in the background」仍写着概要与设备页「未改变」，与本次默认值/行规则改动存在措辞张力——本计划不改它，作为 deferred minor 记录。
5. `publish=false` 校验脚本不得因新增小节而报 appcast 覆盖或语言数量错误。

---

### Task 1: README 说明默认值

**Files:**
- Modify: `README.md:78`
- Modify: `README.zh-Hans.md:78`
- Modify: `README.de.md:78`

**Interfaces:**
- Consumes: 已合并的行为（默认开启）。
- Produces: 三个 README 中该开关的默认值说明。

- [ ] **Step 1: 改三处末句**

`README.md:78` 末句：

```
**Settings › Bluetooth** also controls whether the battery levels are read — on by default — and scales the Bluetooth icon from 100% to 180%.
```

`README.zh-Hans.md:78` 末句：

```
**设置 › 蓝牙**还可以控制是否读取电量（默认开启），并把蓝牙图标在 100%–180% 之间缩放。
```

`README.de.md:78` 末句：

```
**Einstellungen › Bluetooth** steuert außerdem, ob die Batteriestände gelesen werden – standardmäßig an –, und skaliert das Bluetooth-Symbol von 100 % bis 180 %.
```

其余 9 个 README 没有这句话，保持不动。

- [ ] **Step 2: 复核**

Run: `grep -n "on by default\|默认开启\|standardmäßig an" README.md README.zh-Hans.md README.de.md`
Expected: 三个文件各自命中一行；`README.de.md` 的命中来自本次改动（该文件原句无「standardmäßig」）。

Run: `git diff --stat -- README.md README.zh-Hans.md README.de.md`
Expected: 3 个文件、各 1 行改动。

---

### Task 2: 12 语言 1.3.0 发布说明

**Files:**
- Modify: `release-notes/1.3.0/en.md`、`zh-Hans.md`、`zh-Hant.md`、`ar.md`、`de.md`、`es.md`、`fr.md`、`it.md`、`ja.md`、`ko.md`、`pt-BR.md`、`ru.md`

**Interfaces:**
- Consumes: Task 1 的措辞与各语言 `.lproj` 术语。
- Produces: 12 份说明各一个新增 `##` 小节，供 `scripts/validate-appcast-notes.sh` 与 release workflow 生成 appcast。

- [ ] **Step 1: 英文与简体中文（其余语言的翻译源）**

`release-notes/1.3.0/en.md` 末尾追加：

```markdown
## Bluetooth battery levels are on by default
- "Show Bluetooth battery levels" under Settings › Bluetooth now starts enabled, so a connected device reports its battery without a trip into Settings. Turning it off still stops the read.
- The Bluetooth device page no longer prints "Unavailable" on every row: a device that reports no battery shows its name alone, and a report that cannot be read is reported once under the list.
```

`release-notes/1.3.0/zh-Hans.md` 末尾追加：

```markdown
## 蓝牙电量默认显示
- 「设置 › 蓝牙」中的「显示蓝牙设备电量」现在默认开启，已连接的设备会直接显示电量，无需先进设置。关闭它仍会停止读取。
- 蓝牙设备页不再在每一行打印「暂不可用」：没有电量字段的设备只显示名称；整份报告读不出来时，在列表下方提示一次。
```

- [ ] **Step 2: 其余 10 种语言**

按 Step 1 的英文段落翻译，标题与开关名取各自 `.lproj` 的既有术语（`settings.bluetooth.batteryLevels`）：

| 文件 | 小节标题用词 | 开关名（必须原样引用） |
| --- | --- | --- |
| `zh-Hant.md` | 藍牙電量預設顯示 | 顯示藍牙裝置電量 |
| `ar.md` | مستويات بطارية Bluetooth مفعّلة افتراضيًا | عرض مستويات بطارية Bluetooth |
| `de.md` | Bluetooth-Batteriestände sind standardmäßig an | Bluetooth-Batteriestände anzeigen |
| `es.md` | Los niveles de batería Bluetooth vienen activados | Mostrar niveles de batería Bluetooth |
| `fr.md` | Les niveaux de batterie Bluetooth sont activés par défaut | Afficher les niveaux de batterie Bluetooth |
| `it.md` | I livelli batteria Bluetooth sono attivi per impostazione predefinita | Mostra i livelli batteria Bluetooth |
| `ja.md` | Bluetooth のバッテリー残量はデフォルトで表示 | Bluetooth のバッテリー残量を表示 |
| `ko.md` | Bluetooth 배터리 잔량은 기본으로 표시 | Bluetooth 배터리 잔량 표시 |
| `pt-BR.md` | Níveis de bateria Bluetooth vêm ativados por padrão | Mostrar níveis de bateria Bluetooth |
| `ru.md` | Уровни заряда Bluetooth включены по умолчанию | Показывать заряд устройств Bluetooth |

第二条行为每个语言都用该语言的「不可用」串（`bluetooth.battery.unavailable`）：`Nicht verfügbar` / `No disponible` / `Indisponible` / `Non disponibile` / `取得できません` / `사용할 수 없음` / `Indisponível` / `Недоступно` / `غير متاح` / `暫不可用`。措辞风格对齐各文件既有的「Bluetooth no longer polls in the background」小节。

- [ ] **Step 3: 逐个复核结构**

Run: `for f in release-notes/1.3.0/*.md; do printf '%s: ' "$f"; head -1 "$f"; done`
Expected: 12 行，每行都是该语言的 `%VERSION%` / `%BUILD%` 占位标题，未被改动。

Run: `grep -c '^## ' release-notes/1.3.0/*.md`
Expected: 每个文件比改动前多 1 个小节（1.3.0 原有 en/zh-Hans 6 个、其余语言同结构）。

- [ ] **Step 4: 校验说明与 appcast**

Run: `bash scripts/validate-appcast-notes.sh`
Expected: PASS。

---

### Task 3: 提交与本地健康检查

**Files:**
- 无源码改动。

**Interfaces:**
- Consumes: Task 1-2 的文档改动。
- Produces: 一个文档提交 + 本地测试/构建证据。

- [ ] **Step 1: 本地测试与 release 构建（健康检查）**

Run: `swift test`
Expected: PASS，0 failures。

Run: `swift build -c release`
Expected: 构建成功，0 errors。

- [ ] **Step 2: 提交**

```bash
git add README.md README.zh-Hans.md README.de.md release-notes/1.3.0
git commit -m "docs: note the Bluetooth battery level default in the 1.3.0 notes"
```

不推送、不发版；由人类伙伴决定发布流程。
