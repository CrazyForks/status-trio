# 多语言更新日志实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Sparkle 更新日志发射 12 种语言变体，消除 `workflow_dispatch` 10 输入上限的结构性约束，并让这条路径第一次获得 CI 覆盖。

**Architecture:** 文案改为仓库内的单一真源 `release-notes/<version>/<lang>.md`，由 `update-appcast.rb`（改为命名参数）为每个语言发射带 `xml:lang` 的 `title`/`description`；`compile-time` 校验由新的 `scripts/validate-appcast-notes.sh` 承担，它在每次 dispatch（含 `publish=false` 预检）都以 `--output` 干跑到临时文件并断言，从而覆盖此前零 CI 覆盖的路径。

**Tech Stack:** Ruby（`optparse`、字符串模板，沿用现有零依赖风格）、Bash、GitHub Actions YAML、Sparkle 2 appcast。

**Spec:** `docs/superpowers/specs/2026-09-19-multilingual-appcast-notes-design.md`

## Global Constraints

- 语言标签必须与 `Sources/StatusTrioCore/Resources/*.lproj` 目录名逐字一致且大小写敏感：`en ar de es fr it ja ko pt-BR ru zh-Hans zh-Hant`。
- `en` 必须永远是 appcast 里第一个语言变体：Sparkle 的 `-bestNodeInNodes:name:` 在无匹配时取文档顺序第一个节点。
- 每个变体必须显式带 `xml:lang`；绝不把两种语言堆进同一个 `<description>`。
- `en.md` 与 `zh-Hans.md` 是必需语言文件；`publish=true` 时 12 种全部必需，`publish=false` 时只警告。
- GitHub Release 正文格式不变：`# Version X.Y.Z （English + 中文， 中文在下方）`，英文在上中文在下，末尾追加首次启动 `xattr` / `open` 命令；正文不含 `# ` 单层标题行。
- `release-notes/<version>/` 目录名必须等于解析出的 `VERSION`。
- 文案文件第一行必须同时含 `%VERSION%` 与 `%BUILD%` 占位符。
- 只有 `zh-Hans` 包含「更新下载 / mirror fallback」小节；其余 11 种语言（含 `zh-Hant`）一律不含该小节。
- 不改动 `appcast.xml` 的 EdDSA 签名机制、DMG 签名流程或 GitHub Release 正文结构。

---

## File Structure

**新建：**

| 路径 | 职责 |
| --- | --- |
| `release-notes/1.2.0/en.md` | 英文文案（appcast 英文变体 + Release 正文英文段） |
| `release-notes/1.2.0/zh-Hans.md` | 简体文案（appcast 简体变体 + 正文中文段） |
| `release-notes/1.2.0/{zh-Hant,ja,ko,de,fr,es,it,pt-BR,ru,ar}.md` | appcast 其余 10 个语言变体 |
| `scripts/validate-appcast-notes.sh` | 覆盖表 + 干跑断言；预检与正式发布共用 |

**修改：**

| 路径 | 改动 |
| --- | --- |
| `scripts/update-appcast.rb` | 位置参数 → 命名参数；多语言发射；`--output` 干跑；`--replace-existing` |
| `scripts/release.sh` | 删除 `APPCAST_RELEASE_NOTES_*`；改为 `RELEASE_NOTES_DIR` 并传 `--notes-dir` |
| `.github/workflows/release.yml` | 删除 2 个文案输入；`Prepare release notes` 改读文件；新增 `Validate appcast notes` 步骤 |
| `appcast.xml` | 回填 1.2.0 条目的 12 个语言变体 |
| `AGENTS.md` | 第 64 条改写；Release Rules 增加文案目录约定 |
| `docs/github-actions-release.md` | 输入说明、文案目录、校验步骤同步 |

---

### Task 1: 落库英文与简体文案

**Files:**
- Create: `release-notes/1.2.0/en.md`
- Create: `release-notes/1.2.0/zh-Hans.md`

**Interfaces:**
- Consumes: 无
- Produces: 两份文案文件，首行为带占位符的标题、随后为 `## 小节` 与 `- 条目`。Task 3 与 Task 4 直接读取它们。

- [ ] **Step 1: 建目录并放入已确认的正文**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
mkdir -p release-notes/1.2.0
cp /tmp/st-release-notes-en.md release-notes/1.2.0/en.md
cp /tmp/st-release-notes-zh.md release-notes/1.2.0/zh-Hans.md
```

若 `/tmp` 中的文件已不存在，用本仓库 `appcast.xml` 中已发布的 1.2.0 条目正文重建：英文取 `<description xml:lang="en">`、简体取 `<description xml:lang="zh-Hans">` 的 CDATA，把 `<h2>x</h2>` 还原为 `## x`、`<li>x</li>` 还原为 `- x`、`<ul>...</ul>` 去掉包裹。

- [ ] **Step 2: 给两份文件加上标题行**

在 `release-notes/1.2.0/en.md` 最前面插入一行（注意是 `%VERSION%` / `%BUILD%` 字面量，不是实际数字）：

```markdown
# Version %VERSION% (Build %BUILD%)
```

在 `release-notes/1.2.0/zh-Hans.md` 最前面插入一行：

```markdown
# 版本 %VERSION%（构建 %BUILD%）
```

- [ ] **Step 3: 验证结构**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
for f in en zh-Hans; do
  printf '%-8s h2=%s bullets=%s title=%s\n' "$f" \
    "$(grep -c '^## ' release-notes/1.2.0/$f.md)" \
    "$(grep -c '^- ' release-notes/1.2.0/$f.md)" \
    "$(head -1 release-notes/1.2.0/$f.md)"
done
```

预期：`en h2=8 bullets=26`、`zh-Hans h2=9 bullets=29`；标题行分别以 `# Version %VERSION%` 与 `# 版本 %VERSION%` 开头。简体比英文多一节是因为「更新下载」只面向中文读者。

- [ ] **Step 4: 提交**

```bash
git add release-notes/1.2.0/en.md release-notes/1.2.0/zh-Hans.md
git commit -m "docs: add the 1.2.0 release notes for English and Simplified Chinese"
```

---

### Task 2: 把 `update-appcast.rb` 改为命名参数的多语言发射器

**Files:**
- Modify: `scripts/update-appcast.rb`（整体重写，143 行 → 约 245 行）

**Interfaces:**
- Consumes: Task 1 的 `release-notes/1.2.0/`
- Produces: 新 CLI——
  `ruby scripts/update-appcast.rb --version V --build N [--minimum-system-version V] [--dmg-url URL --ed-signature SIG --length N] --notes-dir DIR [--appcast PATH] [--output PATH] [--replace-existing]`
  语言顺序常量 `SUPPORTED_LANGUAGES = %w[en ar de es fr it ja ko pt-BR ru zh-Hans zh-Hant]`，`en` 第一。Task 3 依赖 `build_item` 与 `localized_lines` 的现有签名。

