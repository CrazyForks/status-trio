# 多语言更新日志设计

## 目标

让用户通过 Sparkle 收到的**更新日志**与界面一样支持全部 12 种语言，而不是只有英文和简体中文。同时消除发布流程里两个结构性缺陷：`workflow_dispatch` 的 10 输入上限，以及更新日志路径在 CI 中零覆盖。

## 背景

当前 appcast 的每个条目只发射 `en` 与 `zh-Hans` 两个语言变体，而应用界面（`Sources/StatusTrioCore/Resources/*.lproj`）有 12 种语言，其中包含 `zh-Hant`。结果是繁体中文用户的界面是中文、更新日志却是英文；日、韩、德、法、西、意、葡、俄、阿同理。

现状证据：

- 已发布的 1.2.0 条目只有 `title` / `description` 各 2 个变体，整个 appcast 只出现过 `en` 与 `zh-Hans`。
- `scripts/update-appcast.rb` 把 `zh-Hans` 写死在代码里。
- `.github/workflows/release.yml` 只有 `release_notes`（英）与 `release_notes_zh`（简）两个文案输入。

两个必须绕开的约束：

1. **输入上限**：GitHub `workflow_dispatch` 最多 10 个输入，当前已有 6 个（`version`、`build`、`tag`、`publish`、`release_notes`、`release_notes_zh`）。为 12 种语言各加一个输入在物理上不可行。
2. **零覆盖**：`scripts/release.sh` 在 `PUBLISH=false` 时于 appcast 生成之前 `exit 0`，且 workflow 的 `Prepare release notes` 步骤带 `if: PUBLISH == 'true'`。因此 `publish=false` 的预检完全跑不到更新日志这条路径，它目前没有任何 CI 覆盖。

## 语言集合与标签

12 种语言，`xml:lang` 标签与 `.lproj` 目录名逐字一致（大小写敏感）：

```
ar  de  en  es  fr  it  ja  ko  pt-BR  ru  zh-Hans  zh-Hant
```

## Sparkle 的语言匹配（设计依据）

`Sparkle/SUAppcast.m` 的 `bestNodeInNodes:name:` 使用 `[NSBundle preferredLocalizationsFromArray:]` 挑选变体，而不是自研匹配逻辑。由此推出三条硬性设计约束：

- `preferredLocalizationsFromArray:` 在**无任何匹配**时返回原数组，而该方法随后取 `objectAtIndex:0`。因此兜底是**文档顺序里的第一个节点**，而不是硬编码的英文值。`en` 必须永远排第一——这是行为约束，不是排版偏好。
- Foundation 的匹配会处理子标签：`zh-Hant-TW` 用户能命中 `zh-Hant` 节点，`pt-BR` 用户命中 `pt-BR` 节点。我们只发射 `pt-BR`，因此 `pt-PT` 用户回退英文，符合预期。
- 每个变体都必须显式带 `xml:lang`。当同一元素存在多个节点而某个节点缺该属性时，Sparkle 会记错误日志并把它当作 `en` 处理。

## 目录约定

新增 `release-notes/<version>/`，每个支持语言一份文件：

```
release-notes/
  1.2.0/
    en.md  zh-Hans.md  zh-Hant.md  ja.md   ko.md
    de.md  fr.md       es.md       it.md   pt-BR.md  ru.md  ar.md
```

`en.md` 与 `zh-Hans.md` **一份两用**：既进 appcast，也拼成 GitHub Release 正文的英文段与中文段。

## 文件格式

每份文件沿用现有 `notes_to_html` 的转换规则：

- 第一行为标题 `# <标题>`，必须同时包含 `%VERSION%` 与 `%BUILD%` 两个占位符，由脚本注入实际数字。这样标题里的版本号与构建号不可能手写错。
- 其余行为 `- 条目` 或 `## 小节`；空行忽略；顶层 `# ` 开头的行不输出为正文内容。
- 转换：`## x` → `<h2>x</h2>`，`- x` → `<li>x</li>`，其余非空行也转成 `<li>`（因此文件里不能出现裸段落），顶层 `# ` 行被跳过。
- XML 转义沿用现有实现，所以文件内不要写 `**加粗**` 之类的 Markdown 内联语法——它们会被原样转义。

## 数据流

```
release-notes/<version>/*.md
  ├─ workflow「Prepare release notes」(publish=true)
  │    → GitHub Release 正文：英文段 + 中文段 + 首次启动命令
  └─ release.sh → update-appcast.rb --notes-dir <dir>
       → appcast.xml：12 个 xml:lang 变体，en 排第一
```

GitHub Release 正文的格式**保持不变**：`# Version X.Y.Z （English + 中文， 中文在下方）`、英文在上中文在下、末尾追加首次启动的 `xattr` / `open` 命令。

