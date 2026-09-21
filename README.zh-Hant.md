<p align="center">
  <img src="screenshots/status-trio-dock-state-strip-symmetric.png" width="1000" alt="Status Trio 八種 Dock 圖示狀態，深色與淺色背景對稱排列，包含 Wi-Fi、藍牙音訊、電池、圓點和圓弧狀態">
</p>

<p align="center">
  <img src="Support/AppIcon.png" width="112" alt="Status Trio 應用程式圖示">
</p>

<h1 align="center">Status Trio</h1>

<p align="center">
  <a href="https://trendshift.io/repositories/234371?utm_source=trendshift-badge&utm_medium=badge&utm_campaign=badge-trendshift-234371" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/234371/daily?language=Swift" alt="lingyired/status-trio | Trendshift" width="250" height="55"/></a>
</p>

<p align="center"><strong>三種系統訊號，一個原生 macOS 狀態圖示 —— 就在你的選單列或 Dock。</strong></p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-Universal%20%C2%B7%20macOS%2015%2B-000000?logo=apple&logoColor=white&style=for-the-badge" alt="下載 macOS 版 —— 通用二進位檔，需 macOS 15 或以上版本"></a>
</p>

<p align="center">
  想先看看實際效果？打開 <a href="https://statustrio.lingai.net/">statustrio.lingai.net</a>，就能在瀏覽器裡模擬每一種圖示狀態。
</p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/github/v/release/lingyired/status-trio?label=release&color=blue" alt="最新發行版本"></a>
  <a href="https://github.com/lingyired/status-trio/actions/workflows/release.yml"><img src="https://github.com/lingyired/status-trio/actions/workflows/release.yml/badge.svg" alt="Build and Release macOS 工作流程狀態"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/lingyired/status-trio?label=license" alt="授權條款：Apache-2.0"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B%20supported-blue?logo=apple&logoColor=white" alt="支援 macOS 15 或以上版本">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="通用二進位檔，支援 Apple Silicon 與 Intel">
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-Hans.md">简体中文</a> ·
  <strong>繁體中文</strong> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português (Brasil)</a> ·
  <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="screenshots/menu-bar-wifi.jpg" width="1000" alt="Status Trio 選單列圖示：連接 Wi-Fi 時顯示 Wi-Fi 符號，並展開狀態彈出式視窗">
</p>

Status Trio 是一款原生 macOS 狀態應用程式，把 Wi-Fi、電池和音量整合成一個精巧、可自訂的圖示，顯示在選單列、Dock，或兩處同時顯示。它的彈出式視窗比圖示本身更深入：可用 Wi-Fi 面板查看附近網路與連線詳情、用藍牙面板查看已配對的裝置、還有「電池詳細資訊」頁面，以及正在播放的音訊裝置。靈感來自 iPhone Duo 把 Wi-Fi、電池和行動網路合併顯示的狀態列圖示，並在 Mac 上以音量取代行動網路。

> Status Trio 是獨立專案，與 Apple 沒有任何隸屬關係。

## 主要特色

- **一個圖示，三種訊號** —— 電池、Wi-Fi 和音量在選單列、Dock 或兩處共用同一個圖示，而正在播放的藍牙裝置還能以自己的符號佔據中間的位置。
- **藍牙** —— 播放時音量指示會變成藍色。面板會列出已連接與已配對的裝置及 AirPods 電量，並且在你啟用之前保持關閉。
- **電池** —— 顯示電量百分比、充電中或已連接電源、預計充滿時間，電量偏低時還會變色。打開該列可查看電源轉接器額定功率、電壓、電流、循環使用次數和低耗電模式。
- **Wi-Fi** —— 顯示你目前所在的網路與訊號強弱。打開後可查看附近的網路、鏈路詳細資訊，或直接關閉 Wi-Fi。切換網路請在系統設定的 Wi-Fi 面板中操作。
- **音量** —— 音量大小、靜音狀態和輸出裝置，以圓點或圓弧呈現。可捲動整個面板或只捲動控制項，並選擇哪個方向是調高音量。
- **打造自己的風格** —— 圖示顯示尺寸、符號縮放比例、外環線條粗細、狀態顏色，以及彈出式視窗要顯示哪些區塊、以什麼順序排列。
- **選單列、Dock，或兩處同時顯示** —— 而 Dock 圖示可以跟隨系統樣式，或固定為深色或淺色。
- **原生 macOS 體驗** —— 按左鍵打開彈出式視窗，按右鍵打開選單，首次啟動時還有導覽逐一解說圖示的每個部分。如果你比較喜歡，乙太網路、個人熱點或網際網路共享也可以保留 Wi-Fi 符號。
- **保持最新** —— 狀態來自系統事件，並以低頻輪詢作為備援；Sparkle 會透過已簽署的更新來源更新應用程式。
- **還包括** —— 十二種語言，以及可選的開機時啟動。

## 藍牙音訊