- [ ] **Step 1: 用干跑复现当前失败行为**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
ruby scripts/update-appcast.rb --version 1.2.1 --build 10 --notes-dir release-notes/1.2.0 \
  --appcast appcast.xml --output /tmp/dryrun.xml 2>&1 | head -3; echo "exit=$?"
```

预期：旧脚本的参数数量守卫（只接受 7–9 个参数）被 10 个参数触发，打印 usage 并以退出码 2 结束。这就是要修的行为。

- [ ] **Step 2: 整体重写脚本**

用以下内容替换 `scripts/update-appcast.rb` 全文：

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "optparse"
require "time"

# Languages the app ships (Sources/StatusTrioCore/Resources/*.lproj). `en` must
# stay first: Sparkle's -bestNodeInNodes:name: falls back to the first node in
# document order when the user's preferred languages match nothing.
SUPPORTED_LANGUAGES = %w[en ar de es fr it ja ko pt-BR ru zh-Hans zh-Hant].freeze
RTL_LANGUAGES = %w[ar].freeze

def xml_escape(value)
  CGI.escapeHTML(value.to_s)
end

def cdata_escape(value)
  value.to_s.gsub("]]>", "]]]]><![CDATA[>")
end

def notes_to_html(lines)
  html = []
  list_items = []

  flush_list = lambda do
    next if list_items.empty?

    html << "<ul>#{list_items.join}</ul>"
    list_items = []
  end

  lines.map(&:strip).each do |line|
    next if line.empty?
    next if line.match?(/\A#\s+/)

    if (heading = line.match(/\A##\s+(.+)\z/))
      flush_list.call
      html << "<h2>#{xml_escape(heading[1])}</h2>"
    elsif (item = line.match(/\A(?:[-*+]|\d+\.)\s+(.+)\z/))
      list_items << "<li>#{xml_escape(item[1])}</li>"
    else
      list_items << "<li>#{xml_escape(line)}</li>"
    end
  end

  flush_list.call
  html.join
end

def load_notes(dir)
  raise "Release notes directory does not exist: #{dir}" unless File.directory?(dir)

  notes = {}
  Dir.children(dir).sort.each do |name|
    next if name.start_with?(".")
    next unless name.end_with?(".md")

    language = name.delete_suffix(".md")
    unless SUPPORTED_LANGUAGES.include?(language)
      raise "Unsupported release notes language file: #{name} " \
            "(expected one of: #{SUPPORTED_LANGUAGES.join(', ')})"
    end

    notes[language] = File.join(dir, name)
  end

  raise "Release notes directory has no language files: #{dir}" if notes.empty?

  notes
end

def notes_title(path, version, build)
  line = File.readlines(path, chomp: true).find { |candidate| candidate.strip.match?(/\A#\s+\S/) }
  raise "Missing a '# <title>' heading in #{path}." unless line

  title = line.strip.sub(/\A#\s+/, "")
  %w[%VERSION% %BUILD%].each do |token|
    raise "Title in #{path} must contain #{token}." unless title.include?(token)
  end

  title.gsub("%VERSION%", version).gsub("%BUILD%", build)
end

def notes_description(path, language)
  html = notes_to_html(File.readlines(path, chomp: true))
  raise "Release notes for #{language} are empty: #{path}" if html.empty?

  RTL_LANGUAGES.include?(language) ? %(<div dir="rtl">#{html}</div>) : html
end

# Returns [[language, title_line, description_line], ...] with `en` first.
def localized_lines(notes, version, build)
  languages = SUPPORTED_LANGUAGES.select { |language| notes.key?(language) }

  languages.map do |language|
    title = %(<title xml:lang="#{language}">) \
            "#{xml_escape(notes_title(notes[language], version, build))}</title>"
    body = cdata_escape(notes_description(notes[language], language))
    description = %(<description xml:lang="#{language}"><![CDATA[#{body}]]></description>)
    [language, title, description]
  end
end

def build_item(pub_date:, version:, build:, minimum_system_version:, enclosure_lines:, localized:)
  lines = []
  localized.each { |(_, title, _)| lines << title }
  lines << "<pubDate>#{pub_date}</pubDate>"
  lines << "<sparkle:version>#{xml_escape(build)}</sparkle:version>"
  lines << "<sparkle:shortVersionString>#{xml_escape(version)}</sparkle:shortVersionString>"
  lines << "<sparkle:minimumSystemVersion>#{xml_escape(minimum_system_version)}</sparkle:minimumSystemVersion>"
  localized.each { |(_, _, description)| lines << description }
  enclosure_lines.each { |line| lines << line }

  (["    <item>"] + lines.map { |line| "      #{line}" } + ["    </item>"]).join("\n")
end

def new_enclosure_lines(dmg_url:, ed_signature:, dmg_length:)
  [
    %(<enclosure url="#{xml_escape(dmg_url)}"),
    %(           type="application/octet-stream"),
    %(           sparkle:edSignature="#{xml_escape(ed_signature)}"),
    %(           length="#{xml_escape(dmg_length)}" />)
  ]
end

def existing_item(appcast, build)
  appcast.scan(%r{[ \t]*<item>.*?</item>}m).find do |block|
    block.match?(%r{<sparkle:version>\s*#{Regexp.escape(build)}\s*</sparkle:version>})
  end
end

def item_element(block, name, build)
  block[%r{<#{name}>(.*?)</#{name}>}m, 1] ||
    raise("Existing item for build #{build} has no <#{name}>.")
end

def item_enclosure_lines(block, build)
  match = block[%r{[ \t]*<enclosure\b.*?/>}m] ||
          raise("Existing item for build #{build} has no <enclosure>.")
  match.lines.map(&:strip)
end

def parse_options
  options = {}
  OptionParser.new do |parser|
    parser.banner = "Usage: ruby scripts/update-appcast.rb --version V --build N --notes-dir DIR [options]"
    parser.on("--version V") { |value| options[:version] = value }
    parser.on("--build N") { |value| options[:build] = value }
    parser.on("--minimum-system-version V") { |value| options[:minimum] = value }
    parser.on("--dmg-url URL") { |value| options[:dmg_url] = value }
    parser.on("--ed-signature SIG") { |value| options[:signature] = value }
    parser.on("--length N") { |value| options[:length] = value }
    parser.on("--notes-dir DIR") { |value| options[:notes_dir] = value }
    parser.on("--appcast PATH") { |value| options[:appcast] = value }
    parser.on("--output PATH") { |value| options[:output] = value }
    parser.on("--replace-existing") { options[:replace] = true }
  end.parse!

  options[:appcast] ||= File.expand_path("../appcast.xml", __dir__)
  options[:output] ||= options[:appcast]
  options[:minimum] ||= "15.0"

  raise "VERSION must not be empty." if options[:version].to_s.empty?
  raise "BUILD must contain only digits." unless options[:build].to_s.match?(/\A\d+\z/)
  raise "MINIMUM_SYSTEM_VERSION must not be empty." if options[:minimum].to_s.empty?
  raise "Release notes directory must be given with --notes-dir." if options[:notes_dir].to_s.empty?
  raise "Appcast file does not exist: #{options[:appcast]}" unless File.file?(options[:appcast])

  unless options[:replace]
    raise "DMG_URL must use HTTPS." unless options[:dmg_url].to_s.start_with?("https://")
    raise "ED_SIGNATURE must not be empty." if options[:signature].to_s.empty?
    raise "DMG_LENGTH must contain only digits." unless options[:length].to_s.match?(/\A\d+\z/)
  end

  options
end

options = parse_options
appcast = File.read(options[:appcast])
notes = load_notes(options[:notes_dir])
localized = localized_lines(notes, options[:version], options[:build])
raise "No release notes languages found in #{options[:notes_dir]}." if localized.empty?

existing = existing_item(appcast, options[:build])

updated =
  if options[:replace]
    raise "Build #{options[:build]} does not exist in #{options[:appcast]}." unless existing

    stored_version = item_element(existing, "sparkle:shortVersionString", options[:build])
    unless stored_version == options[:version]
      raise "Existing build #{options[:build]} has shortVersionString #{stored_version}, " \
            "expected #{options[:version]}."
    end

    replacement = build_item(
      pub_date: item_element(existing, "pubDate", options[:build]),
      version: stored_version,
      build: options[:build],
      minimum_system_version: item_element(existing, "sparkle:minimumSystemVersion", options[:build]),
      enclosure_lines: item_enclosure_lines(existing, options[:build]),
      localized: localized
    )

    # Block form avoids backreference interpretation in the replacement text.
    appcast.sub(existing) { replacement }
  else
    if existing
      raise "Build #{options[:build]} already exists in #{options[:appcast]}."
    end

    item = build_item(
      pub_date: Time.now.utc.strftime("%a, %d %b %Y %H:%M:%S +0000"),
      version: options[:version],
      build: options[:build],
      minimum_system_version: options[:minimum],
      enclosure_lines: new_enclosure_lines(
        dmg_url: options[:dmg_url],
        ed_signature: options[:signature],
        dmg_length: options[:length]
      ),
      localized: localized
    )

    first_item = appcast.match(/^[ \t]*<item\b/m)
    if first_item
      appcast.dup.insert(first_item.begin(0), "#{item}\n")
    else
      channel_end = appcast.rindex("</channel>")
      raise "Could not find </channel> in #{options[:appcast]}." unless channel_end

      closing_indent = appcast[0...channel_end][/[ \t]*\z/]
      indent_start = channel_end - closing_indent.length
      copy = appcast.dup
      copy[indent_start, closing_indent.length] = "#{item}\n#{closing_indent}"
      copy
    end
  end

File.write(options[:output], updated)
puts "Updated #{options[:output]} with build #{options[:build]} " \
     "(#{localized.length} languages: #{localized.map(&:first).join(', ')})."
```

