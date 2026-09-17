import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class AboutActionsLayoutTests: XCTestCase {
    func testCheckForUpdatesButtonDoesNotShareARowWithLinks() throws {
        let suite = "StatusTrioCoreTests.AboutActions.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let localization = Localization(
            defaults: defaults,
            preferredLanguages: [AppLanguage.simplifiedChinese.rawValue]
        )
        let availableWidth = SettingsView.width
            - SettingsView.sidebarWidth
            - SettingsMetrics.rowPaddingH * 2
        let view = AboutActionsView(canCheckForUpdates: true, onCheckForUpdates: {})
            .environmentObject(localization)
            .frame(width: availableWidth)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: availableWidth, height: 200)
        hostingView.layoutSubtreeIfNeeded()

        let renderedControls = descendants(of: hostingView)
        XCTAssertEqual(renderedControls.count, 5)

        let linkControls = renderedControls.prefix(4)
        let updateControl = try XCTUnwrap(renderedControls.last)
        for linkControl in linkControls {
            XCTAssertGreaterThan(linkControl.frame.width, 0)
            XCTAssertGreaterThan(linkControl.frame.height, 0)
            let sharesRow = linkControl.frame.minY < updateControl.frame.maxY
                && updateControl.frame.minY < linkControl.frame.maxY
            XCTAssertFalse(
                sharesRow,
                "A link should not share a row with the update button"
            )
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.reduce(into: view.subviews) { result, subview in
            result.append(contentsOf: descendants(of: subview))
        }
    }
}
