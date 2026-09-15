import AppKit

/// Where the Dock lives on screen. Its orientation is not exposed directly, but
/// it is the only thing that can shrink a screen's visible frame horizontally.
enum DockPlacement: Equatable {
    case bottom
    case left
    case right

    static func resolve(screenFrame: NSRect, visibleFrame: NSRect) -> DockPlacement {
        if visibleFrame.minX > screenFrame.minX {
            return .left
        }
        if visibleFrame.maxX < screenFrame.maxX {
            return .right
        }
        return .bottom
    }

    /// Whether a screen point sits in the Dock's strip along the screen edge.
    ///
    /// With a visible Dock the strip is the part of the screen the Dock takes
    /// away; with an auto-hiding Dock the visible frame fills the screen, so the
    /// edge tolerance is the only usable signal.
    func containsPointer(
        _ point: NSPoint,
        screenFrame: NSRect,
        visibleFrame: NSRect,
        collapsedTolerance: CGFloat = 120
    ) -> Bool {
        switch self {
        case .bottom:
            let strip = visibleFrame.minY - screenFrame.minY
            let limit = strip > 4 ? visibleFrame.minY : screenFrame.minY + collapsedTolerance
            return point.y <= limit
        case .left:
            let strip = visibleFrame.minX - screenFrame.minX
            let limit = strip > 4 ? visibleFrame.minX : screenFrame.minX + collapsedTolerance
            return point.x <= limit
        case .right:
            let strip = screenFrame.maxX - visibleFrame.maxX
            let limit = strip > 4 ? visibleFrame.maxX : screenFrame.maxX - collapsedTolerance
            return point.x >= limit
        }
    }
}

/// The hidden anchor window position and popover edge for a Dock icon click.
struct DockPopoverAnchor: Equatable {
    let origin: NSPoint
    let preferredEdge: NSRectEdge

    static func make(
        clickPoint: NSPoint,
        tileSize: NSSize,
        placement: DockPlacement
    ) -> DockPopoverAnchor {
        let tileWidth = max(0, tileSize.width)
        let tileHeight = max(0, tileSize.height)

        switch placement {
        case .bottom:
            return DockPopoverAnchor(
                origin: NSPoint(x: clickPoint.x, y: clickPoint.y + tileHeight / 2),
                preferredEdge: .maxY
            )
        case .left:
            return DockPopoverAnchor(
                origin: NSPoint(x: clickPoint.x + tileWidth / 2, y: clickPoint.y),
                preferredEdge: .maxX
            )
        case .right:
            return DockPopoverAnchor(
                origin: NSPoint(x: clickPoint.x - tileWidth / 2, y: clickPoint.y),
                preferredEdge: .minX
            )
        }
    }
}
