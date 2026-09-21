<p align="center">
  <img src="screenshots/status-trio-dock-state-strip-symmetric.png" width="1000" alt="어두운 배경과 밝은 배경이 대칭으로 배치된 여덟 가지 Status Trio Dock 아이콘 상태. Wi-Fi, Bluetooth 오디오, 배터리, 점, 호 상태를 포함합니다">
</p>

<p align="center">
  <img src="Support/AppIcon.png" width="112" alt="Status Trio 앱 아이콘">
</p>

<h1 align="center">Status Trio</h1>

<p align="center">
  <a href="https://trendshift.io/repositories/234371?utm_source=trendshift-badge&utm_medium=badge&utm_campaign=badge-trendshift-234371" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/234371/daily?language=Swift" alt="lingyired/status-trio | Trendshift" width="250" height="55"/></a>
</p>

<p align="center"><strong>세 가지 시스템 신호. 하나의 네이티브 macOS 상태 아이콘 — 메뉴 막대 또는 Dock에서.</strong></p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-Universal%20%C2%B7%20macOS%2015%2B-000000?logo=apple&logoColor=white&style=for-the-badge" alt="macOS용 다운로드 — 유니버설 빌드, macOS 15 이상"></a>
</p>

<p align="center">
  먼저 실제 동작을 보고 싶으신가요? <a href="https://statustrio.lingai.net/">statustrio.lingai.net</a>을 열면 브라우저에서 모든 아이콘 상태를 시뮬레이션할 수 있습니다.
</p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/github/v/release/lingyired/status-trio?label=release&color=blue" alt="최신 릴리스"></a>
  <a href="https://github.com/lingyired/status-trio/actions/workflows/release.yml"><img src="https://github.com/lingyired/status-trio/actions/workflows/release.yml/badge.svg" alt="Build and Release macOS 워크플로 상태"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/lingyired/status-trio?label=license" alt="라이선스: Apache-2.0"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B%20supported-blue?logo=apple&logoColor=white" alt="macOS 15 이상 지원">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="Apple Silicon 및 Intel용 유니버설 바이너리">
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <strong>한국어</strong> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português (Brasil)</a> ·
  <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="screenshots/menu-bar-wifi.jpg" width="1000" alt="Wi-Fi에 연결된 상태에서 Wi-Fi 기호를 표시하는 Status Trio 메뉴 막대 아이콘과 열려 있는 상태 팝오버">
</p>

Status Trio는 Wi-Fi, 배터리, 볼륨을 하나의 간결하고 설정 가능한 아이콘으로 결합해 메뉴 막대, Dock 또는 두 곳 모두에 표시하는 네이티브 macOS 상태 앱입니다. 팝오버는 아이콘보다 더 깊이 들어갑니다. 주변 네트워크와 링크 세부 정보를 보여 주는 Wi-Fi 패널, 페어링된 기기를 보여 주는 Bluetooth 패널, 배터리 세부 정보 페이지, 그리고 재생 중인 오디오 기기를 제공합니다. iPhone Duo가 Wi-Fi, 배터리, 셀룰러 데이터를 하나의 상태 막대 아이콘으로 결합한 데서 영감을 받았으며, Mac에서는 셀룰러 데이터 대신 볼륨을 사용하도록 각색했습니다.

> Status Trio는 독립적인 프로젝트이며 Apple과 제휴 관계가 없습니다.

## 주요 기능

