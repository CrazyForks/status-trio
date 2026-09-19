import AppKit
import Testing
@testable import StatusTrioCore

/// AppKit creates a status-item popover's backing window with no Spaces
/// behavior, which ties it to the one Space this accessory app occupies: over
/// another app's full-screen Space the popover is shown on the desktop Space
/// instead, so the click looks like it did nothing. These tests pin the
/// behavior the popover window needs, including the flag AppKit refuses to hold
/// at the same time.
@MainActor
struct PopoverWindowPlacementTests {
    @Test func joinsEverySpaceAndFullScreenSpaces() {
        let window = makeWindow()
        window.collectionBehavior = []

        window.enableDisplayOnFullScreenSpaces()

        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    @Test func dropsMoveToActiveSpaceInsteadOfAbortingTheApp() {
        let window = makeWindow()
        window.collectionBehavior = [.moveToActiveSpace]

        window.enableDisplayOnFullScreenSpaces()

        #expect(window.collectionBehavior.contains(.moveToActiveSpace) == false)
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
    }

    @Test func keepsUnrelatedCollectionBehavior() {
        let window = makeWindow()
        window.collectionBehavior = [.ignoresCycle, .stationary]

        window.enableDisplayOnFullScreenSpaces()

        #expect(window.collectionBehavior.contains(.ignoresCycle))
        #expect(window.collectionBehavior.contains(.stationary))
    }

    /// `defer: true` keeps the window device from being created: only the Spaces
    /// flags are under test.
    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
    }
}
