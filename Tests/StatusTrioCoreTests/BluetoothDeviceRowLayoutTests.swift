import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// A device row is one line, whatever it is showing. The confirmation of an
/// input device's disconnect and the spinner of an action in flight both live in
/// the row's trailing area, and neither may wrap or push a control out of the
/// 330-point panel — not even for the longest paired-device name this Mac has.
///
/// Height alone cannot tell a drawn prompt from an empty line box of the same
/// height, so each case also asks the rendered view what it actually drew. The
/// accessibility tree carries nothing in this harness: `NSHostingView` reports
/// no children and no labels here, in or out of a window, and
/// `accessibilityHitTest` only ever answers with the hosting view itself. The
/// questions therefore go to the AppKit views SwiftUI does create — one
/// focus-ring host per `Button`, and a real `NSProgressIndicator` behind the
/// row's `ProgressView`.
@MainActor
final class BluetoothDeviceRowLayoutTests: XCTestCase {
    func testTheConfirmingRowStaysOnOneLine() async throws {
        let device = BluetoothDevice(
            id: "AA:00:00:00:00:01",
            name: "EDIFIER LolliPods 2022版",
            kind: .peripheral(.unclassified),
            isConnected: true
        )
        // The phrase is asserted on a short name: the leading block only grows
        // into the phrase's space when the phrase is missing if the name has
        // room to grow, and that is exactly what this assertion has to catch.
        let shortNamedDevice = BluetoothDevice(
            id: device.id,
            name: "MX Master 3",
            kind: .peripheral(.mouse),
            isConnected: true
        )

        for language in [AppLanguage.english, .simplifiedChinese] {
            let plain = try await renderRow(language: language, device: device)
            let confirming = try await renderRow(
                language: language,
                device: device,
                isConfirmingDisconnect: true
            )

            XCTAssertEqual(
                confirming.size.height,
                plain.size.height,
                accuracy: 1,
                "the confirmation must stay on the row's single line in \(language.rawValue)"
            )

            // The prompt replaces the row's one button with the Disconnect and
            // Cancel buttons, so the rendered view must carry two controls where
            // the plain row carries one. An empty same-height line box would
            // pass the height check above and fail this one.
            XCTAssertEqual(
                plain.controls.count,
                1,
                "the plain row is one button in \(language.rawValue)"
            )
            XCTAssertEqual(
                confirming.controls.count,
                2,
                "the confirming row must render Disconnect and Cancel in \(language.rawValue)"
            )

            // The phrase is plain text with no view of its own, so it is
            // asserted where it is drawn: the ink between the leading block and
            // the Disconnect button the row rendered. The window stays inside
            // the phrase's own box, so a missing phrase leaves it blank.
            let prompt = try await renderRow(
                language: language,
                device: shortNamedDevice,
                isConfirmingDisconnect: true
            )
            let disconnect = try XCTUnwrap(
                prompt.controls.first,
                "the confirming row rendered no controls in \(language.rawValue)"
            )
            XCTAssertTrue(
                prompt.hasInk(from: disconnect.minX - 60, to: disconnect.minX - 12),
                "the confirming row must draw the confirmation phrase in \(language.rawValue)"
            )
        }
    }

    func testTheInFlightRowStaysOnOneLine() async throws {
        let device = BluetoothDevice(
            id: "AA:00:00:00:00:01",
            name: "EDIFIER LolliPods 2022版",
            kind: .audio,
            isConnected: false
        )

        let plain = try await renderRow(language: .english, device: device)
        let connecting = try await renderRow(
            language: .english,
            device: device,
            actionState: .connecting
        )

        XCTAssertEqual(
            connecting.size.height,
            plain.size.height,
            accuracy: 1,
            "an action in flight must stay on the row's single line"
        )

        // The spinner is the one thing the in-flight row adds to the same line
        // box, and the only AppKit view the row hosts besides its button. A
        // label drawn without its spinner would pass the height check above and
        // fail this one.
        XCTAssertEqual(plain.spinners, 0, "a plain row draws no spinner")
        XCTAssertEqual(connecting.spinners, 1, "the in-flight row must draw its spinner")
    }

    /// An ordinary whole-device level is drawn inline, on the name's line, so a
    /// mouse or keyboard with a single percentage stays exactly as tall as the same
    /// device with nothing to draw. This is the regression guard for every device
    /// that is not a component-battery one.
    func testAnInlineLevelKeepsTheRowHeightUnchanged() async throws {
        let device = rowDevice(name: "MX Keys")

        let plain = try await renderRow(language: .english, device: device)
        let inlineLevel = try await renderRow(
            language: .english,
            device: device,
            batteryLevels: levels(main: 84)
        )

        XCTAssertEqual(
            inlineLevel.size.height,
            plain.size.height,
            accuracy: 1,
            "a single whole-device level must share the name's line, not add one"
        )
    }

