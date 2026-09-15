import AppKit
import Testing
@testable import StatusTrioCore

struct DockPlacementTests {
    @Test func detectsTheDockOnTheLeft() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = NSRect(x: 70, y: 0, width: 1370, height: 875)

        #expect(DockPlacement.resolve(screenFrame: frame, visibleFrame: visible) == .left)
    }

    @Test func detectsTheDockOnTheRight() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = NSRect(x: 0, y: 0, width: 1370, height: 875)

        #expect(DockPlacement.resolve(screenFrame: frame, visibleFrame: visible) == .right)
    }

    @Test func detectsTheDockAtTheBottom() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = NSRect(x: 0, y: 70, width: 1440, height: 805)

        #expect(DockPlacement.resolve(screenFrame: frame, visibleFrame: visible) == .bottom)
    }
}

struct DockPopoverAnchorTests {
    @Test func anchorsAboveABottomDock() {
        let anchor = DockPopoverAnchor.make(
            clickPoint: NSPoint(x: 100, y: 20),
            tileSize: NSSize(width: 48, height: 48),
            placement: .bottom
        )

        #expect(anchor.origin == NSPoint(x: 100, y: 44))
        #expect(anchor.preferredEdge == .maxY)
    }

    @Test func anchorsToTheRightOfALeftDock() {
        let anchor = DockPopoverAnchor.make(
            clickPoint: NSPoint(x: 24, y: 500),
            tileSize: NSSize(width: 48, height: 48),
            placement: .left
        )

        #expect(anchor.origin == NSPoint(x: 48, y: 500))
        #expect(anchor.preferredEdge == .maxX)
    }

    @Test func anchorsToTheLeftOfARightDock() {
        let anchor = DockPopoverAnchor.make(
            clickPoint: NSPoint(x: 1416, y: 500),
            tileSize: NSSize(width: 48, height: 48),
            placement: .right
        )

        #expect(anchor.origin == NSPoint(x: 1392, y: 500))
        #expect(anchor.preferredEdge == .minX)
    }
}

struct DockAreaPointerTests {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func recognisesAPointerInsideAVisibleBottomDock() {
        let visible = NSRect(x: 0, y: 70, width: 1440, height: 805)

        #expect(
            DockPlacement.bottom.containsPointer(
                NSPoint(x: 700, y: 30),
                screenFrame: screen,
                visibleFrame: visible
            )
        )
        #expect(
            DockPlacement.bottom.containsPointer(
                NSPoint(x: 700, y: 400),
                screenFrame: screen,
                visibleFrame: visible
            ) == false
        )
    }

    @Test func recognisesAPointerInsideAVisibleLeftDock() {
        let visible = NSRect(x: 70, y: 0, width: 1370, height: 875)

        #expect(
            DockPlacement.left.containsPointer(
                NSPoint(x: 24, y: 400),
                screenFrame: screen,
                visibleFrame: visible
            )
        )
        #expect(
            DockPlacement.left.containsPointer(
                NSPoint(x: 600, y: 400),
                screenFrame: screen,
                visibleFrame: visible
            ) == false
        )
    }

    @Test func usesAnEdgeToleranceWhenTheDockAutoHides() {
        // With auto-hide the visible frame fills the screen, so the Dock area has
        // to be inferred from the screen edge.
        let visible = screen

        #expect(
            DockPlacement.bottom.containsPointer(
                NSPoint(x: 700, y: 40),
                screenFrame: screen,
                visibleFrame: visible
            )
        )
        #expect(
            DockPlacement.bottom.containsPointer(
                NSPoint(x: 700, y: 400),
                screenFrame: screen,
                visibleFrame: visible
            ) == false
        )
        #expect(
            DockPlacement.right.containsPointer(
                NSPoint(x: 1430, y: 400),
                screenFrame: screen,
                visibleFrame: visible
            )
        )
    }
}