- **하나의 아이콘, 세 가지 신호** — 배터리, Wi-Fi, 볼륨이 메뉴 막대, Dock 또는 두 곳 모두에서 하나의 아이콘을 공유하며, 재생 중인 Bluetooth 기기는 자신의 기호로 가운데 자리를 차지할 수 있습니다.
- **Bluetooth** — 재생 중에는 볼륨 표시기가 파란색으로 바뀝니다. 패널에는 연결된 기기와 페어링된 기기가 AirPods 배터리와 함께 표시되며, 사용자가 켜기 전까지는 꺼져 있습니다.
- **배터리** — 잔량 백분율, 충전 중 또는 전원 연결 상태, 완전 충전까지 남은 시간, 잔량이 부족할 때의 색상을 보여 줍니다. 해당 행을 열면 어댑터 정격 출력, 전압, 전류, 사이클 수, 저전력 모드를 확인할 수 있습니다.
- **Wi-Fi** — 현재 연결된 네트워크와 신호 세기를 보여 줍니다. 열면 주변 네트워크를 보고, 링크 세부 정보를 확인하거나 Wi-Fi를 끌 수 있습니다. 네트워크 간 전환은 시스템 설정의 Wi-Fi 패널에서 이루어집니다.
- **볼륨** — 음량, 음소거, 출력 장치를 점 또는 호로 그립니다. 패널 전체 또는 컨트롤만 스크롤할 수 있고, 볼륨을 높이는 스크롤 방향을 선택할 수 있습니다.
- **원하는 대로 설정** — 아이콘 크기, 기호 배율, 외부 링 두께, 상태 색상, 그리고 팝오버에 표시할 섹션과 그 순서를 직접 정할 수 있습니다.
- **메뉴 막대, Dock 또는 둘 다** — Dock 아이콘은 시스템 스타일을 따르거나 어두운 색 또는 밝은 색으로 고정할 수 있습니다.
- **macOS 네이티브** — 왼쪽 클릭으로 팝오버가 열리고 오른쪽 클릭으로 메뉴가 열리며, 첫 실행 시 아이콘 알아보기 가이드가 아이콘의 각 부분을 설명합니다. 원한다면 Ethernet, 핫스팟 또는 인터넷 공유에서도 Wi-Fi 기호를 유지할 수 있습니다.
- **항상 최신 상태 유지** — 상태는 시스템 이벤트에서 가져오고 느린 폴링을 대체 수단으로 사용하며, Sparkle은 서명된 피드를 통해 앱을 업데이트합니다.
- **함께 제공되는 기능** — 열두 개 언어와 선택적 로그인 시 실행 기능입니다.

## Bluetooth 오디오

Bluetooth로 오디오를 재생하는 동안 **설정 › Bluetooth** 아래의 두 스위치로 가운데 기호를 해당 기기 고유의 심볼로 바꿀 수 있고 — AirPods, 헤드폰, 스피커 및 기타 기기는 각자의 심볼을 제공합니다 — 볼륨 점 또는 호를 파란색으로 표시할 수 있습니다. 둘 다 기본적으로 꺼져 있습니다. 기본적으로 켜져 있는 **네트워크 오류 우선**은 연결 자체에 문제가 있는 동안 네트워크 아이콘을 유지합니다:

<p align="center">
  <img src="screenshots/menu-bar-airpods.jpg" width="1000" alt="AirPods가 연결된 상태에서 AirPods 기호를 표시하는 Status Trio 메뉴 막대 아이콘과 열려 있는 상태 팝오버">
</p>

팝오버의 Bluetooth 행은 실시간 상태를 알려 줍니다. 연결된 기기의 이름과 AirPods의 경우 왼쪽, 오른쪽, 케이스 배터리입니다. Bluetooth 패널은 페어링된 기기와 그 연결 상태를 나열합니다. 기본적으로 꺼져 있고 **설정 › 상태 패널**에서 활성화하며, 처음 사용할 때 Bluetooth 권한을 요청합니다. **설정 › Bluetooth**에서는 배터리 잔량을 읽을지 여부를 제어하고 Bluetooth 아이콘을 100%에서 180%까지 조절합니다.

## Dock 아이콘

동일한 실시간 아이콘을 메뉴 막대 대신 Dock에 표시하거나 두 곳에 동시에 표시할 수 있습니다:

<p align="center">
  <img src="screenshots/status-trio-dock-dark-1440x810.jpg" width="880" alt="어두운 색 모양의 Dock에 표시된 Status Trio 실시간 아이콘">
  <br>
  <sub>어두운 색 모양의 Dock 아이콘</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-1440x810.jpg" width="880" alt="밝은 색 모양의 Dock에 표시된 Status Trio 실시간 아이콘">
  <br>
  <sub>밝은 색 모양의 Dock 아이콘</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-bt-1440x810.jpg" width="880" alt="Bluetooth 패널이 표시된 밝은 색 모양의 Dock에 있는 Status Trio">
  <br>
  <sub>Bluetooth 패널 미리보기</sub>
</p>

Dock 아이콘은 메뉴 막대와 동일한 결합 아이콘을 그리므로, Bluetooth 오디오 교체를 켜면 그곳에서도 기기 기호가 가운데를 차지합니다. 배경은 시스템 아이콘 스타일을 따르거나 고정된 명암으로 지정할 수 있습니다:

<p align="center">
  <img src="screenshots/status-trio-dock-icons.png" width="880" alt="어두운 색, 밝은 색, 투명 배경의 Status Trio Dock 아이콘을 두 줄로 정리한 그림: Wi-Fi 상태와 Bluetooth 오디오가 Wi-Fi 아이콘을 대체하며 파란색 볼륨 점을 표시하는 상태">
</p>

## 아이콘 상태

