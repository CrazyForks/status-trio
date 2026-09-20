# Version %VERSION% (Build %BUILD%)

## Native Liquid Glass on macOS 26 and later
- The popover now uses the system's own Liquid Glass material instead of the frosted look carried over from earlier macOS releases, so it matches the menus and panels around it.
- This is the system appearance, not an app-specific style: it follows your system settings, including Reduce Transparency and the system glass tint.
- macOS 15 to 25 keep the appearance they already had; the deployment target is unchanged, so no user has to update macOS to keep using Status Trio.

## Panel opens over full-screen apps
- Clicking the menu bar icon now opens the status panel while another app is in full screen. The panel used to open behind that app, so the click looked like it did nothing.

## Cheaper background refresh
- The fallback refresh — the timer that catches a change the system did not push to the app — now runs every 15 seconds by default instead of every 5, and macOS may slide that timer so it fires alongside other work. The icon still updates the moment the system reports a change.
- The battery is checked on every fallback tick. Wi-Fi and volume are checked less often while the Status Panel and the Settings window are both closed, and go back to your Status refresh interval as soon as either one is on screen.
- The Status refresh interval slider still goes down to 5 seconds for anyone who wants the old cadence.
- The volume row no longer redraws the Status Panel when the volume reading has not changed.

## Bluetooth stops working in the background
- The Bluetooth panel used to read the paired-device list every 15 seconds for as long as the app was running, even after the panel was closed. It now refreshes when a device connects or disconnects, and falls back to a slow check only while a Bluetooth view is on screen.
- Paired devices and battery levels now come from one system report instead of two, which halves the work each refresh does.
- The summary row and the device page are unchanged: the same names, the same levels, and the same permission behaviour — the app still asks for Bluetooth only when you open a Bluetooth view.
