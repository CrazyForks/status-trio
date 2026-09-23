# Version %VERSION% (Build %BUILD%)

## Fixes and improvements
- A Bluetooth device can no longer appear twice. When the system report carried one address twice — a connect or a disconnect caught in the middle, or a Mac with more than one Bluetooth controller — the panel drew that device on two rows, and the two rows shared one set of controls. Each address is now read once.
- A device's level now comes from its connected entry. When the report carried both, the disconnected copy was read second and overwrote the current charge, so a row could show the reading macOS wrote down last.
- The AirPods charging case is drawn as a case glyph instead of the word "Case", which frees the room the word took and removes the last untranslated word from a level.