當音訊透過藍牙播放時，**設定 › 藍牙**中的兩個開關會讓中間的符號變成該裝置自己的符號 —— AirPods、耳機、揚聲器與其他裝置會各自提供 —— 並讓音量圓點或圓弧變成藍色。兩者預設都是關閉。預設開啟的**網路異常優先於藍牙圖示**會在連線本身出問題時保留網路圖示：

<p align="center">
  <img src="screenshots/menu-bar-airpods.jpg" width="1000" alt="Status Trio 選單列圖示：連接 AirPods 時顯示 AirPods 符號，並展開狀態彈出式視窗">
</p>

彈出式視窗中的藍牙列會顯示即時狀態：已連接裝置的名稱，以及 AirPods 的左耳、右耳和充電盒電量。藍牙面板會列出已配對裝置及其連接狀態；它預設為關閉，需在**設定 › 狀態面板**中啟用，並在首次使用時要求藍牙權限。**設定 › 藍牙**也會控制是否讀取電量，並將藍牙圖示從 100% 縮放到 180%。

## Dock 圖示

同一個即時圖示也可以改放在 Dock，而不是選單列，或兩處同時顯示：

<p align="center">
  <img src="screenshots/status-trio-dock-dark-1440x810.jpg" width="880" alt="Dock 中的 Status Trio 即時圖示（深色外觀）">
  <br>
  <sub>Dock 圖示（深色外觀）</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-1440x810.jpg" width="880" alt="Dock 中的 Status Trio 即時圖示（淺色外觀）">
  <br>
  <sub>Dock 圖示（淺色外觀）</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-bt-1440x810.jpg" width="880" alt="Dock 中的 Status Trio 與藍牙面板（淺色外觀）">
  <br>
  <sub>藍牙面板預覽</sub>
</p>

Dock 圖示繪製的是與選單列相同的組合圖示，因此開啟藍牙音訊取代功能後，裝置符號同樣會佔據那裡的中間位置。它的背景可以跟隨系統圖示樣式，或固定為特定深淺：

<p align="center">
  <img src="screenshots/status-trio-dock-icons.png" width="880" alt="Status Trio Dock 圖示的深色、淺色與透明背景，分兩列呈現：Wi-Fi 狀態，以及藍牙音訊以藍色音量圓點取代 Wi-Fi 圖示">
</p>

## 圖示狀態

組合圖示能顯示的每一個狀態，全由應用程式自己的渲染器繪製 —— 頂部是電池指示，中間是 Wi-Fi（開啟該選項時，也可能是取代它的藍牙音訊裝置），底部是音量圓點或圓弧，並在藍牙裝置播放時轉為藍色：

<p align="center">
  <img src="screenshots/status-trio-icon-states.png" width="880" alt="Status Trio 圖示狀態：頂部為充電中、已連接電源、電量百分比、低電量與低耗電模式；中間為 Wi-Fi 訊號、個人熱點、臨時連線、共享與有線狀態；其下為藍牙音訊取代 Wi-Fi 圖示、網路異常時保留 Wi-Fi，以及藍色音量圓點與圓弧；底部為各級音量的圓點與圓弧樣式">
</p>

同一批狀態在深色選單列下的呈現：

<p align="center">
  <img src="screenshots/status-trio-icon-states-dark.png" width="880" alt="相同的 Status Trio 圖示狀態在深色外觀下：深色底塊上的白色符號、綠色充電、紅色低電量與黃色低耗電模式強調色，以及應用程式在深色選單列上為藍牙音訊使用的更亮藍色">
</p>

## 系統需求

- 執行應用程式需要 macOS 15 或以上版本
- 建置則需要搭配 macOS 26 SDK 的 Swift 6 工具鏈（Xcode 26 或以上版本）。使用較舊的 SDK
  建置會悄悄產生 Tahoe 之前的彈出式視窗外觀，因此當 SDK 低於 26 時，
  `scripts/build-app.sh` 會直接失敗。

## 從原始碼執行

```bash
git clone https://github.com/lingyired/status-trio.git
cd status-trio
swift run StatusTrio
```

## 建置本機應用程式

建置 ad-hoc 簽名的應用程式套件並啟動：

```bash
bash scripts/build-app.sh release
```

套件會建立在 `dist/StatusTrio.app`。若要只建置、不結束或啟動現有執行個體，請執行：

```bash
bash scripts/build-app.sh release no-open
```

ad-hoc 簽名的套件適合本機個人使用。如果套件連同隔離標記一起轉移，Gatekeeper 可能會拒絕它。

## 安裝 GitHub Release

