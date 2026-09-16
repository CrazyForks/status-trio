# Status Trio Performance Optimization Design

## Goal

Reduce sustained CPU usage and avoid unnecessary memory growth in the menu bar app while preserving status accuracy and existing appearance behavior.

## Root-Cause Candidates

1. `StatusBarController` observes both `NSApp.effectiveAppearance` and the status button appearance. Each notification starts a new render task, and render replaces a dynamic `NSImage`. This can form a self-sustaining AppKit render loop.
2. Volume and Wi-Fi notifications run full reads on the main actor. Volume refreshes enumerate every audio device even when only scalar or mute changed. Wi-Fi link-quality callbacks perform synchronous CoreWLAN reads, including SSID.
3. Monitor `AsyncStream`s use the default unbounded buffer.
4. Menu bar rendering captures the full `StatusSnapshot`, including output devices and SSID, although the icon only needs a small subset.
5. Hidden popover and settings windows retain large SwiftUI view graphs and continue observing shared stores.
6. The 5-second store refresh and 5-second icon fallback redraw are unconditional.

## Design

### Render deduplication

- Introduce a lightweight `MenuBarStatus` containing only battery, Wi-Fi, connection, and volume-level data.
- Introduce `StatusBarRenderKey` and a small render cache. A render is skipped unless status, icon size, options, or resolved appearance changed.
- Update the render cache before mutating the status button so reentrant appearance notifications become no-ops.
- Observe only the status button appearance, not both `NSApp` and the button.
- Remove the unconditional icon fallback timer. Snapshot publication is already de-duplicated, so unchanged data must not trigger rendering.
- Update accessibility only when its lightweight status or language changes.

### Event coalescing

- Add a shared `MonitorStream.make` helper using `.bufferingNewest(1)`.
- Coalesce volume and Wi-Fi event callbacks over a short debounce window.
- Volume level changes reuse a cached output-device list.
- Full output-device enumeration occurs on popover open, default-device change, or periodic refresh while details are visible.
- Wi-Fi reads SSID only while popover details are visible.

### Detail lifetime

- Add `setDetailsVisible(_:)` to Wi-Fi and volume monitor protocols.
- `SystemStatusStore.setPopoverVisible(_:)` forwards visibility and refreshes details when opened.
- Popover content is recreated on open and released on close.
- Settings window content is released on close and recreated on the next show.

### Adjustable refresh interval

- Persist a refresh interval in `SettingsStore`, default 5 seconds, range 5–300 seconds, step 5 seconds.
- Add a setting in the Basics pane.
- `SystemStatusStore` reads the current interval for each sleep cycle, so the next scheduled refresh uses the new value without replacing the store.
- Existing status monitors remain event-driven; the interval is only a fallback.

## Error Handling

- Invalid or non-finite interval values fall back to the default and are clamped.
- Monitor debounce tasks are cancelled on stop/deinit.
- Missing audio devices, Wi-Fi data, or localization bundles continue to use existing fallback behavior.

## Testing

- Unit-test render-key equality and no-op behavior.
- Unit-test monitor coalescing and cache reuse.
- Unit-test lazy detail visibility.
- Unit-test stream buffering policy through `MonitorStream`.
- Unit-test refresh-interval persistence and clamping.
- Run `swift test` and `swift build -c release`.
- Run the non-publishing release workflow because changes touch `@MainActor`, SwiftUI observation, bindings, and resource-sensitive localization.
