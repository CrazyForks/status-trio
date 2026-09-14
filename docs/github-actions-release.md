# GitHub Actions 自动发布

`.github/workflows/release.yml` 会在 macOS runner 上完成：

1. 构建 `arm64 + x86_64` 通用应用
2. 生成 DMG 和 SHA-256 校验文件
3. 使用 Sparkle EdDSA 私钥签名 DMG
4. 创建 GitHub Release 并上传 DMG
5. 更新并发布 `appcast.xml`

> 开发前请先阅读 [Swift 6.1 CI 兼容性规则](swift-6.1-ci-compatibility.md)。CI 使用 Xcode 16.4 / Swift 6.1.2，本机较新的 Swift 工具链不能替代 CI 验证。

## 触发方式

### 推送版本 tag

先更新 `Support/Info.plist`：

```text
CFBundleShortVersionString = 1.2.0
CFBundleVersion            = 2
```

提交并推送 tag：

```bash
git add Support/Info.plist
git commit -m "release: v1.2.0"
git tag v1.2.0
git push origin main
git push origin v1.2.0
```

tag 必须与 `CFBundleShortVersionString` 一致。构建号必须大于 appcast 中已经发布的最大构建号。

### 手动运行

在 GitHub Actions 页面选择 **Build and Release macOS**：

- `version`：留空时读取 `Support/Info.plist`
- `build`：留空时使用 workflow run number
- `publish=false`：只构建 DMG，并上传为 Actions artifact
- `publish=true`：创建 Release 并更新 Sparkle appcast

## Release notes 规则

Release notes 必须始终使用英文，包括 GitHub Release 正文、Sparkle `appcast.xml` 描述、手动 workflow 的 `release_notes` 输入以及发布公告。不要使用中文或其他语言。

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