- [ ] **Step 3: 干跑并断言**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
ruby scripts/update-appcast.rb \
  --version 1.2.1 --build 10 --minimum-system-version 15.0 \
  --dmg-url "https://example.invalid/StatusTrio-1.2.1.dmg" \
  --ed-signature "test-signature" --length 1 \
  --notes-dir release-notes/1.2.0 --appcast appcast.xml --output /tmp/dryrun.xml
xmllint --noout /tmp/dryrun.xml && echo "XML OK"
echo "items: $(grep -c '<item>' /tmp/dryrun.xml)  (baseline $(grep -c '<item>' appcast.xml))"
ruby -e '
  block = File.read("/tmp/dryrun.xml").scan(%r{<item>.*?</item>}m)
              .find { |candidate| candidate.include?("<sparkle:version>10</sparkle:version>") }
  abort("no item for build 10") unless block
  puts "titles=#{block.scan(/<title xml:lang=/).length} descriptions=#{block.scan(/<description xml:lang=/).length}"
  puts "first=#{block[/<title xml:lang="([^"]+)"/, 1]}"
'
echo "仓库文件未被改动: $(git diff --stat appcast.xml | wc -l) 行"
```

断言必须**限定在新条目内**，因为 `appcast.xml` 里 1.2.0 与 1.1.0 各自已有 2 个带 `xml:lang` 的标题，整文件计数会混入历史条目。

预期：`XML OK`；`items: 8`（基准 7 + 新条目）；`titles=2 descriptions=2`（每种语言各一个 title 与一个 description；此刻只有 en 与 zh-Hans）；`first=en`；`git diff --stat appcast.xml` 为 0 行——证明 `--output` 没有碰仓库文件。

- [ ] **Step 4: 验证错误路径**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
# 未识别的语言文件名必须报错
cp release-notes/1.2.0/en.md /tmp/zh-hant.md && mkdir -p /tmp/badnotes && cp release-notes/1.2.0/*.md /tmp/badnotes/ && cp /tmp/zh-hant.md /tmp/badnotes/zh-hant.md
ruby scripts/update-appcast.rb --version 1.2.1 --build 10 --dmg-url https://x.invalid/a.dmg \
  --ed-signature s --length 1 --notes-dir /tmp/badnotes --appcast appcast.xml --output /tmp/x.xml 2>&1 | grep -o 'Unsupported release notes language file: zh-hant.md' || echo "FAIL: 未拦截"
# 重复 build 必须报错
ruby scripts/update-appcast.rb --version 1.2.0 --build 9 --dmg-url https://x.invalid/a.dmg \
  --ed-signature s --length 1 --notes-dir release-notes/1.2.0 --appcast appcast.xml --output /tmp/x.xml 2>&1 | grep -o 'Build 9 already exists' || echo "FAIL: 未拦截"
```

预期：两条各打印对应错误文本，不出现 `FAIL`。

- [ ] **Step 5: 提交**

```bash
git add scripts/update-appcast.rb
git commit -m "refactor(appcast): emit one localized item variant per notes language"
```

---

### Task 3: 增加 `--replace-existing`

**Files:**
- Modify: `scripts/update-appcast.rb`（Task 2 已写入该分支；本任务只验证并补齐断言）

