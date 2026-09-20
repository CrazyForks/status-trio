<p align="center">
  <img src="screenshots/status-trio-dock-state-strip.png" width="1000" alt="Eight Status Trio Dock icon states alternating dark and light backgrounds, including Wi-Fi, Bluetooth audio, battery, dots, and arc states">
</p>

<p align="center">
  <img src="Support/AppIcon.svg" width="112" alt="Status Trio app icon">
</p>

<h1 align="center">Status Trio</h1>

<p align="center">
  <a href="https://trendshift.io/repositories/234371?utm_source=trendshift-badge&utm_medium=badge&utm_campaign=badge-trendshift-234371" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/234371/daily?language=Swift" alt="lingyired/status-trio | Trendshift" width="250" height="55"/></a>
</p>

<p align="center"><strong>Three system signals. One native macOS status icon — in your menu bar or the Dock.</strong></p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-Universal%20%C2%B7%20macOS%2015%2B-000000?logo=apple&logoColor=white&style=for-the-badge" alt="Download for macOS — universal build, macOS 15 or later"></a>
</p>

<p align="center">
  Want to see it in action first? Open <a href="https://statustrio.lingai.net/">statustrio.lingai.net</a> to simulate every icon state in your browser.
</p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/github/v/release/lingyired/status-trio?label=release&color=blue" alt="Latest release"></a>
  <a href="https://github.com/lingyired/status-trio/actions/workflows/release.yml"><img src="https://github.com/lingyired/status-trio/actions/workflows/release.yml/badge.svg" alt="Build and Release macOS workflow status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/lingyired/status-trio?label=license" alt="License: Apache-2.0"></a>
  <a href="https://deepwiki.com/lingyired/status-trio"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B%20supported-blue?logo=apple&logoColor=white" alt="macOS 15 or later supported">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="Universal binary for Apple Silicon and Intel">
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="screenshots/menu-bar-wifi.jpg" width="1000" alt="Status Trio menu bar icon showing the Wi-Fi glyph while connected to Wi-Fi, with its status popover open">
</p>

Status Trio is a native macOS status app that combines Wi-Fi, battery, and volume into one compact, configurable icon, shown in the menu bar, in the Dock, or in both. Its popover goes deeper than the icon: a Wi-Fi panel for joining networks and reading link details, a Bluetooth panel for paired devices, a Battery Details page, and the audio devices that are playing. It is inspired by the iPhone Duo's combined status bar icon for Wi-Fi, Battery, and Cellular Data, adapted for Mac with Volume instead of Cellular Data.

> Status Trio is an independent project and is not affiliated with Apple.

## Highlights

- **One combined status icon** — battery, network, and volume in a single icon, in the menu bar, the Dock, or both.
- **Bluetooth audio** — while a Bluetooth device is playing, the device's own symbol can replace the network glyph and the volume dots or arc can turn blue, so the active output is obvious at a glance.
- **Detailed battery status** — percentage, a charging bolt or a plug while connected without charging, an optional percentage while connected, estimated time to full, status colors, a configurable critical threshold, and a Battery Settings shortcut.
- **Battery Details page** — adapter rating, time remaining, net battery power estimates, voltage, current, cycle count, and Low Power Mode, sampled on demand.
- **Wi-Fi awareness** — the network name as the popover title, its band and signal strength, and signal strength plus common connection states in the icon.
- **Wi-Fi panel** — scan nearby networks, join one with a password stored in the Keychain, toggle Wi-Fi, and read full link details: BSSID, channel, width, RSSI, noise, SNR, PHY, rate, security, IPv4/IPv6, router, and DNS.
- **Bluetooth panel** — paired devices and their connection state, with AirPods battery levels. It is off by default; enable it under Settings › Status Panel.
- **Volume at a glance** — output level, mute state, and the current output device with the symbol macOS uses for it.
- **Scroll to adjust volume** — choose whether scrolling anywhere in the panel or only on the volume control changes the volume, and whether scrolling up always raises it regardless of the system's natural scrolling setting.
- **Configurable rendering** — an icon size from 16–36 pt (24 pt by default), a network and Bluetooth symbol scale from 100%–180%, volume dots or a continuous arc, and a Light, Regular, or Bold ring stroke width.
- **Connection icon choices** — optionally use the standard Wi-Fi signal icon for Ethernet, Personal Hotspot, temporary connections, or Internet Sharing.
- **Customizable Status Panel** — choose which sections the popover shows (Battery, Wi-Fi, Bluetooth, Volume) and drag them into order.
- **Menu bar or Dock** — choose where the live icon lives: the menu bar, the Dock, or both, with a Dock icon that follows the system icon style or holds a pinned dark or light background.
- **macOS-native controls** — left-click for a status popover and right-click for the standard menu, from either the menu bar icon or the Dock icon.
- **Meet your icon** — a first-launch guide that explains each part of the icon and shows a gallery of common state combinations.
- **Efficient updates** — event-driven monitoring with a low-frequency polling fallback.
- **Twelve languages** — follow the system language or choose one manually; changes apply immediately.
- **Launch at login** — optional startup with guidance when macOS requires approval.
- **Automatic updates** — Sparkle checks the signed appcast and verifies each update with the app's EdDSA key.

