import AppKit

/// The anchor a status panel hangs from: a positioning rect in screen
/// coordinates plus the edge of that rect the panel should sit next to.
///
/// The panel replaces `NSPopover` (issue #186), so the placement maths that the
/// popover used to own are explicit and testable here.
struct StatusPanelAnchor: Equatable {
    /// The anchor rect in screen coordinates (origin bottom-left, Y up).
    let screenRect: NSRect
    /// The edge of `screenRect` the panel attaches to, mirroring
    /// `NSPopover.show(relativeTo:of:preferredEdge:)`.
    let preferredEdge: NSRectEdge
}

/// A screen's geometry in the small shape placement needs, so the maths can be
/// unit-tested without constructing an `NSScreen`.
struct StatusPanelScreen: Equatable {
    let frame: NSRect
    let visibleFrame: NSRect

    init(frame: NSRect, visibleFrame: NSRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    init(_ screen: NSScreen) {
        self.init(frame: screen.frame, visibleFrame: screen.visibleFrame)
    }
}

enum StatusPanelPlacement {
    /// The visual gap between the anchor and the panel. `NSPopover` spent this
    /// distance on its arrow; with the arrow gone the panel sits close to the
    /// menu bar / Dock without touching it.
    static let gap: CGFloat = 6

    /// Chooses the frame for a panel of `contentSize` anchored at `anchor`.
    ///
    /// The panel is centred on the anchor's perpendicular axis, flushed to the
    /// chosen edge with `gap`, and clamped to the screen's visible frame. When
    /// the preferred side has no room it flips to the opposite side, matching
    /// the popover behaviour users already expect. The frame keeps its top edge
    /// fixed for `.minY` (menu bar) anchors, so a growing panel extends
    /// downwards instead of jumping.
    static func frame(
        contentSize: NSSize,
        anchor: StatusPanelAnchor,
        screens: [StatusPanelScreen]
    ) -> NSRect {
        let size = NSSize(
            width: max(contentSize.width, 1),
            height: max(contentSize.height, 1)
        )
        let anchorRect = anchor.screenRect
        let visibleFrame = screenContaining(anchorRect, screens: screens)?.visibleFrame ?? anchorRect

        var origin: NSPoint
        switch anchor.preferredEdge {
        case .minY, .maxY:
            let below = NSPoint(
                x: anchorRect.midX - size.width / 2,
                y: anchorRect.minY - gap - size.height
            )
            let above = NSPoint(
                x: anchorRect.midX - size.width / 2,
                y: anchorRect.maxY + gap
            )
            if anchor.preferredEdge == .minY {
                origin = fits(below, size: size, in: visibleFrame) ? below : above
            } else {
                origin = fits(above, size: size, in: visibleFrame) ? above : below
            }
        case .maxX, .minX:
            let toRight = NSPoint(
                x: anchorRect.maxX + gap,
                y: anchorRect.midY - size.height / 2
            )
            let toLeft = NSPoint(
                x: anchorRect.minX - gap - size.width,
                y: anchorRect.midY - size.height / 2
            )
            if anchor.preferredEdge == .maxX {
                origin = fits(toRight, size: size, in: visibleFrame) ? toRight : toLeft
            } else {
                origin = fits(toLeft, size: size, in: visibleFrame) ? toLeft : toRight
            }
        @unknown default:
            origin = NSPoint(
                x: anchorRect.midX - size.width / 2,
                y: anchorRect.minY - gap - size.height
            )
        }

        origin.x = min(
            max(origin.x, visibleFrame.minX),
            max(visibleFrame.minX, visibleFrame.maxX - size.width)
        )
        origin.y = min(
            max(origin.y, visibleFrame.minY),
            max(visibleFrame.minY, visibleFrame.maxY - size.height)
        )
        return NSRect(origin: origin, size: size)
    }

    /// The screen whose frame contains the anchor's centre, falling back to the
    /// first screen. A menu-bar anchor can sit just outside `visibleFrame`
    /// (inside the menu bar strip), so the full `frame` is the right test.
    static func screenContaining(
        _ rect: NSRect,
        screens: [StatusPanelScreen]
    ) -> StatusPanelScreen? {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return screens.first { $0.frame.contains(center) } ?? screens.first
    }

    private static func fits(_ origin: NSPoint, size: NSSize, in visibleFrame: NSRect) -> Bool {
        let rect = NSRect(origin: origin, size: size)
        return visibleFrame.contains(rect)
    }
}