**Interfaces:**
- Consumes: Task 2 的 `existing_item`、`item_element`、`item_enclosure_lines`、`build_item`
- Produces: `--replace-existing` 语义——就地替换同 build 条目，保留 `pubDate`、`sparkle:version`、`sparkle:shortVersionString`、`sparkle:minimumSystemVersion` 与 `enclosure`

- [ ] **Step 1: 干跑替换并核对保留字段**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
ruby scripts/update-appcast.rb --version 1.2.0 --build 9 \
  --notes-dir release-notes/1.2.0 --appcast appcast.xml \
  --output /tmp/replaced.xml --replace-existing
echo "items: $(grep -c '<item>' /tmp/replaced.xml)  (必须仍是 7)"
echo "pubDate: $(grep -o '<pubDate>[^<]*' /tmp/replaced.xml | head -1)  (必须与现网一致)"
xmllint --noout /tmp/replaced.xml && echo "XML OK"
# enclosure 必须逐字保留：把替换前后 1.2.0 条目的 enclosure 段比对
ruby -e '
  pick = lambda do |path|
    File.read(path).scan(%r{<item>.*?</item>}m).find { |b| b.include?("<sparkle:version>9</sparkle:version>") }
  end
  a = pick.call("appcast.xml")[/<enclosure\b.*?\/>/m]
  b = pick.call("/tmp/replaced.xml")[/<enclosure\b.*?\/>/m]
  puts(a == b ? "enclosure 逐字一致 OK" : "FAIL: enclosure 被改动")
'
```

预期：`items: 7`、`pubDate` 仍为 1.2.0 原有的 `Fri, 18 Sep 2026 13:54:08 +0000`（以现网 `appcast.xml` 的值为准）、`XML OK`、`enclosure 逐字一致 OK`。

- [ ] **Step 2: 验证版本不匹配时报错**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
ruby scripts/update-appcast.rb --version 9.9.9 --build 9 \
  --notes-dir release-notes/1.2.0 --appcast appcast.xml \
  --output /tmp/x.xml --replace-existing 2>&1 | grep -o 'expected 9.9.9' || echo "FAIL: 未拦截版本不匹配"
```

预期：打印 `expected 9.9.9`，不出现 `FAIL`。

- [ ] **Step 3: 提交**

```bash
git add scripts/update-appcast.rb
git commit -m "feat(appcast): support replacing an existing item in place"
```

---

### Task 4: 新增 `scripts/validate-appcast-notes.sh`

**Files:**
- Create: `scripts/validate-appcast-notes.sh`

**Interfaces:**
- Consumes: Task 2 的 CLI；环境变量 `VERSION`、`BUILD`、`PUBLISH`、可选 `RELEASE_NOTES_DIR`、`MINIMUM_SYSTEM_VERSION`、`APPCAST_FILE`
- Produces: 退出码 0/1；`publish=true` 时强制 12 种齐全，`publish=false` 时只打印覆盖表并继续

- [ ] **Step 1: 写脚本**

创建 `scripts/validate-appcast-notes.sh`：

```bash
#!/usr/bin/env bash
# Validates release note coverage and the appcast item those notes generate.
#
# Runs on every release dispatch, including publish=false preflights, which is
# what gives this path CI coverage: the appcast is only written when publishing.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION="${VERSION:?VERSION is required}"
BUILD="${BUILD:?BUILD is required}"
PUBLISH="${PUBLISH:-false}"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-15.0}"
NOTES_DIR="${RELEASE_NOTES_DIR:-$ROOT/release-notes/$VERSION}"
APPCAST_FILE="${APPCAST_FILE:-appcast.xml}"
APPCAST_PATH="$ROOT/$APPCAST_FILE"

SUPPORTED=(en ar de es fr it ja ko pt-BR ru zh-Hans zh-Hant)
REQUIRED=(en zh-Hans)

if [[ ! -d "$NOTES_DIR" ]]; then
    if [[ "$PUBLISH" == "true" ]]; then
        echo "::error::Release notes directory does not exist: $NOTES_DIR"
        exit 1
    fi
    echo "::notice::Release notes directory does not exist yet: $NOTES_DIR — skipping validation."
    exit 0
fi

present=()
missing=()
for language in "${SUPPORTED[@]}"; do
    if [[ -f "$NOTES_DIR/$language.md" ]]; then
        present+=("$language")
    else
        missing+=("$language")
    fi
done

echo "Release notes coverage for $VERSION: ${#present[@]}/${#SUPPORTED[@]} languages"
printf '  present: %s\n' "${present[*]}"
printf '  missing: %s\n' "${missing[*]:-none}"

fail=0
if [[ "$PUBLISH" == "true" ]]; then
    for language in "${REQUIRED[@]}"; do
        if [[ ! -f "$NOTES_DIR/$language.md" ]]; then
            echo "::error::Required release notes missing: $NOTES_DIR/$language.md"
            fail=1
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "::error::Release notes missing for: ${missing[*]}"
        fail=1
    fi
    [[ "$fail" -eq 0 ]] || exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioNotes.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

cp "$APPCAST_PATH" "$TEMP_DIR/appcast.xml"
OUTPUT="$TEMP_DIR/generated.xml"

ARGS=(
    --version "$VERSION"
    --build "$BUILD"
    --minimum-system-version "$MINIMUM_SYSTEM_VERSION"
    --notes-dir "$NOTES_DIR"
    --appcast "$TEMP_DIR/appcast.xml"
    --output "$OUTPUT"
)

if grep -qF "<sparkle:version>$BUILD</sparkle:version>" "$TEMP_DIR/appcast.xml"; then
    ARGS+=(--replace-existing)
else
    ARGS+=(--dmg-url "https://example.invalid/StatusTrio-$VERSION.dmg")
    ARGS+=(--ed-signature "validation-only")
    ARGS+=(--length "1")
fi

ruby "$ROOT/scripts/update-appcast.rb" "${ARGS[@]}"
xmllint --noout "$OUTPUT"

ITEM="$TEMP_DIR/item.xml"
ruby -e '
  build = ARGV[1]
  block = File.read(ARGV[0]).scan(%r{[ \t]*<item>.*?</item>}m)
              .find { |candidate| candidate.include?("<sparkle:version>#{build}</sparkle:version>") }
  abort("No appcast item found for build #{build}.") unless block
  print block
' "$OUTPUT" "$BUILD" > "$ITEM"

expected="${#present[@]}"
titles="$(grep -c '<title xml:lang=' "$ITEM" || true)"
descriptions="$(grep -c '<description xml:lang=' "$ITEM" || true)"

if [[ "$titles" -ne "$expected" ]]; then
    echo "::error::Expected $expected localized titles for build $BUILD, found $titles."
    fail=1
fi
if [[ "$descriptions" -ne "$expected" ]]; then
    echo "::error::Expected $expected localized descriptions for build $BUILD, found $descriptions."
    fail=1
fi

first_language="$(grep -o '<title xml:lang="[^"]*"' "$ITEM" | head -1 | sed 's/.*="//; s/"$//')"
if [[ "$first_language" != "en" ]]; then
    echo "::error::The first language variant must be en (Sparkle's fallback is document order), found '${first_language}'."
    fail=1
fi

if grep -qE '%(VERSION|BUILD)%' "$ITEM"; then
    echo "::error::Unsubstituted placeholders remain in the appcast item for build $BUILD."
    fail=1
fi

if grep -qE '<description xml:lang="[^"]*"><!\[CDATA\[\]\]></description>' "$ITEM"; then
    echo "::error::An empty localized description was generated for build $BUILD."
    fail=1
fi

for language in "${present[@]}"; do
    if ! grep -qF "<title xml:lang=\"$language\">" "$ITEM"; then
        echo "::error::Missing appcast title variant for '$language'."
        fail=1
    fi
    if ! grep -qF "<description xml:lang=\"$language\">" "$ITEM"; then
        echo "::error::Missing appcast description variant for '$language'."
        fail=1
    fi
done

[[ "$fail" -eq 0 ]] || exit 1
echo "Appcast notes OK: $titles titles and $descriptions descriptions, en first."
```

