import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// A device row is one line, whatever it is showing. The confirmation of an
/// input device's disconnect and the spinner of an action in flight both live in
/// the row's trailing area, and neither may wrap or push a control out of the
/// 330-point panel — not even for the longest paired-device name this Mac has.
@MainActor
final class BluetoothDeviceRowLayoutTests: XCTestCase {
    func testTheConfirmingRowStaysOnOneLine() async throws {
        let device = BluetoothDevice(
            id: "AA:00:00:00:00:01",
            name: "EDIFIER LolliPods 2022版",
            kind: .peripheral,
            isConnected: true
        )

        for language in [AppLanguage.english, .simplifiedChinese] {
            let plain = try await renderRow(language: language, device: device)
            let confirming = try await renderRow(
                language: language,
                device: device,
                isConfirmingDisconnect: true
            )

            XCTAssertEqual(confirming.width, 330, accuracy: 0.5)
            XCTAssertEqual(
                confirming.height,
                plain.height,
                accuracy: 1,
                "the confirmation must stay on the row's single line in \(language.rawValue)"
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

        XCTAssertEqual(connecting.width, 330, accuracy: 0.5)
        XCTAssertEqual(
            connecting.height,
            plain.height,
            accuracy: 1,
            "an action in flight must stay on the row's single line"
        )
    }

    /// Renders one row at the width the panel gives it: the popover is 330 wide
    /// with 14 points of padding on each side, so the row itself gets 302.
    private func renderRow(
        language: AppLanguage,
        device: BluetoothDevice,
        batteryLevels: [String: BluetoothBatteryLevel] = [:],
        actionState: BluetoothDeviceActionState? = nil,
        isConfirmingDisconnect: Bool = false
    ) async throws -> NSSize {
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
        return hosting.fittingSize
    }
}
