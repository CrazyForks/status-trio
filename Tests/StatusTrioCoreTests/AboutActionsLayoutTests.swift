import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class AboutActionsLayoutTests: XCTestCase {
    func testCheckForUpdatesButtonDoesNotShareARowWithLinks() throws {
        let suite = "StatusTrioCoreTests.AboutActions.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }

        let localization = Localization(
            defaults: defaults,
            preferredLanguages: [AppLanguage.simplifiedChinese.rawValue]
        )
        let linksOnlyHeight = renderedHeight(
            canCheckForUpdates: false,
            localization: localization
        )
        let withUpdateHeight = renderedHeight(
            canCheckForUpdates: true,
            localization: localization
        )

        XCTAssertGreaterThanOrEqual(
            withUpdateHeight,
            linksOnlyHeight + 20,
            "The update button should add its own row below the links"
        )
    }

    private func renderedHeight(
        canCheckForUpdates: Bool,
        localization: Localization
    ) -> CGFloat {
        let availableWidth = SettingsView.width
            - SettingsView.sidebarWidth
            - SettingsMetrics.rowPaddingH * 2
        let view = AboutActionsView(
            canCheckForUpdates: canCheckForUpdates,
            onCheckForUpdates: {}
        )
            .environmentObject(localization)
            .frame(width: availableWidth)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: availableWidth, height: 0)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }
}
