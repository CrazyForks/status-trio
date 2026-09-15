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