從 [GitHub Releases 頁面](https://github.com/lingyired/status-trio/releases)下載最新的 `StatusTrio-*.dmg`，打開後將 `Status Trio.app` 拷貝到 `/Applications`。

目前的公開發行版本使用 ad-hoc 簽名，但未經 Apple 公證。macOS 可能在首次啟動時顯示以下警告：

> Apple 無法驗證「Status Trio」是否含有可能危害你的 Mac 或危及你的隱私的惡意軟體。

這是因為缺少 Developer ID 簽名與 Apple 公證而觸發的 Gatekeeper 警告，本身並不代表應用程式含有惡意軟體。只有在 DMG 是從官方 GitHub Releases 頁面下載，且其公布的 SHA-256 校驗值相符時，才應略過這項警告。

將應用程式拷貝到 `/Applications` 後，移除隔離屬性並開啟它：

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
open "/Applications/Status Trio.app"
```

或者，也可以先嘗試開啟應用程式一次，然後前往 **系統設定 → 隱私權與安全性**，選擇 **仍要打開**。

請勿全域停用 Gatekeeper。後續的 Sparkle 更新會以應用程式的 EdDSA 簽名金鑰驗證；`xattr` 指令通常只在第一次手動安裝時需要。

## 使用方式

- **按左鍵**點擊選單列圖示或 Dock 圖示，即可打開狀態彈出式視窗。
- **按右鍵**點擊任一個圖示，會顯示原生選單，其中包含版本與結束等操作。
- 在彈出式視窗中選擇某一列，即可打開對應頁面：Wi-Fi 詳細資訊與附近網路、已配對的藍牙裝置，以及電池詳細資訊。
- 打開**設定**可選擇圖示顯示的位置（選單列、Dock 或兩處），並變更其尺寸、顏色、外環線條粗細、面板區塊與其順序、捲動調節音量行為、語言、更新檢查，以及開機時啟動。
- 隨時可以從 **設定 › 應用程式圖示 › 打開指引** 重新開啟 **認識你的圖示** 導覽。
- 需要時請依提示允許顯示目前的 Wi-Fi 網路名稱；macOS 會為這項選用細節要求定位權限。

## 已知限制

有兩條界線，是 macOS 與本專案各自刻意劃下的。兩者的詳細說明見[已知限制](docs/known-limitations.md)。

- **切換網路在系統設定裡完成。** 在彈出式視窗中選擇網路會打開 Wi-Fi 面板；Status Trio 從不讀取也不儲存 Wi-Fi 密碼——macOS 沒有用已儲存密碼連線的公開 API，而其他做法最後都會讓 app 持有你的密碼。
- **「立即完全充電」留在 macOS 裡。** 當最佳化電池充電或充電上限暫停充電時，彈出式視窗會如實顯示暫停狀態，並連結到電池面板；沒有公開 API 能讓應用程式越過上限恢復充電，Status Trio 也不會為此寫入 SMC 或附帶特權輔助程式。

## 支援的語言

Status Trio 預設跟隨 macOS 的偏好語言，內建 English、简体中文、繁體中文、日本語、한국어、Español、Français、Deutsch、Italiano、Português (Brasil)、Русский 和 العربية。

## 隱私權

Status Trio 透過 macOS 的公開框架讀取狀態。它不使用 App Sandbox，也不需要網路權限，且不包含遙測或分析。不會讀取也不儲存 Wi-Fi 密碼，也不會要求鑰匙圈存取。定位權限為選用，僅在你選擇顯示目前的 Wi-Fi 網路名稱或打開 Wi-Fi 詳細資訊時要求。藍牙權限僅在打開藍牙詳細資訊時要求，用途是顯示已配對裝置的連接狀態。

## 開發

執行測試套件：

```bash
swift test
```

透過輔助指令碼執行指定範圍的 XCTest 篩選：

```bash
bash scripts/test.sh BatteryMonitorTests
```

若要在主要安裝之外另外建置 worktree 應用程式：

```bash
bash scripts/build-worktree.sh release
```

輔助指令碼會依據目前分支產生開發版套件識別碼與顯示名稱。這兩個值都可以覆寫：

```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

單一執行個體鎖定會以套件識別碼區分，因此識別碼不同的版本可以同時執行。

## 技術基準

- Swift 6
- SwiftUI + AppKit
- macOS 15+
- `LSUIElement` 選單列輔助應用程式，在顯示 Dock 圖示時切換為一般啟用策略
- 使用 Sparkle 檢查更新

## 文件

- [已知限制](docs/known-limitations.md)
- [自動化 GitHub Actions 發行](docs/github-actions-release.md)
- [Status Trio 設計規格](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [選單列圖示 SVG](status-menubar.svg)
- [資料驅動圖示示範](status-menubar-demo.html)

## 授權條款

Copyright 2026 lingyired.

依 Apache License, Version 2.0 授權。請參閱 [LICENSE](LICENSE) 與 [NOTICE](NOTICE)。

## 作者

由 [lingyired](https://github.com/lingyired) 建立並維護。<br>
網站：[https://statustrio.lingai.net/](https://statustrio.lingai.net/)

## Star History

<a href="https://www.star-history.com/?repos=lingyired%2Fstatus-trio&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
 </picture>
</a>
