# Status Trio Dock Icon Display Design

- Date: 2026-09-15
- Branch: `codex/dock-icon-display`
- Scope: selectable Menu Bar/Dock presence and a live-rendered Dock icon

## Goal

Let the user keep Status Trio in the Menu Bar, the Dock, or both. At least one location must always remain enabled. When the Dock is enabled, its icon follows the same battery, connection, Wi-Fi, and volume status as the Menu Bar icon.

## Confirmed Product Decisions

1. The setting has exactly three values: Menu Bar Only, Dock Only, and Both.
2. Menu Bar Only remains the default so existing users keep the current behavior.
3. There is no Neither value. Hiding both surfaces would be equivalent to closing the app and would remove the settings entry point.
4. Clicking the Dock icon opens the existing Settings window. A separate Dock-anchored status window is outside this change.
5. The Menu Bar icon size setting does not resize the Dock icon. The Dock uses a fixed macOS app-icon canvas.
6. Battery and connection display options affect both Menu Bar and Dock rendering.

## Current Architecture

- `Support/Info.plist` sets `LSUIElement=true`, so the app starts without a Dock icon.
- `AppDelegate` currently forces `.accessory` at launch.
- `AppActivationPolicy` temporarily switches to `.regular` while Settings is open, then returns to `.accessory` when the final temporary owner leaves.
- `StatusBarController` owns the `NSStatusItem`, subscribes to status/settings changes, debounces status updates, and skips duplicate renders with `StatusBarRenderCache`.
- `StatusIconRenderer` already produces an `NSImage` or `CGImage` for the current `MenuBarStatus` and display options.

The existing temporary activation counter cannot represent a user preference to keep the Dock icon visible. Closing Settings would currently hide the Dock even when the user selected Dock Only or Both.

## Research Findings

Apple documents `NSApplication.applicationIconImage` as the API for temporarily replacing the app's Dock tile image. The Dock scales the supplied image and restores the bundled icon when the property is set to `nil`.

Apple's `NSDockTile.contentView` is intended for a continuously custom-drawn tile and requires explicit `display()` calls. Open-source examples such as AirBattery use this for live SwiftUI content, but this keeps an additional view graph alive and can increase update cost. Status Trio already renders immutable status images, so a custom Dock content view is unnecessary.

Open-source Menu Bar apps consistently use runtime activation policy changes for Dock visibility:

- eqMac models Dock, Status Bar, Both, and Neither, then combines `.regular`/`.accessory` with `NSStatusItem.isVisible`.
- Stats and Lunar persist a Dock preference and apply `.regular`/`.accessory` immediately.
- AirBattery combines a placement mode with a live Dock tile, but its implementation also warns that Dock rendering increases energy use.

References:

- <https://developer.apple.com/documentation/appkit/nsapplication/applicationiconimage>
- <https://developer.apple.com/documentation/appkit/nsapplication/setactivationpolicy(_:)>
- <https://developer.apple.com/documentation/appkit/nsdocktile>
- <https://github.com/bitgapp/eqMac/blob/04e5a3a9bd3a65f2b5105cf54a76d2c72a1d00d7/native/app/Source/Settings/Settings.swift>
- <https://github.com/exelban/stats/blob/27c0c343a0df77ffaca8317c31b4e3aa14754eb7/Stats/Views/AppSettings.swift>
- <https://github.com/alin23/Lunar/blob/8a21ffe302a00890d9f5d5101536cdd2a4631be8/Lunar/AppDelegate.swift>
- <https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/Supports/AirBatteryApp.swift>

## Considered Approaches

### Recommended: `applicationIconImage` plus a bitmap compositor

Create a Dock-specific renderer that draws the existing dark rounded-square App Icon background, then composites the current Status Trio glyph over it. Assign the finished `NSImage` to `NSApplication.applicationIconImage` only when Dock display is enabled.

This preserves the native app-icon silhouette, reuses the tested status renderer, has no persistent Dock view hierarchy, and lets the existing render-key strategy suppress duplicate work.

### Rejected: `NSDockTile.contentView`

Hosting SwiftUI or an `NSImageView` in the Dock tile is useful for animation, progress bars, or multiple independently updating subviews. Status Trio only needs to replace one rendered image after a meaningful status change. A custom view adds lifecycle, redraw, and energy overhead without a user-visible benefit.

### Rejected: changing `LSUIElement` and relaunching

Editing the bundle behavior or requiring a restart makes the setting slow and brittle. Apple supports runtime activation-policy switching, and the existing app already relies on it for Settings.

## Data Model

Add a persisted `AppIconPlacement` enum:

```swift
enum AppIconPlacement: String, CaseIterable, Identifiable, Sendable {
    case menuBar
    case dock
    case both

    var id: Self { self }
    var showsMenuBarIcon: Bool { self != .dock }
    var showsDockIcon: Bool { self != .menuBar }
}
```

`SettingsStore` owns `@Published var appIconPlacement`, stores the raw value in `UserDefaults`, defaults to `.menuBar`, and falls back to `.menuBar` for unknown stored values. An enum makes the invalid "neither" state unrepresentable instead of repairing two independent Boolean settings after the fact.

