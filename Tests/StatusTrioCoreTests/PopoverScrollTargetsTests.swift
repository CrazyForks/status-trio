import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class PopoverScrollTargetsTests: XCTestCase {
    func testRegisteredVolumeControlMatchesPointsInsideItsFrame() {
        let window = makeWindow()
        let targets = PopoverScrollTargets()
        let control = makeControlView(in: window)
        targets.registerVolumeControl(control)

        XCTAssertTrue(
            targets.containsVolumeControl(at: NSPoint(x: 100, y: 70), in: window)
        )
        XCTAssertFalse(
            targets.containsVolumeControl(at: NSPoint(x: 100, y: 20), in: window)
        )
        XCTAssertFalse(
            targets.containsVolumeControl(at: NSPoint(x: 10, y: 70), in: window)
        )
    }

    func testRegionIsEmptyBeforeRegistrationAndAfterRemoval() {
        let window = makeWindow()
        let targets = PopoverScrollTargets()
        let control = makeControlView(in: window)
        let point = NSPoint(x: 100, y: 70)

        XCTAssertFalse(targets.containsVolumeControl(at: point, in: window))

        targets.registerVolumeControl(control)
        XCTAssertTrue(targets.containsVolumeControl(at: point, in: window))

        targets.unregisterVolumeControl(control)
        XCTAssertFalse(targets.containsVolumeControl(at: point, in: window))
    }

    func testStaleRemovalKeepsTheCurrentVolumeControl() {
        let window = makeWindow()
        let targets = PopoverScrollTargets()
        let control = makeControlView(in: window)
        let stale = NSView(frame: control.frame)
        targets.registerVolumeControl(control)

        targets.unregisterVolumeControl(stale)

        XCTAssertTrue(
            targets.containsVolumeControl(at: NSPoint(x: 100, y: 70), in: window)
        )
    }

    func testControlInAnotherWindowNeverMatches() {
        let window = makeWindow()
        let otherWindow = makeWindow()
        let targets = PopoverScrollTargets()
        targets.registerVolumeControl(makeControlView(in: window))

        XCTAssertFalse(
            targets.containsVolumeControl(at: NSPoint(x: 100, y: 70), in: otherWindow)
        )
        XCTAssertFalse(
            targets.containsVolumeControl(at: NSPoint(x: 100, y: 70), in: nil)
        )
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
    }

    private func makeControlView(in window: NSWindow) -> NSView {
        let control = NSView(frame: NSRect(x: 40, y: 60, width: 200, height: 30))
        window.contentView?.addSubview(control)
        return control
    }
}
