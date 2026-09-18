import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The picture-card pickers hide the system focus effect so their selection ring
/// is the only ring on screen. These tests pin the keyboard path that stays
/// available, plus a render smoke test for every picker the panes use.
@MainActor
final class SettingsPictureRowTests: XCTestCase {
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

    func testPlacementPickerStillRendersItsOptionCards() {
        let hostingView = NSHostingView(
            rootView: SettingsPictureRow(
                "macwindow.on.rectangle",
                title: "Placement",
                selection: .constant(AppIconPlacement.menuBar),
                options: [AppIconPlacement.menuBar, .dock, .both],
                previewSize: CGSize(width: 62, height: 42),
                caption: { _ in "caption" },
                preview: { placement in AppIconPlacementPreview(placement: placement) }
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 120)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
        XCTAssertGreaterThan(hostingView.fittingSize.width, 0)
    }
}