## 接口契约

### `scripts/update-appcast.rb`

从位置参数改为命名参数，以支持任意语言数并让预检可跑：

```
--version <v> --build <n> --minimum-system-version <v>
--dmg-url <url> --ed-signature <sig> --length <bytes>
--notes-dir <dir> --appcast <path>
[--output <path>]        # 写出位置；默认为 --appcast，给出时仓库内文件不被修改
[--replace-existing]     # 就地替换同一 build 的已有条目
```

行为：

- `--appcast` 是**读取**的基准文档（新条目插入其 `<channel>`，或在 `--replace-existing` 时在其中定位条目）；`--output` 是**写出**位置。缺省写回 `--appcast`，因此干跑必须显式给出 `--output` 指向临时文件。
- 按固定顺序发射变体：`en` 第一，其余按规范顺序（`ar de es fr it ja ko pt-BR ru zh-Hans zh-Hant`）。
- `--replace-existing` 按 `<sparkle:version>` 定位已有条目并**只重写 `title` 与 `description` 节点**，保留原 `pubDate`、`sparkle:version`、`sparkle:shortVersionString`、`sparkle:minimumSystemVersion` 与 `enclosure`。定位不到对应 build 时报错退出。
- `ar` 的 `description` 外层包 `<div dir="rtl">`；其余语言不加包装。

### `scripts/release.sh`

- 移除 `APPCAST_RELEASE_NOTES_EN_FILE` 与 `APPCAST_RELEASE_NOTES_ZH_FILE` 两个变量。
- 改为 `RELEASE_NOTES_DIR="${RELEASE_NOTES_DIR:-$ROOT/release-notes/$VERSION}"`，校验后传给 `update-appcast.rb`。
- 所有校验都在 appcast 生成之前完成，且在 `PUBLISH=false` 时不因文案缺失而失败（见下）。

### `.github/workflows/release.yml`

- 移除 `release_notes` 与 `release_notes_zh` 两个输入（输入数 6 → 4）。
- `Prepare release notes` 改为从 `release-notes/<version>/en.md` 与 `zh-Hans.md` 读取并拼装正文，仍只在 `publish=true` 时执行。原先「`release_notes` 留空时用 `git log` 自动生成英文日志」的兜底**取消**：正文一律来自文案文件。
- 新增**始终运行**的 `Validate appcast notes` 步骤（位于 `Resolve release version` 之后、`Run tests` 之前），以 `--output` 干跑到临时文件，然后断言：
  - `xmllint --noout` 通过；
  - **变体数 = `2 × 已发射语言数`**（每语言一个 `title` 与一个 `description`），且发射顺序以 `en` 开头；
  - `publish=true` 时额外断言已发射语言数 = 12；
  - 不含未替换的 `%VERSION%` / `%BUILD%` 占位符；
  - 不含空的 `<description>`；
  - 打印覆盖表（哪些语言存在、哪些缺失）。

这是本次改动最关键的部分：更新日志这条路径第一次获得真实的 CI 覆盖，并会随每次预检运行。

## 校验规则与边界

| 情形 | `publish=true` | `publish=false`（预检） |
| --- | --- | --- |
| 缺 `en.md` 或 `zh-Hans.md` | 失败（正文需要它们） | 警告 |
| 缺其余 10 种中任一 | 失败，并列出缺失清单 | 警告 + 覆盖表 |
| `release-notes/<version>/` 不存在 | 失败 | 跳过并提示 |

正式发布要求 12 种齐全，而不是「有就发、缺就回退英文」——静默回退正是要消灭的缺口。预检只警告不阻断，使文案未写完时仍能照常预检，缺口在发布前暴露而非卡在发版当下。

其他规则：

- 目录名必须等于解析出的 `VERSION`，否则失败（防止把 1.2.0 的文案挂到 1.3.0）。
- 忽略点文件（`.DS_Store` 等）与非 `.md` 文件；出现未识别的 `*.md` 语言名（如 `zh-hant.md`）时失败，防止拼写错误静默降级。
- 标题必须同时含 `%VERSION%` 与 `%BUILD%`，缺失即失败。
- 变体数量与语言集合的一致性由校验步骤断言。

## 翻译策略与术语

以 `en.md` 为唯一基准产出其余 11 种。**术语权威是各语言已有的界面翻译** `Sources/StatusTrioCore/Resources/<lang>.lproj/Localizable.strings`，而不是字面转换。高风险术语对照（均取自仓库现有字符串）：