    /// A component device moves its levels to a second line and is therefore
    /// taller than an inline row — by exactly the one line the height model
    /// budgets, so the list can trust it.
    func testAComponentRowIsTallerThanAnInlineRow() async throws {
        let device = rowDevice(name: "Ling's AirPods Pro")

        let inlineRow = try await renderRow(language: .english, device: device)
        let componentRow = try await renderRow(
            language: .english,
            device: device,
            batteryLevels: levels(left: 85, right: 80, caseLevel: 70)
        )

        XCTAssertGreaterThan(
            componentRow.size.height,
            inlineRow.size.height,
            "component levels have to take their own line"
        )
        XCTAssertEqual(
            componentRow.size.height - inlineRow.size.height,
            BluetoothDeviceRowMetrics.componentHeight - BluetoothDeviceRowMetrics.inlineHeight,
            accuracy: 1,
            "the second line is one line tall"
        )
    }

    /// A single component channel is enough for the second line. This pins the
    /// rule against a future change back to `channelCount >= 2`: a lone earbud
    /// reporting only `left` mid-connection must not flip the row between one and
    /// two lines as its partner reports in.
    func testASingleComponentChannelStillUsesTheComponentRow() async throws {
        let device = rowDevice(name: "Sony WF-1000XM6")

        let inlineRow = try await renderRow(language: .english, device: device)
        let leftOnly = try await renderRow(
            language: .english,
            device: device,
            batteryLevels: levels(left: 85)
        )
        let full = try await renderRow(
            language: .english,
            device: device,
            batteryLevels: levels(left: 85, right: 80, caseLevel: 70)
        )

        XCTAssertGreaterThan(
            leftOnly.size.height,
            inlineRow.size.height,
            "one component channel still takes the component row"
        )
        XCTAssertEqual(
            leftOnly.size.height,
            full.size.height,
            accuracy: 1,
            "a lone earbud sits at the same two-line height as a full set"
        )
    }

    /// With the level on its own line the name gets the whole width back: a long
    /// name truncates on the first line rather than wrapping or crowding the
    /// battery out. The row stays at the two-line component height a short name
    /// produces, and the battery still adds exactly one line over an inline row of
    /// the same long name — proof the level was neither pushed off nor wrapped.
    func testALongNameTruncatesWithoutPushingTheBatteryAway() async throws {
        let longName = "EDIFIER LolliPods 2022版 Ultra Long Device Name"
        let device = rowDevice(name: longName)

        let shortComponent = try await renderRow(
            language: .english,
            device: rowDevice(name: "Air"),
            batteryLevels: levels(left: 85, right: 80, caseLevel: 70)
        )
        let longInline = try await renderRow(language: .english, device: device)
        let longComponent = try await renderRow(
            language: .english,
            device: device,
            batteryLevels: levels(left: 85, right: 80, caseLevel: 70)
        )

        XCTAssertEqual(
            longComponent.size.height,
            shortComponent.size.height,
            accuracy: 1,
            "a long name must truncate, not wrap, and keep the two-line height"
        )
        XCTAssertEqual(
            longComponent.size.height - longInline.size.height,
            BluetoothDeviceRowMetrics.componentHeight - BluetoothDeviceRowMetrics.inlineHeight,
            accuracy: 1,
            "the battery keeps its own line even beside a truncated name"
        )
    }

    /// A component device that is mid-action still lays out its levels on the
    /// second line: the spinner lives on the name's line, so the row neither grows
    /// nor loses its battery line, and it draws exactly one spinner.
    func testAConnectingComponentRowStaysTwoLinesAndSpinsOnce() async throws {
        let device = rowDevice(name: "AirPods Pro", isConnected: false)

        let resting = try await renderRow(
            language: .english,
            device: device,
            batteryLevels: levels(left: 85, right: 80, caseLevel: 70)
        )
        let connecting = try await renderRow(
            language: .english,
            device: device,
            batteryLevels: levels(left: 85, right: 80, caseLevel: 70),
            actionState: .connecting
        )

        XCTAssertEqual(
            connecting.size.height,
            resting.size.height,
            accuracy: 1,
            "an action in flight must not disturb the component row's two lines"
        )
        XCTAssertEqual(connecting.spinners, 1, "the in-flight component row draws one spinner")
    }