- [ ] **Step 2: 让脚本可执行并跑通**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
chmod +x scripts/validate-appcast-notes.sh
VERSION=1.2.0 BUILD=10 PUBLISH=false bash scripts/validate-appcast-notes.sh
```

预期：打印覆盖表（此刻 `2/12 languages`）、`Appcast notes OK: 2 titles and 2 descriptions, en first.`，退出码 0。

- [ ] **Step 3: 验证两条失败路径**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
# publish=true 且语言不全 → 必须失败并列出缺失
VERSION=1.2.0 BUILD=10 PUBLISH=true bash scripts/validate-appcast-notes.sh 2>&1 | grep -o 'Release notes missing for:.*' | head -1; echo "exit=${PIPESTATUS[0]}"
# 目录不存在 + publish=false → 跳过
VERSION=9.9.9 BUILD=99 PUBLISH=false bash scripts/validate-appcast-notes.sh; echo "exit=$?"
```

预期：第一条打印 `Release notes missing for: ar de es fr it ja ko pt-BR ru zh-Hant`（顺序按 `SUPPORTED`）且退出码 1；第二条打印 `skipping validation` 且退出码 0。

- [ ] **Step 4: 提交**

```bash
git add scripts/validate-appcast-notes.sh
git commit -m "test(release): validate multilingual appcast notes on every dispatch"
```

---

### Task 5: 补齐其余 10 种语言文案

**Files:**
- Create: `release-notes/1.2.0/zh-Hant.md`
- Create: `release-notes/1.2.0/ja.md`、`ko.md`、`de.md`、`fr.md`、`es.md`、`it.md`、`pt-BR.md`、`ru.md`、`ar.md`

**Interfaces:**
- Consumes: Task 1 的 `en.md`（唯一基准）、`zh-Hans.md`（繁体基准）、Global Constraints 的术语表
- Produces: 10 份文案文件，供 Task 8 回填 appcast

**术语权威**：`Sources/StatusTrioCore/Resources/<lang>.lproj/Localizable.strings`。高风险术语必须与该语言 lproj 用词一致，例如 `zh-Hant` 用 `圖示` / `捲動` / `音訊` / `設定`（不是 `图标` / `滚动` / `音频` / `设置`），`ru` 的蓝牙音频是 `Звук Bluetooth`（不是 `Аудио`）。规格文档 `docs/superpowers/specs/2026-09-19-multilingual-appcast-notes-design.md` 的术语对照表是完整清单。

**本节是全计划唯一不逐字内联产物内容的步骤**：产物是 10 份自然语言翻译（每份约 30 行），内联进计划会与落库文件重复一倍。取而代之的是可机械验证的结构契约（Step 2）与术语契约（Step 3）。

- [ ] **Step 1: 逐语言产出文件**

每种语言的标题行格式（第一行，占位符保持字面量）：

| 语言 | 标题行 |
| --- | --- |
| `zh-Hant` | `# 版本 %VERSION%（構建 %BUILD%）` |
| `ja` | `# バージョン %VERSION%（ビルド %BUILD%）` |
| `ko` | `# 버전 %VERSION%(빌드 %BUILD%)` |
| `de` | `# Version %VERSION% (Build %BUILD%)` |
| `fr` | `# Version %VERSION% (build %BUILD%)` |
| `es` | `# Versión %VERSION% (compilación %BUILD%)` |
| `it` | `# Versione %VERSION% (build %BUILD%)` |
| `pt-BR` | `# Versão %VERSION% (compilação %BUILD%)` |
| `ru` | `# Версия %VERSION% (сборка %BUILD%)` |
| `ar` | `# الإصدار %VERSION% (البنية %BUILD%)` |

正文：10 种语言全部以 `en.md` 为基准（因此**都不含**「更新下载」小节——该小节只在 `zh-Hans.md` 里）。逐条对应，不增不减。

- [ ] **Step 2: 机械校验结构一致性**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
for f in en zh-Hans zh-Hant ja ko de fr es it pt-BR ru ar; do
  printf '%-8s h2=%-2s bullets=%-2s title=%s\n' "$f" \
    "$(grep -c '^## ' release-notes/1.2.0/$f.md)" \
    "$(grep -c '^- ' release-notes/1.2.0/$f.md)" \
    "$(head -1 release-notes/1.2.0/$f.md)"
done
```

预期：`en` = `h2=8 bullets=26`；`zh-Hans` = `h2=9 bullets=29`（唯一含「更新下载」小节的语言）；其余 11 种（含 `zh-Hant`）= `h2=8 bullets=26`。标题行都含 `%VERSION%` 与 `%BUILD%`。

- [ ] **Step 3: 校验术语用词确实取自 lproj**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
check() { # language, lproj key, expected term
  local term; term="$(grep -m1 "^\"$2\" =" "Sources/StatusTrioCore/Resources/$1.lproj/Localizable.strings" | sed 's/.*= "//; s/";$//')"
  if grep -qF "$term" "release-notes/1.2.0/$1.md"; then echo "OK   $1  $term"; else echo "MISS $1  $term"; fi
}
check zh-Hant settings.statusIcon.title
check zh-Hant settings.popup.volumeScroll.natural
check zh-Hant settings.bluetooth.title
check ja settings.statusIcon.title
check ko settings.statusIcon.title
check de settings.statusIcon.title
check fr settings.statusIcon.title
check es settings.statusIcon.title
check it settings.statusIcon.title
check pt-BR settings.statusIcon.title
check ru settings.bluetooth.title
check ar settings.statusIcon.title
```

