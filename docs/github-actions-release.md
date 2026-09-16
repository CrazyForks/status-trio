# GitHub Actions 自动发布

`.github/workflows/release.yml` 会在 macOS runner 上完成：

1. 构建 `arm64 + x86_64` 通用应用
2. 生成 DMG 和 SHA-256 校验文件
3. 使用 Sparkle EdDSA 私钥签名 DMG
4. 创建 GitHub Release 并上传 DMG
5. 更新并发布 `appcast.xml`

> 开发前请先阅读 [Swift 6.1 CI 兼容性规则](swift-6.1-ci-compatibility.md)。CI 使用 Xcode 16.4 / Swift 6.1.2，本机较新的 Swift 工具链不能替代 CI 验证。

## 触发方式

### 手动运行正式发布

在 GitHub Actions 页面选择 **Build and Release macOS**：

- `version`：例如 `1.2.0`；留空时读取 `Support/Info.plist`
- `build`：显式的数字构建号，必须大于 appcast 中已发布的最大构建号
- `publish=false`：只构建 DMG，并上传为 Actions artifact
- `publish=true`：创建 Release、创建 tag，并更新 Sparkle appcast
- `release_notes`：英文说明，每行一个列表项；留空时根据上一个 tag 到当前提交自动生成
- `release_notes_zh`：中文说明，每行一个列表项；`publish=true` 时必填

正式发布统一使用手动 workflow，因为 `publish=true` 需要同时提供双语说明。workflow 会在 GitHub Release 不存在对应 tag 时自动从 `main` 创建 tag。

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

工作流会根据 `version` 自动生成标题，并把 `release_notes` 和 `release_notes_zh` 合并为上述格式。`publish=true` 时必须提供 `release_notes_zh`；未提供 `release_notes` 时，英文部分会根据上一个 tag 到当前提交自动生成。

Sparkle `appcast.xml` 使用双语说明：条目标题包含版本号和 `（English + 中文， 中文在下方）`，描述按 English、中文两个区块显示。

GitHub Release 正文会在双语说明后自动追加首次启动提示：

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
open "/Applications/Status Trio.app"
```

这些首次启动命令只写入 GitHub Release，不写入 Sparkle appcast。

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
