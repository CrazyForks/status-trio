import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The live menu bar simulation at the top of the icon panes must stay in place
/// while the option groups below it scroll.
@MainActor
final class SettingsPagePinningTests: XCTestCase {
    func testPinnedHeaderSitsOutsideTheScrollView() {
        let hostingView = makeHostingView(
            SettingsPage(pinnedHeader: {
                ProbeView(kind: .pinned)
            }) {
                ProbeView(kind: .content)
                    .frame(height: 2000)
            }
        )

        let pinned = findProbe(.pinned, in: hostingView)
        let content = findProbe(.content, in: hostingView)

        XCTAssertNotNil(pinned)
        XCTAssertNotNil(content)
        XCTAssertNil(
            enclosingScrollView(of: pinned),
            "The pinned header must not scroll with the page."
        )
        XCTAssertNotNil(
            enclosingScrollView(of: content),
            "The page content must live inside the scroll view."
        )
    }

    func testPinnedHeaderIsLaidOutAboveTheScrollView() throws {
        let hostingView = makeHostingView(
            SettingsPage(pinnedHeader: {
                ProbeView(kind: .pinned)
                    .frame(height: 40)
            }) {
                ProbeView(kind: .content)
                    .frame(height: 2000)
            }
        )

        let pinned = try XCTUnwrap(findProbe(.pinned, in: hostingView))
        let scrollView = try XCTUnwrap(enclosingScrollView(of: findProbe(.content, in: hostingView)))
        let pinnedFrame = pinned.convert(pinned.bounds, to: hostingView)
        let scrollFrame = scrollView.convert(scrollView.bounds, to: hostingView)

        // NSHostingView is flipped, so "above" means a smaller y there.
        if hostingView.isFlipped {
            XCTAssertLessThanOrEqual(
                pinnedFrame.maxY,
                scrollFrame.minY + 0.5,
                "The pinned header must be stacked above the scrolling content."
            )
        } else {
            XCTAssertGreaterThanOrEqual(
                pinnedFrame.minY,
                scrollFrame.maxY - 0.5,
                "The pinned header must be stacked above the scrolling content."
            )
        }
    }

    func testPagesWithoutAPinnedHeaderStillScrollTheirContent() {
        let hostingView = makeHostingView(
            SettingsPage {
                ProbeView(kind: .content)
                    .frame(height: 2000)
            }
        )

        XCTAssertNil(findProbe(.pinned, in: hostingView))
        XCTAssertNotNil(
            enclosingScrollView(of: findProbe(.content, in: hostingView)),
            "A page without a pinned header keeps its existing scrolling layout."
        )
    }

    private func makeHostingView<Content: View>(_ view: Content) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 530, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
    }

    private func findProbe(_ kind: ProbeKind, in root: NSView) -> NSView? {
        if let probe = root as? ProbeNSView, probe.kind == kind { return probe }
        for subview in root.subviews {
            if let found = findProbe(kind, in: subview) { return found }
        }
        return nil
    }

    private func enclosingScrollView(of view: NSView?) -> NSScrollView? {
        var current = view?.superview
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView { return scrollView }
            current = candidate.superview
        }
        return nil
    }
}

private enum ProbeKind {
    case pinned
    case content
}

private final class ProbeNSView: NSView {
    let kind: ProbeKind

    init(kind: ProbeKind) {
        self.kind = kind
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct ProbeView: NSViewRepresentable {
    let kind: ProbeKind

    func makeNSView(context: Context) -> ProbeNSView {
        ProbeNSView(kind: kind)
    }

    func updateNSView(_ nsView: ProbeNSView, context: Context) {}
}