预期：12 行全部 `OK`，没有 `MISS`。若某语言正文里该术语的变形（如属格）与 lproj 字面不同导致 `MISS`，改用该语言 lproj 里出现的等价字符串并在提交信息中说明。

- [ ] **Step 4: 跑校验脚本确认 12 语言全绿**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
VERSION=1.2.0 BUILD=10 PUBLISH=true bash scripts/validate-appcast-notes.sh
```

预期：`Release notes coverage for 1.2.0: 12/12 languages`，`missing: none`，`Appcast notes OK: 12 titles and 12 descriptions, en first.`，退出码 0。

- [ ] **Step 5: 确认 RTL 包装只作用于阿拉伯语**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
ruby scripts/update-appcast.rb --version 1.2.1 --build 10 \
  --dmg-url "https://example.invalid/a.dmg" --ed-signature s --length 1 \
  --notes-dir release-notes/1.2.0 --appcast appcast.xml --output /tmp/dryrun.xml
echo "dir=rtl 出现次数: $(grep -o 'dir="rtl"' /tmp/dryrun.xml | wc -l)  (必须为 1)"
grep -o '<description xml:lang="ar">.\{0,20\}' /tmp/dryrun.xml
```

预期：`dir="rtl"` 恰好 1 次，且出现在 `<description xml:lang="ar">` 上。

- [ ] **Step 6: 提交**

```bash
git add release-notes/1.2.0
git commit -m "docs: add the 1.2.0 release notes in the remaining ten languages"
```

---

### Task 6: `release.sh` 改用文案目录

**Files:**
- Modify: `scripts/release.sh:142-155`（删除 `APPCAST_RELEASE_NOTES_*` 块）
- Modify: `scripts/release.sh:276-286`（改为命名参数调用）

**Interfaces:**
- Consumes: Task 2 的 CLI；环境变量 `RELEASE_NOTES_DIR`（默认 `$ROOT/release-notes/$VERSION`）
- Produces: `release.sh` 不再接受 `APPCAST_RELEASE_NOTES_EN_FILE` / `APPCAST_RELEASE_NOTES_ZH_FILE`

- [ ] **Step 1: 替换 notes 变量块**

把 `scripts/release.sh` 中第 142-155 行整块（从 `if [[ -z "${APPCAST_RELEASE_NOTES_FILE:-}" ]]; then` 到该 `fi`）替换为：

```bash
RELEASE_NOTES_DIR="${RELEASE_NOTES_DIR:-$ROOT/release-notes/$VERSION}"

if [[ ! -d "$RELEASE_NOTES_DIR" ]]; then
    echo "Error: release notes directory does not exist: $RELEASE_NOTES_DIR" >&2
    exit 1
fi
```

- [ ] **Step 2: 替换 appcast 调用块**

把第 276-286 行附近构造 `APPCAST_NOTES_ARGS` 并调用 `ruby "$ROOT/scripts/update-appcast.rb" "${APPCAST_NOTES_ARGS[@]}"` 的整块，替换为：

```bash
ruby "$ROOT/scripts/update-appcast.rb" \
    --version "$VERSION" \
    --build "$BUILD" \
    --minimum-system-version "$MINIMUM_SYSTEM_VERSION" \
    --dmg-url "$DMG_URL" \
    --ed-signature "$ED_SIGNATURE" \
    --length "$DMG_LENGTH" \
    --notes-dir "$RELEASE_NOTES_DIR" \
    --appcast "$APPCAST_PATH"
```

保留其后的 `xmllint --noout "$APPCAST_PATH"` 与 appcast 上传、build 断言逻辑不变。

- [ ] **Step 3: 确认没有遗留引用**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
grep -n "APPCAST_RELEASE_NOTES" scripts/release.sh || echo "无遗留引用 OK"
bash -n scripts/release.sh && echo "语法 OK"
```

预期：`无遗留引用 OK` 与 `语法 OK`。

- [ ] **Step 4: 用 `publish=false` 路径确认不回归**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
grep -n "PUBLISH.*== \"false\"" -A3 scripts/release.sh | head -8
```

预期：`PUBLISH=false` 的提前 `exit 0` 仍在 appcast 调用之前，因此预检不受 `RELEASE_NOTES_DIR` 影响。

- [ ] **Step 5: 提交**

```bash
git add scripts/release.sh
git commit -m "refactor(release): read appcast notes from release-notes/<version>"
```

---

### Task 7: 打通 workflow

**Files:**
- Modify: `.github/workflows/release.yml`（`on.workflow_dispatch.inputs` 删除两项；`Prepare release notes` 重写；新增 `Validate appcast notes`）

**Interfaces:**
- Consumes: Task 4 的 `scripts/validate-appcast-notes.sh`
- Produces: dispatch 输入从 6 个降为 4 个（`version`、`build`、`tag`、`publish`）

- [ ] **Step 1: 删除两个文案输入**

从 `.github/workflows/release.yml` 的 `workflow_dispatch.inputs` 中删除这一段：

```yaml
      release_notes:
        description: "English release notes. One bullet per line. Defaults to commits since the previous tag."
        required: false
        type: string
      release_notes_zh:
        description: "Chinese release notes. One bullet per line. Required when publish=true."
        required: false
        type: string
```

- [ ] **Step 2: 重写 `Prepare release notes` 步骤**

用以下内容替换该步骤整体：

```yaml
      - name: Prepare release notes
        if: ${{ env.PUBLISH == 'true' }}
        run: |
          set -euo pipefail
          NOTES_DIR="${GITHUB_WORKSPACE}/release-notes/${VERSION}"
          RELEASE_BODY_PATH="${RUNNER_TEMP}/github-release-notes.md"

          for language in en zh-Hans; do
            if [[ ! -f "${NOTES_DIR}/${language}.md" ]]; then
              echo "::error::Release notes file does not exist: ${NOTES_DIR}/${language}.md"
              exit 1
            fi
          done

          {
            printf '# Version %s （English + 中文， 中文在下方）\n\n' "${VERSION}"
            printf '## English\n\n'
            grep -v '^# ' "${NOTES_DIR}/en.md"
            printf '\n## 中文\n\n'
            grep -v '^# ' "${NOTES_DIR}/zh-Hans.md"
          } > "${RELEASE_BODY_PATH}"

          {
            printf '\n## First launch / 首次启动\n\n'
            printf 'If macOS blocks the first launch, run:\n\n'
            printf '```bash\n'
            printf 'xattr -dr com.apple.quarantine "/Applications/Status Trio.app"\n'
            printf 'open "/Applications/Status Trio.app"\n'
            printf '```\n\n'
            printf '如果 macOS 阻止首次启动，请运行：\n\n'
            printf '```bash\n'
            printf 'xattr -dr com.apple.quarantine "/Applications/Status Trio.app"\n'
            printf 'open "/Applications/Status Trio.app"\n'
            printf '```\n'
          } >> "${RELEASE_BODY_PATH}"

          {
            echo "RELEASE_NOTES_DIR=${NOTES_DIR}"
            echo "RELEASE_BODY_FILE=${RELEASE_BODY_PATH}"
          } >> "${GITHUB_ENV}"
