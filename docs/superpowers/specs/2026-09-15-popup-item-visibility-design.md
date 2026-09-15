# Popup Item Visibility Design

## Goal

Let users choose which status sections appear in the status popup. The existing
order preference remains available, but order and visibility become independent
settings.

## Defaults and Migration

- Battery, Network, and Volume are enabled by default.
- Bluetooth is disabled by default.
- A fresh install therefore shows Battery, Network, and Volume in the popup.
- Existing installs without a visibility preference also adopt these defaults.
- Existing popup ordering is preserved. Disabled sections keep their position
  in the settings list and reappear at that position when enabled again.
- Unknown persisted section identifiers are ignored.

## Settings UI

The existing Popup Order section becomes Popup Items.

- Every row has a checkbox-style visibility toggle, the section icon and title,
  and the existing drag handle.
- Changing a toggle immediately updates popup visibility and persists it.
- Dragging continues to change only the full section order, including disabled
  sections.
- These settings affect the popup only. They do not change menu bar icon
  behavior or monitor availability for Battery, Network, or Volume.

## Popup Rendering

The popup renders the stored order filtered by the enabled section set.

- Dividers are inserted only between visible sections.
- Bluetooth is absent from the initial popup because it is disabled by default.
- Network keeps its existing default behavior and permission flow. Selecting the
  Network permission action still requests location access in the same way as
  before.

## Bluetooth Permission Flow

Bluetooth remains lazy: the app does not create `CBCentralManager` at launch.

- Enabling the Bluetooth row is the first action allowed to start
  `BluetoothDeviceController` and trigger the macOS Bluetooth permission
  prompt.
- The settings window activates the app before starting CoreBluetooth so the
  system prompt is presented in front.
- The app does not cancel the preference if permission is denied or dismissed.
  The Bluetooth popup continues to show the existing denied, restricted, or
  retry states.
- Disabling Bluetooth stops the Bluetooth monitor and removes the Bluetooth
  section from the popup.
- Opening the popup by itself must not start CoreBluetooth.

## Data Model

`SettingsStore` owns a persisted set of enabled `PopupSection` values.

- The full order remains `popupSectionOrder`.
- `visiblePopupSections` returns `popupSectionOrder` filtered by the enabled set.
- `setPopupSection(_:enabled:)` updates and persists visibility.
- Missing storage uses the default set: Battery, Network, and Volume.

`SystemStatusStore` exposes Bluetooth lifecycle methods used by the settings UI:

- Enabling starts Bluetooth monitoring and requests authorization.
- Disabling stops Bluetooth monitoring.

## Testing

- Settings tests cover defaults, persistence, sanitization, and filtering by
  visibility without changing order.
- Bluetooth timing tests verify that opening the popup does not start
  CoreBluetooth, enabling Bluetooth does, and disabling Bluetooth stops it.
- Existing localization coverage must pass for all supported languages.
- Run `swift test` and `swift build -c release`.
- Run a non-publishing release workflow preflight because the change touches
  `@MainActor`, SwiftUI bindings, and CoreBluetooth lifecycle.

## Out of Scope

- Changing menu bar icon visibility.
- Adding or removing `PopupSection` cases.
- Requesting Bluetooth permission before the user enables the Bluetooth item.
