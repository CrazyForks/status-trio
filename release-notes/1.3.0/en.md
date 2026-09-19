# Version %VERSION% (Build %BUILD%)

## Native Liquid Glass on macOS 26 and later
- The popover now uses the system's own Liquid Glass material instead of the frosted look carried over from earlier macOS releases, so it matches the menus and panels around it.
- This is the system appearance, not an app-specific style: it follows your system settings, including Reduce Transparency and the system glass tint.
- macOS 15 to 25 keep the appearance they already had; the deployment target is unchanged, so no user has to update macOS to keep using Status Trio.

## Panel opens over full-screen apps
- Clicking the menu bar icon now opens the status panel while another app is in full screen. The panel used to open behind that app, so the click looked like it did nothing.