```

`grep -v '^# '` 只剥离单层 `# ` 标题行，`## 小节` 不受影响——正文不需要每语言的标题（正文自己有一级标题）。

- [ ] **Step 3: 新增校验步骤**

紧接在 `Resolve release version` 步骤之后插入：

```yaml
      - name: Validate appcast notes
        run: bash scripts/validate-appcast-notes.sh
```

`VERSION`、`BUILD`、`PUBLISH` 由 `Resolve release version` 写入 `GITHUB_ENV` 与 job 级 `env`，无需再传。该步骤没有 `if:`，因此 `publish=false` 预检也会执行。

- [ ] **Step 4: 校验 YAML 与输入数量**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
ruby -ryaml -e '
  yaml = YAML.load_file(".github/workflows/release.yml")
  inputs = yaml["on"]["workflow_dispatch"]["inputs"].keys
  puts "inputs(#{inputs.length}): #{inputs.join(", ")}"
  steps = yaml["jobs"]["release"]["steps"].map { |s| s["name"] }.compact
  puts "validate step 存在: #{steps.include?("Validate appcast notes")}"
  puts "prepare step 存在: #{steps.include?("Prepare release notes")}"
  puts "残留 inputs 引用: #{File.read(".github/workflows/release.yml").scan(/inputs\.release_notes/).length}"
'
```

预期：`inputs(4): version, build, tag, publish`；两个 `存在` 都是 `true`；`残留 inputs 引用: 0`。

- [ ] **Step 5: 本地复现校验步骤**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
VERSION=1.2.0 BUILD=10 PUBLISH=false bash scripts/validate-appcast-notes.sh
```

预期：覆盖表 + `Appcast notes OK: 12 titles and 12 descriptions, en first.`，退出码 0。

- [ ] **Step 6: 提交**

```bash
git add .github/workflows/release.yml
git commit -m "ci(release): read notes from the repo and validate appcast notes on every dispatch"
```

---

### Task 8: 回填 1.2.0 的 appcast 条目

**Files:**
- Modify: `appcast.xml`（1.2.0 条目由 2 个语言变体扩为 12 个）

**Interfaces:**
- Consumes: Task 3 的 `--replace-existing`；Task 5 的 12 份文案
- Produces: 已发布 appcast 中 1.2.0 条目含 12 个 `title` 与 12 个 `description`

- [ ] **Step 1: 先干跑，确认替换结果正确**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
ruby scripts/update-appcast.rb --version 1.2.0 --build 9 \
  --notes-dir release-notes/1.2.0 --appcast appcast.xml \
  --output /tmp/backfill.xml --replace-existing
xmllint --noout /tmp/backfill.xml && echo "XML OK"
echo "items: $(grep -c '<item>' /tmp/backfill.xml)  (必须为 7)"
ruby -e '
  block = File.read("/tmp/backfill.xml").scan(%r{<item>.*?</item>}m)
              .find { |candidate| candidate.include?("<sparkle:version>9</sparkle:version>") }
  abort("no item for build 9") unless block
  puts "titles=#{block.scan(/<title xml:lang=/).length} descriptions=#{block.scan(/<description xml:lang=/).length}"
'
```

预期：`XML OK`、`items: 7`、`titles=12 descriptions=12`（1.2.0 条目 12 个语言各一对）。同样必须限定在条目内计数。

- [ ] **Step 2: 确认 1.1.0 条目未被改动**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
ruby -e '
  pick = lambda do |path|
    File.read(path).scan(%r{<item>.*?</item>}m).find { |b| b.include?("<sparkle:version>8</sparkle:version>") }
  end
  puts(pick.call("appcast.xml") == pick.call("/tmp/backfill.xml") ? "1.1.0 条目逐字未变 OK" : "FAIL: 1.1.0 条目被改动")
'
```

预期：`1.1.0 条目逐字未变 OK`。

- [ ] **Step 3: 落盘并跑全量校验**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
ruby scripts/update-appcast.rb --version 1.2.0 --build 9 \
  --notes-dir release-notes/1.2.0 --appcast appcast.xml --replace-existing
xmllint --noout appcast.xml && echo "XML OK"
VERSION=1.2.0 BUILD=9 PUBLISH=true bash scripts/validate-appcast-notes.sh
git diff --stat appcast.xml
```

预期：`XML OK`；校验打印 `12/12 languages` 且 `12 titles and 12 descriptions, en first.`；`git diff --stat` 显示仅 `appcast.xml` 变动，约 20 行新增（10 个新语言 × 2 个节点），且无删除行。

- [ ] **Step 4: 确认 Sparkle 关心的字段未变**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
git diff appcast.xml | grep -E '^[-+].*(sparkle:version|shortVersionString|minimumSystemVersion|enclosure|pubDate)' || echo "版本/签名/日期字段未被改动 OK"
```

预期：打印 `版本/签名/日期字段未被改动 OK`。

- [ ] **Step 5: 提交并推送**

```bash
git add appcast.xml
git commit -m "docs(appcast): backfill the 1.2.0 release notes in all twelve languages"
git push origin main
```

---

### Task 9: 同步规则与发布文档

**Files:**
- Modify: `AGENTS.md:64`
- Modify: `AGENTS.md`（Release Rules 区块）
- Modify: `docs/github-actions-release.md`

**Interfaces:**
- Consumes: 前八个任务确立的行为
- Produces: 规则文本与实际行为一致

- [ ] **Step 1: 改写 `AGENTS.md` 第 64 条**

把该行替换为：

```markdown
- Sparkle appcast items are localized per language: emit one `<title xml:lang="…">` and one `<description xml:lang="…">` for every language present in `release-notes/<version>/`, give every variant an explicit `xml:lang`, and keep `en` first because Sparkle falls back to the first node in document order when the user's preferred languages match nothing. Never stack two languages inside one `<description>`.
```

- [ ] **Step 2: 在 Release Rules 里补文案目录约定**

在第 64 条之后插入一条：

