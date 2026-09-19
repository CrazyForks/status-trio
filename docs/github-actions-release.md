# GitHub Actions 自动发布

`.github/workflows/release.yml` 会在 macOS runner 上完成：

1. 构建 `arm64 + x86_64` 通用应用
2. 生成 DMG 和 SHA-256 校验文件
3. 使用 Sparkle EdDSA 私钥签名 DMG
4. 创建 GitHub Release 并上传 DMG
5. 更新并发布 `appcast.xml`

> 开发前请先阅读 [Swift 工具链 CI 兼容性规则](swift-ci-compatibility.md)。CI 使用 `macos-26` / Xcode 26.6 / Swift 6.3.3，本机较新的 Swift 工具链不能替代 CI 验证。

## 触发方式

### 手动运行正式发布

在 GitHub Actions 页面选择 **Build and Release macOS**：

- `version`：例如 `1.2.0`；留空时读取 `Support/Info.plist`
- `build`：显式的数字构建号，必须大于 appcast 中已发布的最大构建号
- `publish=false`：只构建 DMG，并上传为 Actions artifact
- `publish=true`：创建 Release、创建 tag，并更新 Sparkle appcast

文案不再通过输入传入，改为读取仓库内的 `release-notes/<version>/`。每个 dispatch（含 `publish=false` 预检）都会运行 `scripts/validate-appcast-notes.sh`，打印语言覆盖表，并把生成的 appcast 条目干跑到临时文件后断言 XML 合法、变体齐全、`en` 排第一、无未替换占位符。

正式发布统一使用手动 workflow。workflow 会在 GitHub Release 不存在对应 tag 时自动从 `main` 创建 tag。

## 文案目录

每个版本一个目录，每种语言一个文件，语言名与 `Sources/StatusTrioCore/Resources/*.lproj` 逐字一致（大小写敏感）：

```
release-notes/1.2.0/
  en.md  zh-Hans.md  zh-Hant.md  ja.md  ko.md
  de.md  fr.md       es.md       it.md  pt-BR.md  ru.md  ar.md
```

- 每份文件第一行是 `# <标题>`，必须同时含 `%VERSION%` 与 `%BUILD%` 占位符，由脚本注入实际数字（这样标题里的版本号不可能手写错）。
- 其余行为 `- 条目` 或 `## 小节`；空行忽略；不要写 `**加粗**` 之类的 Markdown 内联语法，它们会被 XML 转义成字面量。
- `en.md` 与 `zh-Hans.md` 一份两用：既进 appcast，也拼成 GitHub Release 正文的英文段与中文段。
- 术语必须取自该语言已有的 `.lproj` 字符串，而不是字面转换。例如繁体用「圖示 / 捲動 / 音訊 / 設定」，简体用「电池详情」而不是「电量详情」。
- 只有 `zh-Hans` 包含针对中国大陆网络的镜像回退说明，其余语言不含。

## Release notes 规则

GitHub Release 正文必须包含英文和中文，英文在上、中文在下，并使用版本号标题：

```markdown
# Version 1.2.0 （English + 中文， 中文在下方）

## English

- English change one.
- English change two.

## 中文

- 中文变更一。
- 中文变更二。
```

工作流会根据 `version` 自动生成标题，并把 `release-notes/<version>/en.md` 与 `zh-Hans.md` 合并为上述格式，同时剥掉每份文件的 `# ` 标题行（正文自己有一级标题）。

Sparkle `appcast.xml` 使用分语言说明：每个新条目为文案目录中每种语言写入一组带显式 `xml:lang` 的 `<title>` 与 `<description>`，`en` 必须排第一——Sparkle 的 `-bestNodeInNodes:name:` 在用户偏好语言都匹配不到时取**文档顺序第一个节点**作为兜底。把两种语言堆进同一个 `<description>` 会让所有用户都看到双语。`publish=true` 要求 12 种语言齐全，`publish=false` 只警告不阻断。GitHub Release 正文始终是英文 + 简体双语。