## Bluetooth audio

While audio plays over Bluetooth, two switches under **Settings › Bluetooth** let the middle glyph become that device's own symbol — AirPods, headphones, speakers, and other devices supply their own — and let the volume dots or arc turn blue. Both are off by default. **Let network errors take priority**, on by default, keeps the network icon while the connection itself is in trouble:

<p align="center">
  <img src="screenshots/menu-bar-airpods.jpg" width="1000" alt="Status Trio menu bar icon showing the AirPods glyph while AirPods are connected, with its status popover open">
</p>

The popover's Bluetooth row reports live state: the names of connected devices and, for AirPods, left, right, and case battery. The Bluetooth panel lists paired devices and their connection state; it is off by default, is enabled under **Settings › Status Panel**, and asks for Bluetooth permission on first use. **Settings › Bluetooth** also controls whether the battery levels are read and scales the Bluetooth icon from 100% to 180%.

## Dock icon

The same live icon can live in the Dock instead of the menu bar, or in both places at once:

<p align="center">
  <img src="screenshots/status-trio-dock-dark-1440x810.jpg" width="880" alt="Status Trio live icon in the Dock with dark appearance">
  <br>
  <sub>Dock icon in dark appearance</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-1440x810.jpg" width="880" alt="Status Trio live icon in the Dock with light appearance">
  <br>
  <sub>Dock icon in light appearance</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-bt-1440x810.jpg" width="880" alt="Status Trio in the Dock with the Bluetooth panel shown, light appearance">
  <br>
  <sub>Bluetooth panel preview</sub>
</p>

The Dock icon draws the same combined icon as the menu bar, so with Bluetooth audio replacement enabled the device glyph takes over the middle there too. Its background can follow the system icon style or be pinned to a fixed shade:

<p align="center">
  <img src="screenshots/status-trio-dock-icons.png" width="880" alt="Status Trio Dock icon in dark, light, and clear backgrounds, in two rows: the Wi-Fi state and Bluetooth audio replacing the Wi-Fi icon with blue volume dots">
</p>

## Icon states

Every state the combined icon can show, drawn by the app's own renderer — battery indicators on top, Wi-Fi (or the Bluetooth audio device that can replace it, when that option is on) in the middle, and volume dots or the arc at the bottom, turning blue while a Bluetooth device is playing:

<p align="center">
  <img src="screenshots/status-trio-icon-states.png" width="880" alt="Status Trio icon states: charging, plugged in, percentage, low battery, and Low Power Mode at the top; Wi-Fi signal, hotspot, temporary, shared, and wired states in the middle; Bluetooth audio replacing the Wi-Fi icon, keeping Wi-Fi during a network error, and blue volume dots and arc below that; volume dots and arc styles for every level at the bottom">
</p>

The same states rendered for a dark menu bar:

<p align="center">
  <img src="screenshots/status-trio-icon-states-dark.png" width="880" alt="The same Status Trio icon states in dark appearance: white glyphs on dark chips, green charging, red low battery and yellow Low Power Mode accents, and the brighter blue the app uses for Bluetooth audio on a dark menu bar">
</p>

## Requirements

- macOS 15 or later to run the app
- Swift 6 toolchain with the macOS 26 SDK (Xcode 26 or later) to build it. Building against an
  older SDK silently produces the pre-Tahoe popover appearance, so `scripts/build-app.sh` fails
  when the SDK is older than 26.

