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

## Bluetooth no longer polls in the background
- The Bluetooth panel used to read the paired-device list every 15 seconds for as long as the app was running, even after the panel was closed. It now refreshes when a device connects or disconnects, and falls back to a slow check only while a Bluetooth view is on screen.
- Paired devices and battery levels now come from one system report instead of two, which halves the work each refresh does.
- The summary row and the device page are unchanged: the same names, the same levels, and the same permission behaviour — the app still asks for Bluetooth only when you open a Bluetooth view.

## Wi-Fi scanning stops when you stop looking
- The Wi-Fi page used to sweep every channel about every five seconds for as long as it was open, even after you went back to the summary. It now scans when you open the page, when you tap refresh, and when you switch the radio, and keeps the last result in between.
- Leaving the Wi-Fi page stops its scan loop instead of leaving it running in the background.
- On Macs without a Wi-Fi interface — a Mac mini or Mac Studio on Ethernet, for example — the app no longer rebuilds its Wi-Fi monitoring every 30 seconds; it now tries a few times and then waits for a wake or a network change.
- Nothing about the list itself changes: the same networks, the same details, and the same manual refresh button.

## Wi-Fi switching stays in the system
- The popover no longer joins a network or switches between them. Choosing a network opens the Wi-Fi pane of System Settings, and the Wi-Fi page says so above the button that opens it.
- Status Trio no longer reads or stores Wi-Fi passwords. The old behaviour could not be made dependable: macOS keeps a saved network's password to itself, and a stored copy that had gone stale ended in failed joins and repeated Keychain prompts, with no way to tell you the password was wrong.
- If you ticked **Remember password** in an earlier version, that Keychain item is still there and is no longer used. You can delete it in Keychain Access by searching for `com.lingsmbp.StatusTrio.wifi-password`.
- Nothing else about the page changed: the same networks, the same signal and link details, the same Wi-Fi switch, and the same button that opens System Settings.

## Bluetooth battery levels are on by default
- **Show Bluetooth battery levels** under **Settings › Bluetooth** now starts enabled, so a connected device reports its battery without a trip into Settings. Turning it off still stops the read.
- The Bluetooth device page no longer prints **Unavailable** on every row: a device that reports no battery shows its name alone, and a report that cannot be read is reported once under the list.