결합 아이콘이 표시할 수 있는 모든 상태를 앱 자체 렌더러로 그린 것입니다. 위쪽에는 배터리 표시기, 가운데에는 Wi-Fi(해당 옵션이 켜져 있으면 이를 대체할 수 있는 Bluetooth 오디오 기기), 아래쪽에는 볼륨 점 또는 호가 있으며, Bluetooth 기기가 재생 중일 때는 파란색으로 바뀝니다:

<p align="center">
  <img src="screenshots/status-trio-icon-states.png" width="880" alt="Status Trio 아이콘 상태: 위쪽은 충전 중, 전원 연결됨, 잔량 백분율, 배터리 부족, 저전력 모드이고 가운데는 Wi-Fi 신호, 핫스팟, 임시 연결, 공유 중, 유선 상태이며 그 아래는 Wi-Fi 아이콘을 대체한 Bluetooth 오디오, 네트워크 오류 중 Wi-Fi 유지, 파란색 볼륨 점과 호이고 맨 아래는 모든 단계의 볼륨 점 및 호 스타일">
</p>

어두운 메뉴 막대용으로 렌더링한 동일한 상태:

<p align="center">
  <img src="screenshots/status-trio-icon-states-dark.png" width="880" alt="어두운 색 모양의 동일한 Status Trio 아이콘 상태: 어두운 칩 위의 흰색 기호, 초록색 충전, 빨간색 배터리 부족과 노란색 저전력 모드 강조, 그리고 어두운 메뉴 막대에서 앱이 Bluetooth 오디오에 사용하는 더 밝은 파란색">
</p>

## 요구 사항

- 앱을 실행하려면 macOS 15 이상이 필요합니다.
- 빌드하려면 macOS 26 SDK(Xcode 26 이상)가 포함된 Swift 6 툴체인이 필요합니다. 이전 SDK로 빌드하면
  아무 알림 없이 Tahoe 이전 팝오버 모양이 만들어지므로, SDK가 26보다 이전이면 `scripts/build-app.sh`가 실패합니다.

## 소스에서 실행

```bash
git clone https://github.com/lingyired/status-trio.git
cd status-trio
swift run StatusTrio
```

## 로컬 앱 빌드

Ad-hoc 서명된 앱 번들을 빌드하고 실행합니다:

```bash
bash scripts/build-app.sh release
```

번들은 `dist/StatusTrio.app`에 생성됩니다. 실행 중인 인스턴스를 종료하거나 새로 실행하지 않고 빌드하려면 다음을 실행하십시오:

```bash
bash scripts/build-app.sh release no-open
```

Ad-hoc 서명된 번들은 로컬 개인 사용을 위한 것입니다. 번들이 격리 메타데이터와 함께 전송되면 Gatekeeper가 이를 거부할 수 있습니다.

## GitHub 릴리스 설치