GitHub Release 正文会在双语说明后自动追加首次启动提示：

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
open "/Applications/Status Trio.app"
```

这些首次启动命令只写入 GitHub Release，不写入 Sparkle appcast。

## 预检产物与更新验证

`publish=false` 的预检产物使用的是**下一个正式版的构建号**（准备发布 1.2.0 / build 9 时，预检也用 build 9）。Sparkle 只按 `sparkle:version`（即 `CFBundleVersion`）判断新旧，因此有两条硬性注意事项：

- **不要把预检产物安装到 `/Applications`。** 本机一旦存在构建号相同的应用，正式版发布后 Sparkle 会判定「已是最新」，这台机器就再也收不到该版本的更新。需要在本机试用预检构建时，改用 `scripts/build-worktree.sh` 产出的构建——它的 bundle id 带 `.dev.<branch>` 后缀，不会覆盖正式安装。
- **验证「旧版本 → 新版本」的更新链路时，必须先安装上一个正式发布的构建号。** 例如验证 1.2.0 时先装 1.1.0（build 8），`9 > 8` 才成立；装预检构建无法测出更新。

Sparkle 的磁盘缓存还会掩盖网络结果：`~/Library/Caches/com.lingsmbp.StatusTrio/` 里缓存过比较新的 feed 时，即使这次网络请求失败，也可能照常显示「有更新」。要验证真实网络路径（包括镜像回退是否生效），先清掉缓存再检查：

```bash
osascript -e 'quit app "Status Trio"' 2>/dev/null
rm -rf ~/Library/Caches/com.lingsmbp.StatusTrio
```

查看这次检查实际请求了哪个源：

```bash
sqlite3 ~/Library/Caches/com.lingsmbp.StatusTrio/Cache.db \
  "select request_key, time_stamp from cfurl_cache_response;"
```

出现 `raw.githubusercontent.com` 之外、带 `gh-proxy.com/` 或 `ghfast.top/` 前缀的记录，说明镜像回退已经接管。

## 第一次配置

### 1. 配置 Sparkle EdDSA 私钥

私钥必须与 `Support/Info.plist` 中的 `SUPublicEDKey` 配对。导出当前 Sparkle 私钥：

```bash
KEY_DIR="$(mktemp -d)"
KEY_FILE="$KEY_DIR/sparkle-private-key"
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x "$KEY_FILE"
gh secret set SPARKLE_PRIVATE_KEY < "$KEY_FILE"
rm -f "$KEY_FILE"
rmdir "$KEY_DIR"
```

不要把导出的私钥提交到 Git，也不要在 issue 或日志中粘贴私钥。

### 2. 让上传内容可匿名下载

Sparkle 无法从私有 GitHub Release 更新。二选一：

#### 方案 A：源码仓库公开

将 `lingyired/status-trio` 改为 public。当前 `SUFeedURL` 已经指向：

```text
https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml
```

#### 方案 B：使用独立的公开更新仓库

保留源码仓库为 private，新建公开仓库，例如 `lingyired/status-trio-updates`，并在其中放置 `appcast.xml`。将本项目的 `release.json` 和 `Support/Info.plist` 指向该更新仓库：

```json
"github_repo": "lingyired/status-trio-updates"
```

```text
SUFeedURL=https://raw.githubusercontent.com/lingyired/status-trio-updates/main/appcast.xml
```

也可以不修改文件，而是在 GitHub 设置仓库变量覆盖：

```bash
gh variable set RELEASE_REPO --body "lingyired/status-trio-updates"
gh variable set RELEASE_BRANCH --body "main"
```

跨仓库写入需要 PAT，设置 `RELEASE_TOKEN` secret。PAT 至少需要目标更新仓库的 `Contents: Read and write` 权限：

```bash
gh secret set RELEASE_TOKEN
```

如果更新仓库与源码仓库相同且仓库为 public，可以省略 `RELEASE_TOKEN`，工作流会使用内置 `GITHUB_TOKEN`。

### 3. 可选：Developer ID 签名和 Apple 公证

未配置证书时，工作流使用 Ad-hoc 签名。用户可以安装和更新，但第一次手动安装可能需要移除 quarantine：

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
```

配置 Developer ID 后无需这一步。需要以下 repository secrets：

| Secret | 内容 |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12` | Developer ID Application `.p12` 文件的 Base64 |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | `.p12` 密码 |
| `APPSTORE_CONNECT_API_KEY_ID` | App Store Connect API Key ID |
| `APPSTORE_CONNECT_API_ISSUER_ID` | App Store Connect Issuer ID |
| `APPSTORE_CONNECT_API_PRIVATE_KEY` | `AuthKey_*.p8` 文件内容 |

生成证书 secret：

```bash
base64 -i DeveloperIDApplication.p12 | gh secret set DEVELOPER_ID_CERTIFICATE_P12
gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD
gh secret set APPSTORE_CONNECT_API_KEY_ID
gh secret set APPSTORE_CONNECT_API_ISSUER_ID
gh secret set APPSTORE_CONNECT_API_PRIVATE_KEY < AuthKey_XXXXXXXXXX.p8
```

## 本地验证

只构建 DMG，不连接 GitHub：

```bash
PUBLISH=false UNIVERSAL_BUILD=1 bash scripts/release.sh
```

本地发布需要本机 Keychain 中有 Sparkle 私钥，并且 `gh` 已登录：

```bash
PUBLISH=true UNIVERSAL_BUILD=1 bash scripts/release.sh
```
