import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The custom panel replaces `NSPopover` (issue #186). These pin the two pieces
/// that no longer come from AppKit: the SwiftUI content's sizing signal and the
/// window's key-window capability.
@MainActor
final class StatusPanelContentTests: XCTestCase {
    private struct FixedContent: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Header")
                Divider()
                Text("Body")
            }
            .padding(14)
            .frame(width: 330)
        }
    }

    func testHostingControllerReportsTheFitSizeOnLayout() {
        let host = StatusPanelHostingController(rootView: FixedContent())
        var reported: [NSSize] = []
        host.onLayout = { reported.append($0) }

        host.view.layoutSubtreeIfNeeded()
        host.viewDidLayout()

        XCTAssertEqual(reported.count, 1)
        XCTAssertEqual(reported.first?.width, 330)
        XCTAssertGreaterThan(reported.first?.height ?? 0, 0)
        XCTAssertEqual(reported.first, host.view.fittingSize)
    }

    func testWrapperReportsTheSameIntrinsicSize() {
        let host = StatusPanelHostingController(rootView: FixedContent())
        let wrapper = StatusPanelContentViewController(hostingController: host)

        let size = wrapper.intrinsicContentSize

        XCTAssertEqual(size.width, 330)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertEqual(size.width, host.view.fittingSize.width)
    }

    func testPanelCanBecomeKeyWithoutBecomingMain() {
        let panel = AnchoredStatusPanel()

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(panel.collectionBehavior.contains(.fullScreenAuxiliary), true)
        XCTAssertEqual(panel.collectionBehavior.contains(.canJoinAllSpaces), true)
    }
}