```markdown
- User-facing release notes live in `release-notes/<version>/<language>.md`, one file per language the app ships (`Sources/StatusTrioCore/Resources/*.lproj` names, case-sensitive). `en.md` and `zh-Hans.md` are always required and also form the GitHub Release body; `publish=true` additionally requires all 12 languages. Every file starts with a `# <title>` line containing the `%VERSION%` and `%BUILD%` placeholders. `bash scripts/validate-appcast-notes.sh` checks coverage and the generated appcast XML, and the release workflow runs it on every dispatch, including `publish=false` preflights.
```

- [ ] **Step 3: 同步 `docs/github-actions-release.md`**

在该文档「触发方式 › 手动运行正式发布」的输入列表中删除这两行：

```markdown
- `release_notes`：英文说明，每行一个列表项；留空时根据上一个 tag 到当前提交自动生成
- `release_notes_zh`：中文说明，每行一个列表项；`publish=true` 时必填
```

替换为：

```markdown
- 文案不再通过输入传入：改为读取仓库内的 `release-notes/<version>/`，语言文件名与 `Resources/*.lproj` 一致（大小写敏感）。英文与简体是必需项，`publish=true` 时要求 12 种齐全。
- 每个 dispatch（含 `publish=false` 预检）都会运行 `scripts/validate-appcast-notes.sh`：打印语言覆盖表，并把生成的 appcast 条目干跑到临时文件后断言 XML 合法、变体齐全、`en` 排第一、无未替换占位符。
```

并在「Release notes 规则」章节中，把描述 appcast 双语的那段结尾补一句：

```markdown
每个新条目为 `release-notes/<version>/` 中每种语言发射一组带显式 `xml:lang` 的 `<title>` 与 `<description>`，`en` 必须排第一（Sparkle 无匹配时按文档顺序兜底）。GitHub Release 正文仍为英文 + 简体双语。
```

- [ ] **Step 4: 确认文档不再引用已删除的输入**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
grep -n "release_notes_zh\|release_notes\b" docs/github-actions-release.md AGENTS.md .github/workflows/release.yml || echo "无过时引用 OK"
```

预期：`无过时引用 OK`。

- [ ] **Step 5: 提交**

```bash
git add AGENTS.md docs/github-actions-release.md
git commit -m "docs: document the multilingual release notes workflow"
```

---

### Task 10: 端到端验证

**Files:**
- 无文件改动；产生一次 CI 预检 run

**Interfaces:**
- Consumes: 全部前序任务
- Produces: 一次 `publish=false` 预检，其中 `Validate appcast notes` 步骤真实执行并通过

- [ ] **Step 1: 本地跑完整断言套件**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
VERSION=1.2.0 BUILD=9 PUBLISH=true bash scripts/validate-appcast-notes.sh
echo "exit=$?"
```

预期：build 9 已存在于 appcast，因此走 `--replace-existing` 分支（顺带覆盖 Task 3 的路径）；打印 `12/12 languages`、`12 titles and 12 descriptions, en first.`、`exit=0`。

- [ ] **Step 2: 确认工作树干净**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
git status --porcelain
git log --oneline -10
```

预期：除已知的未跟踪 `.agents/skills/ui-ux-pro-max/scripts/__pycache__/`（已被 `.gitignore` 忽略，不应再出现）与 `marketing/animations/` 外无改动；提交历史包含本计划 9 次提交。

- [ ] **Step 3: 推送并跑预检**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
git push origin main
gh workflow run release.yml --repo lingyired/status-trio --ref main \
  -f version=1.2.0 -f build=10 -f publish=false
sleep 10
gh run list --workflow=release.yml --limit 2 --json databaseId,headSha,status --jq '.[] | "\(.databaseId) \(.headSha[0:7]) \(.status)"'
```

为什么必须是 `version=1.2.0` 配 `build=10`：`version` 要指向**已存在文案目录**的版本，否则校验步骤会因目录缺失走「跳过」分支，等于没验证；`build` 要**大于已发布的 9**，否则 `release.sh` 的构建号单调性检查（`build must be greater than the latest published build`）会让预检直接 abort。build 10 不在 appcast 中，因此校验会走「新条目」分支。

预期：推送成功；最新 run 的 `headSha` 是本计划的最后一个提交（**不是**推送前的旧 SHA——注意本仓库此前出现过推送与 dispatch 之间 main 前移的情况）。

- [ ] **Step 4: 观察预检结果**

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio
gh run watch <run-id> --repo lingyired/status-trio --exit-status
gh run view <run-id> --json jobs --jq '.jobs[].steps[] | select(.name=="Validate appcast notes") | "\(.name): \(.conclusion)"'
```

预期：`Validate appcast notes: success`，且 run 整体 success。若该步骤失败，按 `docs/swift-6.1-ci-compatibility.md` 的规则追加失败记录（run ID、失败阶段、根因、修复、验证结果）。

- [ ] **Step 5: 无需提交**

本任务不产生文件改动。若预检暴露问题，回到对应任务修复后重跑 Step 3。

---

## Self-Review

**1. Spec 覆盖**

| Spec 章节 | 对应任务 |
| --- | --- |
| 语言集合与标签 | Task 2（`SUPPORTED_LANGUAGES`）、Task 5 |
| Sparkle 匹配依据（`en` 第一） | Task 2、Task 4（`first_language` 断言） |
| 目录约定 / 文件格式 | Task 1、Task 5 |
| 数据流 | Task 6、Task 7 |
| `update-appcast.rb` 接口 | Task 2、Task 3 |
| `release.sh` 接口 | Task 6 |
| workflow 接口 + 校验步骤 | Task 7 |
| 校验规则与边界 | Task 4（含 `publish` 分支）、Task 2 Step 4 |
| 翻译策略与术语 | Task 5 Step 3 |
| 1.2.0 回填 | Task 8 |
| 规则与文档更新 | Task 9 |
| 测试与验证 | Task 4、Task 10 |
| 范围外事项 | 未产生任务（符合预期） |

**2. 占位符扫描**：无 `TBD` / `TODO` / 「类似 Task N」。Task 5 是唯一未逐字内联产物内容的任务，已在该任务开头显式说明原因，并以结构契约（Step 2）与术语契约（Step 3）替代——产物是自然语言文本而非代码。

**3. 类型与命名一致性**：CLI 参数名在 Task 2（定义）、Task 4（调用）、Task 6（调用）、Task 8（调用）中一致：`--version --build --minimum-system-version --dmg-url --ed-signature --length --notes-dir --appcast --output --replace-existing`。Ruby 内部函数 `build_item` / `localized_lines` / `existing_item` / `item_element` / `item_enclosure_lines` / `new_enclosure_lines` 在 Task 2 定义并在 Task 3 复用，签名一致。Shell 变量 `SUPPORTED` / `REQUIRED` / `present` / `missing` / `ITEM` / `expected` 在 Task 4 内自洽。