    /// The disconnect confirmation is a temporary operation state that needs the
    /// whole horizontal width, so it stays on one line even for a component
    /// device: the row collapses to the same single-line confirmation height an
    /// ordinary device produces, and it still renders both Disconnect and Cancel.
    func testTheConfirmationCollapsesAComponentRowToOneLine() async throws {
        let device = rowDevice(name: "AirPods Pro")

        let ordinaryConfirmation = try await renderRow(
            language: .english,
            device: device,
            isConfirmingDisconnect: true
        )
        let componentConfirmation = try await renderRow(
            language: .english,
            device: device,
            batteryLevels: levels(left: 85, right: 80, caseLevel: 70),
            isConfirmingDisconnect: true
        )

        XCTAssertEqual(
            componentConfirmation.size.height,
            ordinaryConfirmation.size.height,
            accuracy: 1,
            "a confirming component device collapses to the single-line confirmation height"
        )
        XCTAssertEqual(
            componentConfirmation.controls.count,
            2,
            "the confirming component row still renders Disconnect and Cancel"
        )
    }

    private func rowDevice(name: String, isConnected: Bool = true) -> BluetoothDevice {
        BluetoothDevice(
            id: "AA:00:00:00:00:01",
            name: name,
            kind: .audio,
            isConnected: isConnected
        )
    }

    private func levels(
        main: Int? = nil,
        left: Int? = nil,
        right: Int? = nil,
        caseLevel: Int? = nil
    ) -> [String: BluetoothBatteryLevel] {
        [
            BluetoothBatteryReader.normalizedAddress("AA:00:00:00:00:01"): BluetoothBatteryLevel(
                deviceAddress: "AA:00:00:00:00:01",
                main: main,
                left: left,
                right: right,
                caseLevel: caseLevel
            )
        ]
    }

    /// One rendered row, as the test can ask about it.
    private struct RenderedRow {
        /// The size the row asks the panel for.
        let size: NSSize

        /// One rect per `Button` SwiftUI rendered, in the row's coordinates, in
        /// their reading order. SwiftUI gives each button a focus-ring host
        /// view, and that is the handle this harness has on a rendered control.
        let controls: [NSRect]

        /// How many `NSProgressIndicator`s the row rendered — the `ProgressView`
        /// of an action in flight.
        let spinners: Int

        let bitmap: NSBitmapImageRep
        let scale: CGFloat

        /// Whether the row drew anything in the horizontal band `start..<end`,
        /// in the row's coordinates.
        func hasInk(from start: CGFloat, to end: CGFloat) -> Bool {
            let lower = max(0, Int((start * scale).rounded(.down)))
            let upper = min(bitmap.pixelsWide - 1, Int((end * scale).rounded(.up)))
            guard lower <= upper else { return false }
            for x in lower...upper {
                for y in 0..<bitmap.pixelsHigh {
                    guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                    let luminance = 0.299 * color.redComponent
                        + 0.587 * color.greenComponent
                        + 0.114 * color.blueComponent
                    if luminance < 0.9 { return true }
                }
            }
            return false
        }
    }

    /// Renders one row at the width the panel gives it: the popover is 330 wide
    /// with 14 points of padding on each side, so the row itself gets 302.
    private func renderRow(
        language: AppLanguage,
        device: BluetoothDevice,
        batteryLevels: [String: BluetoothBatteryLevel] = [:],
        actionState: BluetoothDeviceActionState? = nil,
        isConfirmingDisconnect: Bool = false
    ) async throws -> RenderedRow {
        let suite = "StatusTrioCoreTests.BluetoothDeviceRow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))

        let view = BluetoothDeviceRow(
            device: device,
            batteryLevels: batteryLevels,
            actionState: actionState,
            isConfirmingDisconnect: isConfirmingDisconnect,
            onPerformAction: {},
            onRequestDisconnect: {},
            onCancelDisconnect: {}
        )
        .padding(14)
        .frame(width: 330)
        .background(Color(white: 0.96))
        .environmentObject(localization)
        .environment(\.colorScheme, .light)

        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

        var controls: [NSRect] = []
        var spinners = 0
        var pending = hosting.subviews
        while let subview = pending.popLast() {
            if String(describing: type(of: subview)).contains("FocusRing") {
                controls.append(subview.convert(subview.bounds, to: hosting))
            }
            if subview is NSProgressIndicator {
                spinners += 1
            }
            pending.append(contentsOf: subview.subviews)
        }

        return RenderedRow(
            size: hosting.fittingSize,
            controls: controls.sorted { $0.minX < $1.minX },
            spinners: spinners,
            bitmap: bitmap,
            scale: CGFloat(bitmap.pixelsWide) / hosting.bounds.width
        )
    }
}
