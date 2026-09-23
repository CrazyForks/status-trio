import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The picture-card pickers hide the system focus effect so their selection ring
/// is the only ring on screen. These tests pin the keyboard path that stays
/// available, plus a render smoke test for every picker the panes use.
@MainActor
final class SettingsPictureRowTests: XCTestCase {
    func testAppIconChoiceCardsUseTheSharedPreviewSize() {
        XCTAssertEqual(
            SettingsMetrics.appIconPictureOptionPreviewSize,
            CGSize(width: 64, height: 42)
        )
    }

    func testArrowKeySelectionWrapsAtBothEnds() {
        let options: [AppIconPlacement] = [.menuBar, .dock, .both]

        XCTAssertEqual(
            SettingsPictureRowSelection.wrapped(in: options, from: .menuBar, offset: -1),
            .both
        )
        XCTAssertEqual(
            SettingsPictureRowSelection.wrapped(in: options, from: .both, offset: 1),
            .menuBar
        )
        XCTAssertEqual(
            SettingsPictureRowSelection.wrapped(in: options, from: .dock, offset: 1),
            .both
        )
    }

    func testArrowKeySelectionIgnoresUnknownAndEmptyOptionLists() {
        XCTAssertNil(
            SettingsPictureRowSelection.wrapped(
                in: [AppIconPlacement](),
                from: .menuBar,
                offset: 1
            )
        )
        XCTAssertNil(
            SettingsPictureRowSelection.wrapped(
                in: [RingStrokeStyle.light, .regular],
                from: .bold,
                offset: 1
            )
        )
    }

    func testDockBackgroundOptionsHaveDistinctSettingsSymbols() {
        XCTAssertEqual(
            DockIconBackgroundPreference.allCases.map(\.settingsSymbol),
            ["circle.lefthalf.filled", "moon.fill", "sun.max.fill"]
        )
    }

    func testPlacementPickerStillRendersItsOptionCards() {
        let hostingView = NSHostingView(
            rootView: SettingsPictureRow(
                "macwindow.on.rectangle",
                title: "Placement",
                selection: .constant(AppIconPlacement.menuBar),
                options: [AppIconPlacement.menuBar, .dock, .both],
                previewSize: SettingsMetrics.appIconPictureOptionPreviewSize,
                caption: { _ in "caption" },
                preview: { placement in AppIconPlacementPreview(placement: placement) }
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 120)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
        XCTAssertGreaterThan(hostingView.fittingSize.width, 0)
    }

    func testSettingsHintRowRendersAtFullRowWidth() {
        let hostingView = NSHostingView(
            rootView: SettingsHintRow(text: "A readable hint below the choices.")
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 60)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostingView.fittingSize.width, 0)
        XCTAssertLessThan(hostingView.fittingSize.height, 44)
    }

    func testDockBackgroundPickerRendersChoiceSymbols() {
        let hostingView = NSHostingView(
            rootView: SettingsPictureRow(
                "dock.rectangle",
                title: "Dock Icon Background",
                subtitle: "Choose the appearance used by Dock icons.",
                optionSymbol: { $0.settingsSymbol },
                selection: .constant(DockIconBackgroundPreference.system),
                options: DockIconBackgroundPreference.allCases,
                previewSize: SettingsMetrics.appIconPictureOptionPreviewSize,
                caption: { $0.rawValue.capitalized },
                preview: { _ in RoundedRectangle(cornerRadius: 6) }
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 140)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
        XCTAssertGreaterThan(hostingView.fittingSize.width, 0)
    }
}