| 术语 | en | zh-Hant | zh-Hans | ja | ko | de |
| --- | --- | --- | --- | --- | --- | --- |
| 状态图标 | Status Icon | 狀態**圖示** | 状态图标 | ステータスアイコン | 상태 아이콘 | Status-Symbol |
| 蓝牙音频 | Bluetooth Audio | 藍牙**音訊** | 蓝牙音频 | Bluetooth オーディオ | Bluetooth 오디오 | Bluetooth-Audio |
| 电池详情 | Battery Details | 電池**詳細資訊** | 电池详情 | バッテリーの詳細 | 배터리 세부 정보 | Batteriedetails |
| 自然滚动 | Natural Scrolling | 自然**捲動** | 自然滚动 | ナチュラルスクロール | 자연스러운 스크롤 | Natürliches Scrollen |
| 检查更新 | Check for Updates… | **檢查**更新… | 检查更新… | アップデートを確認… | 업데이트 확인… | Nach Updates suchen… |

| 术语 | fr | es | it | pt-BR | ru | ar |
| --- | --- | --- | --- | --- | --- | --- |
| 状态图标 | Icône d’état | Icono de estado | Icona di stato | Ícone de status | Значок состояния | أيقونة الحالة |
| 蓝牙音频 | Audio Bluetooth | Audio por Bluetooth | Audio Bluetooth | Áudio Bluetooth | **Звук** Bluetooth | صوت Bluetooth |
| 电池详情 | Détails de la batterie | Detalles de la batería | Dettagli batteria | Detalhes da bateria | Сведения об аккумуляторе | تفاصيل البطارية |
| 自然滚动 | Défilement naturel | Desplazamiento natural | Scorrimento naturale | Rolagem natural | Естественная прокрутка | التمرير الطبيعي |
| 检查更新 | Rechercher les mises à jour… | Buscar actualizaciones… | Controlla aggiornamenti… | Verificar atualizações… | Проверить обновления… | التحقق من وجود تحديثات… |

lproj 中没有对应词的表述（适配器额定功率、净功率估算、循环次数、采样时间等）采用该语言 macOS 自身的系统用词。繁体中文不得使用字符转换结果，必须使用上表这类台湾/香港用词。

## 1.2.0 回填

- 新建 `release-notes/1.2.0/`：已确认的英文与简体内容，加上新产出的 10 种（含 `zh-Hant`），共 12 份。
- 用 `--replace-existing --build 9` 重新生成 appcast 的 1.2.0 条目。
- 断言：变体数 24（12 `title` + 12 `description`），`xmllint` 通过，`pubDate` 与 enclosure 未变。
- 1.1.0 及更早的历史条目**不回填**：Sparkle 只向用户展示最新可更新版本的日志，历史条目不再有用户看到。

## 规则与文档更新

- `AGENTS.md` 第 64 条从「发射 en + zh-Hans」改为「为 `release-notes/<version>/` 中每种语言发射带显式 `xml:lang` 的变体，`en` 必须第一（Sparkle 无匹配时按文档顺序兜底），绝不把两种语言堆进同一个 `<description>`」。
- `AGENTS.md` Release Rules 增加文案目录约定，以及「正式发布要求 12 种齐全，预检只警告」。
- `AGENTS.md` 第 65 条（正文双语格式 + 首次启动命令只进 Release 不进 appcast）**不变**。
- `docs/github-actions-release.md` 同步：移除两个已删除输入的说明，补上文案目录约定与 `Validate appcast notes` 步骤。

## 测试与验证

- 不引入 Ruby 单测框架：仓库没有该基础设施，且属于过度设计。CI 的 `Validate appcast notes` 干跑步骤就是这条路径的测试。
- 本地用与 CI 相同的断言先验一遍（`--output` 到临时文件 + `xmllint` + 变体计数 + 占位符检查）。
- 改动不涉及 Swift 源码，`swift test` 行为不受影响。
- 完成后运行一次 `publish=false` 的 release workflow 预检，让新的校验步骤真实执行一次。

## 不在本次范围内

- 不回填 1.1.0 及更早的 appcast 条目。
- 不把 GitHub Release 正文改成多语言，正文维持英文 + 简体双语。
- 不引入 Ruby 测试框架或新的 CI job。
- 不改动应用内 12 种语言的界面文案。
- 不改动 appcast 的 EdDSA 签名机制与 DMG 签名流程。

## 风险

- **翻译质量无人工复核**（用户明确表示不 review）：以 lproj 术语表为权威、并在本文档留下可审计的术语对照表来缓解。
- **12 种强制校验可能挡住紧急发版**：预检只警告，缺口会提前暴露；紧急情况下可先补齐文案文件再发布。
- **`--replace-existing` 会改写已发布条目**：限定为只重写 `title` / `description` 且保留 `pubDate`，版本号、签名与 enclosure 均不动。
