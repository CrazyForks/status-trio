import AppKit
import Testing
@testable import StatusTrioCore

struct StatusPanelPlacementTests {
    private let screen = StatusPanelScreen(
        frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 875)
    )

    @Test func menuBarAnchorHangsCentredBelowWithTheGap() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 708, y: 880, width: 24, height: 18),
            preferredEdge: .minY
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.origin == NSPoint(x: 555, y: 474))
        #expect(frame.size == NSSize(width: 330, height: 400))
    }

    @Test func clampsToTheTrailingScreenEdge() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 1410, y: 880, width: 24, height: 18),
            preferredEdge: .minY
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.maxX == 1440)
        #expect(frame.minX == 1110)
        // Horizontal overflow must clamp, not flip: the panel stays below the
        // menu bar with the regular gap.
        #expect(frame.maxY == anchor.screenRect.minY - StatusPanelPlacement.gap)
    }

    @Test func flipsAboveWhenThereIsNoRoomBelow() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 488, y: 10, width: 24, height: 18),
            preferredEdge: .minY
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.minY == 34)
        #expect(frame.maxY == 434)
    }

    @Test func bottomDockAnchorSitsAboveTheIcon() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 488, y: 20, width: 24, height: 18),
            preferredEdge: .maxY
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.origin == NSPoint(x: 335, y: 44))
    }

    @Test func leftDockAnchorSitsToTheRightOfTheIcon() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 10, y: 388, width: 18, height: 24),
            preferredEdge: .maxX
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.origin == NSPoint(x: 34, y: 200))
    }

    @Test func rightDockAnchorSitsToTheLeftOfTheIcon() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 1410, y: 388, width: 18, height: 24),
            preferredEdge: .minX
        )

        let frame = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 400),
            anchor: anchor,
            screens: [screen]
        )

        #expect(frame.origin == NSPoint(x: 1074, y: 200))
    }

    @Test func picksTheScreenContainingTheAnchor() {
        let secondary = StatusPanelScreen(
            frame: NSRect(x: -1920, y: 0, width: 1920, height: 1080),
            visibleFrame: NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        )
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: -600, y: 500, width: 24, height: 18),
            preferredEdge: .minY
        )

        #expect(StatusPanelPlacement.screenContaining(anchor.screenRect, screens: [screen, secondary]) == secondary)
    }

    @Test func growingContentKeepsTheTopEdgeFixedForMenuBarAnchors() {
        let anchor = StatusPanelAnchor(
            screenRect: NSRect(x: 708, y: 880, width: 24, height: 18),
            preferredEdge: .minY
        )

        let short = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 200),
            anchor: anchor,
            screens: [screen]
        )
        let tall = StatusPanelPlacement.frame(
            contentSize: NSSize(width: 330, height: 500),
            anchor: anchor,
            screens: [screen]
        )

        #expect(short.maxY == tall.maxY)
        #expect(tall.minY < short.minY)
    }
}
