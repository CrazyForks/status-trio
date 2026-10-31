# Issue #186 — arrowless status panel (custom `NSPanel`)

Status: **implemented locally, focused tests pass; live visual and background
UI verification pending.**

Related issues:

- [#186 去掉弹出面板顶部的尖角（NSPopover 箭头）](https://github.com/lingyired/status-trio/issues/186)
- [Issue #165 template-image view](issue-165-template-image-view.md) — the menu
  bar icon layout this change does not touch.
- [#40 菜单栏展开玻璃通透度](../popover-glass-investigation.md) — the native
  Liquid Glass decision this change preserves.

## Problem

`NSPopover` draws the small arrow that points at the status item. AppKit has no
public API to hide it (verified in the macOS 26, 27 and 27.2 SDK headers:
`NSPopover.h` contains no arrow property), so the only supported way to remove
it is to stop using `NSPopover` and draw/position the panel ourselves.

## Implementation

- New `Sources/StatusTrioCore/UI/AnchoredStatusPanel.swift`:
  - `AnchoredStatusPanel: NSPanel` — borderless, `.nonactivatingPanel`,
    `.statusBar` level, `canBecomeKey == true`, `canBecomeMain == false`,
    `.canJoinAllSpaces + .fullScreenAuxiliary` (replacing the popover's
    `enableDisplayOnFullScreenSpaces()` call — the helper is still applied for
    the same contract).
  - `StatusPanelContentViewController` wraps the SwiftUI hosting controller in a
    native glass background and follows `NSHostingView.fittingSize` so expanding
    rows and detail pages resize the window exactly as the popover did.
  - `close()` / `performClose(_:)` order the window out, post
    `AnchoredStatusPanel.didCloseNotification` and call `onClose`; this replaces
    `NSPopoverDelegate.popoverDidClose(_:)`. The controller's five-second
    content-retention contract is unchanged.
  - Escape, outside clicks (existing global monitor), app deactivation and the
    status item toggle all close the panel.
- New `Sources/StatusTrioCore/UI/StatusPanelPlacement.swift`: pure placement
  maths (anchor rect + preferred edge + content size + screen geometry), with
  the popover's centring, 6 pt gap, visible-frame clamping and
  flip-to-the-opposite-side fallback. Covered by
  `Tests/StatusTrioCoreTests/StatusPanelPlacementTests.swift`.
- `StatusBarController` uses `AnchoredStatusPanel` instead of `NSPopover`; the
  lifecycle calls (`show`, `performClose`, `isShown`, `contentViewController`)
  keep the same shape so the content lifecycle tests still exercise the same
  contracts.

## Glass

The popover's chrome came from the private `NSPopoverFrame`; the panel reproduces
it with public views only:

| macOS | Background |
| --- | --- |
| 26+ | `NSGlassEffectView(style: .regular)`, `cornerRadius = 16` |
| 13–25 | `NSVisualEffectView(material: .popover, blendingMode: .behindWindow)` |
| Reduce Transparency on | solid `windowBackgroundColor` with the same corner radius |

The window is transparent, `hasShadow == true`, and the rounded background is
what gives the shadow its shape. `NSGlassEffectView` is guarded with
`#available(macOS 26.0, *)`, matching the existing SDK-26 floor.

## Known differences from `NSPopover`

These are deliberate and recorded in `docs/known-limitations.md`:

- The panel does not continuously track the anchor while it is open; it
  repositions on show, on content resize and on screen-parameter changes.
  `NSPopover` moved with the status item frame.
- `NSPopover`'s show/close animation and detach-by-drag interaction are gone
  (`animationBehavior = .none`).
- Clicking another window **of this app** (for example an already-open Settings
  window) does not dismiss the panel; clicking another app, the status item,
  Escape, or any panel action does. Actions that open Settings already close the
  panel explicitly.
- The panel uses the public `NSGlassEffectView` / `NSVisualEffectView` path
  instead of the private `NSPopoverFrame`, so it cannot inherit AppKit's popover
  chrome on future releases; that is the trade-off issue #186 chose.

## Verification

Done locally:

- `bash scripts/test.sh 'StatusPanelPlacementTests|StatusBarMemoryPressureTests|StatusBarContentLifecycleTests|PopoverWindowPlacementTests'`
  — pass.
- Full `swift test` suite — see the delivery report.
- Release build and the `full` local profile — see the delivery report.

Not proven by local tests:

- Whether the glass corner radius, shadow shape and content insets match the
  previous popover visually on macOS 26/27.
- Ventura (macOS 13) runtime behaviour of the `NSVisualEffectView` fallback and
  the `NSHostingView.fittingSize` sizing path.
- Real multi-display placement, full-screen Spaces and Dock anchoring.
- Background UI testing and any manual visual approval.