[GitHub 릴리스 페이지](https://github.com/lingyired/status-trio/releases)에서 최신 `StatusTrio-*.dmg`를 내려받아 열고 `Status Trio.app`을 `/Applications`에 복사합니다.

현재 공개 빌드는 ad-hoc 서명되어 있지만 Apple의 공증을 받지 않았습니다. macOS는 첫 실행 시 다음 경고를 표시할 수 있습니다:

> Apple은 “Status Trio”에 Mac을 손상시키거나 개인 정보를 침해할 수 있는 악성 코드가 없는지 확인할 수 없습니다.

이것은 Developer ID 서명과 Apple 공증이 없어서 발생하는 Gatekeeper 경고입니다. 그 자체로 앱에 악성 코드가 포함되어 있다는 뜻은 아닙니다. 공식 GitHub 릴리스 페이지에서 DMG를 내려받았고 공개된 SHA-256 체크섬이 일치할 때만 경고를 우회하십시오.

앱을 `/Applications`에 복사한 후 격리 속성을 제거하고 엽니다:

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
open "/Applications/Status Trio.app"
```

또는 앱을 한 번 열어 본 다음 **시스템 설정 → 개인정보 보호 및 보안**으로 이동해 **그래도 열기**를 선택하십시오.

Gatekeeper를 전역으로 비활성화하지 마십시오. 이후의 Sparkle 업데이트는 앱의 EdDSA 서명 키로 인증됩니다. `xattr` 명령은 보통 최초 수동 설치에만 필요합니다.

## 사용 방법

- 메뉴 막대 아이콘이나 Dock 아이콘을 **왼쪽 클릭**하면 상태 팝오버가 열립니다.
- 두 아이콘 중 하나를 **오른쪽 클릭**하면 버전과 종료 동작을 포함한 네이티브 메뉴가 열립니다.
- 팝오버에서 행을 선택하면 해당 페이지가 열립니다. 주변 네트워크가 있는 Wi-Fi 세부 정보, 페어링된 Bluetooth 기기, 배터리 세부 정보입니다.
- **설정**을 열어 아이콘을 표시할 위치(메뉴 막대, Dock 또는 둘 다)를 선택하고 크기, 색상, 외부 링 두께, 패널 섹션과 그 순서, 스크롤로 조절하는 동작, 언어, 업데이트 확인, 로그인 시 실행을 변경할 수 있습니다.
- **설정 › 앱 아이콘 › 가이드 열기**에서 언제든지 **아이콘 알아보기** 가이드를 다시 열 수 있습니다.
- 요청이 표시되면 현재 Wi-Fi 네트워크 이름 표시를 허용하십시오. macOS는 이 선택적 정보를 위해 위치 접근 권한을 요청합니다.

## 알려진 제한 사항

macOS와 이 프로젝트가 의도적으로 그은 두 가지 경계가 있습니다. 둘 다 [알려진 제한 사항](docs/known-limitations.md)에 설명되어 있습니다.

- **네트워크 전환은 시스템 설정에서 이루어집니다.** 팝오버에서 네트워크를 선택하면 Wi-Fi 패널이 열립니다. Status Trio는 Wi-Fi 암호를 읽거나 저장하지 않습니다. macOS가 저장된 암호로 연결할 수 있는 공개 API를 제공하지 않으며, 다른 모든 방법은 결국 앱이 암호를 보관하게 되기 때문입니다.
- **“지금 완전히 충전”은 macOS에 남아 있습니다.** 최적화된 배터리 충전이나 충전 한도로 인해 충전이 일시 중지되면, 팝오버는 일시 중지된 상태를 그대로 표시하고 배터리 패널로 이동하는 링크를 제공합니다. 앱이 한도를 넘어 충전을 재개할 수 있는 공개 API는 없으며, Status Trio는 이를 위해 SMC에 쓰거나 권한 있는 helper를 함께 제공하지 않습니다.

## 언어

Status Trio는 기본적으로 macOS의 선호 언어를 따르며 English, 简体中文, 繁體中文, 日本語, 한국어, Español, Français, Deutsch, Italiano, Português (Brasil), Русский, العربية를 지원합니다.

## 개인정보 보호

Status Trio는 공개 macOS 프레임워크를 통해 상태를 읽습니다. App Sandbox를 사용하지 않고 네트워크 권한도 필요로 하지 않으며, 원격 측정이나 분석을 포함하지 않습니다. 위치 접근은 선택 사항이며 현재 Wi-Fi 네트워크 이름을 표시하거나 Wi-Fi 세부 정보를 열 때만 요청합니다. Bluetooth 접근은 Bluetooth 세부 정보를 열 때만 요청하며, 페어링된 기기의 연결 상태를 표시하기 위한 것입니다.

## 개발

테스트 스위트를 실행합니다:

```bash
swift test
```

헬퍼를 통해 특정 XCTest 필터를 실행합니다:

```bash
bash scripts/test.sh BatteryMonitorTests
```

기본 설치와 함께 워크트리 앱을 빌드하려면:

```bash
bash scripts/build-worktree.sh release
```

헬퍼는 현재 브랜치에서 개발용 번들 식별자와 표시 이름을 도출합니다. 두 값 모두 재정의할 수 있습니다:

```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

단일 인스턴스 잠금은 번들 식별자를 기준으로 적용되므로, 식별자가 다른 빌드는 동시에 실행할 수 있습니다.

## 기술 기준

- Swift 6
- SwiftUI + AppKit
- macOS 15+
- Dock 아이콘이 표시되는 동안 일반 활성화 정책으로 전환하는 `LSUIElement` 메뉴 막대 액세서리
- 업데이트 확인을 위한 Sparkle

## 문서

- [알려진 제한 사항](docs/known-limitations.md)
- [자동화된 GitHub Actions 릴리스](docs/github-actions-release.md)
- [Status Trio 디자인 명세](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [메뉴 막대 아이콘 SVG](status-menubar.svg)
- [데이터 기반 아이콘 데모](status-menubar-demo.html)

## 라이선스

Copyright 2026 lingyired.

Apache License, Version 2.0에 따라 라이선스가 부여됩니다. [LICENSE](LICENSE) 및 [NOTICE](NOTICE)를 참조하십시오.

## 작성자

[lingyired](https://github.com/lingyired)가 만들고 유지 관리합니다.<br>
웹사이트: [https://statustrio.lingai.net/](https://statustrio.lingai.net/)

## Star History

<a href="https://www.star-history.com/?repos=lingyired%2Fstatus-trio&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
 </picture>
</a>
