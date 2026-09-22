# Version %VERSION% (Build %BUILD%)

## Native glass look on macOS 26
- The popover now uses macOS 26's Liquid Glass material and blends in with the system menus; settings such as Reduce Transparency still apply.
- macOS 15 through 25 keep the look they already have, and the minimum system requirement is unchanged — no one needs to update macOS to keep using Status Trio.

## Bluetooth works better
- The status panel now lists your paired devices right away: tap one to connect, tap it again to disconnect; disconnecting a keyboard or mouse asks you to confirm in the row first.
- Drag devices in Settings to reorder them; connected devices always come first.
- Bluetooth battery levels now show by default, with no switch to turn on.

## Wi-Fi switching stays in the system
- The app no longer joins networks for you: tapping a network opens the system's Wi-Fi settings, where you do the switching.
- Status Trio no longer reads or stores Wi-Fi passwords.
- A password entry saved by an earlier version may still be in your keychain, but it is no longer used.
- Seeing your networks, the signal details and the Wi-Fi switch all work as before.

## Uses less power
- Far less background work: Bluetooth no longer polls devices on a timer, Wi-Fi scanning stops when you leave the page, and the fallback refresh slowed from every 5 seconds to every 15.
- Updates still arrive the moment the system reports a change, and your refresh interval setting is unchanged.

## Fixes and improvements
- Clicking the menu bar icon now opens the panel while another app is full screen.
- Power readings in the battery details are more accurate: "System power (estimate)" on power, "Battery discharge (estimate)" on battery.
- A location permission refused for Wi-Fi can be requested again instead of staying stuck at network names unavailable.
- With the system's Reduce Motion turned on, the settings interface no longer plays transition animations.

## Thanks
- Thanks to @hhh2210 for their code contributions to this release.