## Run from source

```bash
git clone https://github.com/lingyired/status-trio.git
cd status-trio
swift run StatusTrio
```

## Build a local app

Build an ad-hoc-signed app bundle and launch it:

```bash
bash scripts/build-app.sh release
```

The bundle is created at `dist/StatusTrio.app`. To build without quitting or launching an existing instance, run:

```bash
bash scripts/build-app.sh release no-open
```

The ad-hoc-signed bundle is intended for local personal use. Gatekeeper may reject it if the bundle is transferred with quarantine metadata.

## Install a GitHub Release

Download the latest `StatusTrio-*.dmg` from the [GitHub Releases page](https://github.com/lingyired/status-trio/releases), open it, and copy `Status Trio.app` into `/Applications`.

The current public build is ad-hoc signed but is not notarized by Apple. macOS may show this warning on first launch:

> Apple cannot verify “Status Trio” is free of malware that may harm your Mac or compromise your privacy.

This is a Gatekeeper warning caused by the missing Developer ID signature and Apple notarization. It does not by itself mean the app contains malware. Only bypass the warning when the DMG was downloaded from the official GitHub Releases page and its published SHA-256 checksum matches.

After copying the app into `/Applications`, remove the quarantine attribute and open it:

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
open "/Applications/Status Trio.app"
```

Alternatively, try to open the app once, then go to **System Settings → Privacy & Security** and choose **Open Anyway**.

Do not disable Gatekeeper globally. Subsequent Sparkle updates are authenticated with the app's EdDSA signing key; the `xattr` command is normally needed only for the first manual installation.

## Usage

- **Left-click** the menu bar icon or the Dock icon to open the status popover.
- **Right-click** either icon for the native menu, including version and quit actions.
- Select a row in the popover to open its page: Wi-Fi details with nearby networks, paired Bluetooth devices, and Battery Details.
- Open **Settings** — App Icon, Battery, Network, Bluetooth, Audio, Status Panel, General, and About — to choose where the icon is shown (menu bar, Dock, or both) and to change the icon size, symbol scales, ring stroke width, status colors, panel sections and their order, scroll-to-adjust behavior, language, update checks, and launch-at-login behavior.
- Reopen the **Meet your icon** guide any time from **Settings › App Icon › Open Guide**.
- Enable the current Wi-Fi network name when prompted; macOS requests location access for this optional detail.

## Languages

Status Trio follows the macOS preferred language by default and includes English, Simplified Chinese, Traditional Chinese, Japanese, Korean, Spanish, French, German, Italian, Brazilian Portuguese, Russian, and Arabic.

## Privacy

Status Trio reads status through public macOS frameworks. It does not use App Sandbox or require a network entitlement, and it does not include telemetry or analytics. Location access is optional and requested only when you choose to display the current Wi-Fi network name or open Wi-Fi details. Bluetooth access is requested only when you open Bluetooth details, and it exists to show paired-device connection status.

## Development

Run the test suite:

```bash
swift test
```

Run a focused XCTest filter through the helper:

```bash
bash scripts/test.sh BatteryMonitorTests
```

To build a worktree app alongside the main installation:

```bash
bash scripts/build-worktree.sh release
```

The helper derives a development bundle identifier and display name from the current branch. Both values can be overridden:

```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

The single-instance lock is scoped by bundle identifier, so differently identified builds can run at the same time.

## Technical baseline

- Swift 6
- SwiftUI + AppKit
- macOS 15+
- `LSUIElement` menu bar accessory that switches to a regular activation policy while the Dock icon is shown
- Sparkle for update checks

## Documentation

- [Automated GitHub Actions releases](docs/github-actions-release.md)
- [Status Trio design specification](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [Menu bar icon SVG](status-menubar.svg)
- [Data-driven icon demo](status-menubar-demo.html)

## License

Copyright 2026 lingyired.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Author

Created and maintained by [lingyired](https://github.com/lingyired).<br>
Website: [https://statustrio.lingai.net/](https://statustrio.lingai.net/)

## Star History

<a href="https://www.star-history.com/?repos=lingyired%2Fstatus-trio&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
 </picture>
</a>