## Activation Policy

Convert `AppActivationPolicy` from global static state into an injected `@MainActor` instance. It tracks two inputs:

- `keepsDockIconVisible`: persistent user intent from `AppIconPlacement`.
- `temporaryRegularRequestCount`: transient owners such as the Settings window.

The desired policy is `.regular` when either input requires it and `.accessory` otherwise. Closing Settings therefore cannot hide a user-selected Dock icon. Opening Settings in Menu Bar Only mode still temporarily provides normal window activation.

Keep `LSUIElement=true`. This prevents a Dock flash for the default Menu Bar Only mode; selecting Dock Only or Both promotes the running app to `.regular`.

When moving from Menu Bar Only to Dock Only, request `.regular` and install the Dock image before hiding the status item. When moving back, show the status item before requesting `.accessory`. If AppKit reports that a policy change failed, keep the Menu Bar visible so the app never loses all entry points.

## Presentation Coordination

Add an `AppIconController` retained by `AppEnvironment`. It owns placement coordination and Dock rendering while leaving menu interaction inside `StatusBarController`.

On a placement change it:

1. Makes the destination surface visible before hiding the source surface.
2. Updates persistent Dock intent in `AppActivationPolicy`.
3. Calls `StatusBarController.setVisible(_:)`.
4. Renders the latest Dock image when Dock becomes visible.
5. Sets `applicationIconImage=nil` when Dock display is disabled, restoring the packaged icon during temporary `.regular` periods.

`StatusBarController.setVisible(false)` closes an open popover, ends detail monitoring, and avoids further Menu Bar image renders while hidden. Re-enabling it renders the latest snapshot immediately.

`AppDelegate.applicationShouldHandleReopen` forwards Dock clicks to `SettingsWindowController.show()` and returns `false`, avoiding an empty default window.

## Dock Rendering

Add `DockIconRenderer`, which:

- Produces a non-template square `NSImage` with a 1024-pixel backing representation.
- Matches `Support/AppIcon.svg`: `#151517` rounded-square fill, `#3A3A3D` border, and transparent outer margin.
- Uses `StatusIconRenderer.render` for the current `MenuBarStatus` instead of duplicating battery, Wi-Fi, connection, or volume geometry.
- Uses white as the normal foreground because the Dock artwork has a fixed dark background.
- Preserves existing charging green, low-power yellow, and critical red behavior.
- Accepts `BatteryIconOptions` and `ConnectionIconOptions`, but not the Menu Bar `iconSize` or appearance.

Add `DockIconRenderKey`/`DockIconRenderCache` covering status plus both option structs. The controller debounces snapshot updates by the existing 0.5-second icon interval, skips equal keys, and does no Dock rendering while Dock display is disabled.

Finder, Launchpad, alerts, and the on-disk `.icns` continue using the static packaged App Icon. `applicationIconImage` changes only the running app's Dock tile and is reset to `nil` when dynamic Dock display is disabled or the controller is torn down.

## Settings UI And Localization

Add a segmented picker to the Basics pane near Launch at Login. The choices are Menu Bar, Dock, and Both. Use localized text labels so VoiceOver and keyboard navigation do not depend on symbols alone.

Add localization keys for the row title, description, and three values in all 12 supported languages. Keep the existing Menu Bar settings tab focused on size and connection-icon style; no tab rename is needed.

## Error Handling

- Unknown stored placement values fall back to Menu Bar Only.
- A failed `.regular` transition leaves the Menu Bar visible.
- A failed Dock render keeps the last valid dynamic image; if no valid image exists, setting `applicationIconImage=nil` restores the bundled icon.
- Repeated placement assignments, window enter/leave calls, and identical status snapshots are idempotent.
- Temporary activation request counts never fall below zero.

## Testing

- Unit-test all placement visibility combinations and persistence fallback.
- Unit-test activation policy resolution across persistent Dock intent and nested temporary Settings requests.
- Unit-test transition ordering so a failed Dock activation never hides the Menu Bar.
- Unit-test Dock image dimensions, opaque rounded-square body, transparent outer margin, and status color changes.
- Unit-test render-cache equality and disabled-Dock no-op behavior.
- Extend localization completeness tests; do not test SwiftUI view internals directly.
- Manually verify all three placement modes, live status changes, Settings open/close behavior, Dock click reopening, and relaunch persistence.

## CI And Compatibility

The implementation must compile with the repository acceptance toolchain: macOS 15 runner, Xcode 16.4, and Swift 6.1.2. Do not use Swift 6.2-only syntax or APIs.

Run `swift test` and `swift build -c release`. Because the change touches `@MainActor`, SwiftUI bindings, AppKit lifecycle, and localized resources, run the non-publishing release workflow for `codex/dock-icon-display` before merge or release.

## Out Of Scope

- A Dock-anchored clone of the status popover.
- A separate Dock icon size control.
- Animation or per-frame Dock drawing.
- A Neither/hidden-everywhere mode.
- Changes to the static Finder/Launchpad icon or release signing.
