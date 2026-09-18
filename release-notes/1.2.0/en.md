# Version %VERSION% (Build %BUILD%)

## Highlights: Bluetooth audio
- The popover's Bluetooth row now reports live state: the names of connected devices, plus left/right/case battery for AirPods. Other devices show their name only.
- While audio plays over Bluetooth, the center network icon can switch to the matching device glyph (AirPods, headphones, speakers, and so on) and render in blue, with the volume dots or arc turning blue too, so the active output is obvious at a glance.
- New Settings > Bluetooth page: switches for replacing the network icon, using blue for Bluetooth volume, letting network errors take priority, and showing Bluetooth battery levels, plus a 100%-180% Bluetooth icon size.
- Fixed a device renamed in System Settings still showing its old name.
- Fixed Bluetooth battery levels staying at Unavailable after switching between the summary and the device page.

## Battery details
- Tapping the battery row in the popover opens a dedicated page with adapter rating, time remaining, Low Power Mode, voltage, current, sample time, and cycle count.
- New net battery power estimate: charging is labeled green as Charging (estimate), and discharging reads Discharging (estimate).
- These values are best-effort estimates, not total Mac power consumption. After a power-source change macOS can take up to a minute to report new values; that window shows Sampling instead of Unavailable.

## Wi-Fi summary
- When Wi-Fi is connected, the popover uses the network name (SSID) as its title and shows the current band and signal strength below it, for example 5 GHz / -52 dBm.
- Missing measurements are omitted rather than shown as 0; Ethernet, offline, and other non-Wi-Fi paths do not show them.

## Meet your icon
- A fresh installation opens the Meet your icon guide on first launch. Select the battery arc, the center network glyph, or the volume indicator to read what each one means; the volume explanation follows your current dots or arc setting.
- The guide includes a gallery of common state combinations: charging, low battery, Ethernet, no Internet and muted, hotspot with Low Power Mode, weak Wi-Fi at 25% volume, Wi-Fi off, Bluetooth headphones, AirPods, and Wi-Fi with blue volume.
- Updating to this version, restarting, and existing installations do not open it automatically. Reopen it any time from Settings, App Icon, Open Guide.

## Volume
- New Natural Scrolling switch: when on, scrolling up with a mouse or trackpad increases the volume regardless of the system's natural scrolling preference; when off, volume follows the system's scrolling direction.
- New Adjustment Area choice: scroll anywhere in the panel, or only on the volume control.
- If scrolling up still lowers the volume with this on, a scroll utility such as MOS, Scroll Reverser, or LinearMouse is reversing the events; add Status Trio to that app's exception or ignore list.

## Settings and appearance
- Volume style (dots or arc), icon placement, and ring stroke width are now visual card pickers: the selection is marked with a concentric ring and previews the result inline.
- New Ring Stroke Width setting: Light, Regular, or Bold, applied to the battery outer ring, the volume arc, and the volume dots for a sharper result on Retina displays.
- Choosing Menu Bar only now warns that the Dock icon disappears when the Settings window closes.
- The popover's audio controls and footer are more compact: the mute toggle moves into the header, duplicate speaker icons are removed, the output device name becomes a subtitle, and a More actions entry is added.
- Popover rows now share one icon size and spacing; the default menu bar icon is 24 pt and the Wi-Fi symbol scale defaults to 160%.

## Fixes
- Changing an icon option now redraws the menu bar and Dock icons immediately instead of one step later.
- The menu bar preview in Settings stays pinned to the top of the page instead of scrolling with the options.
- Clicking a known Wi-Fi network opens the system Wi-Fi settings directly.
- The Wi-Fi symbol is centered in the status icon (issue #30).

## Thanks
- Thanks to @ReffWu and @hhh2210 for their code contributions to this release.
