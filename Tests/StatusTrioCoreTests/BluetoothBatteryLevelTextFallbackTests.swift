import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

final class BluetoothBatteryLevelTextFallbackTests: XCTestCase {
    func testMissingSymbolFallsBackToItsTextLabel() {
        // `airpods.chargingcase` was introduced after Ventura. The image lookup
        // is injectable so this test can exercise the absence path even on a
        // newer host where the symbol exists.
        let text = BluetoothBatteryLevelText.drawn(
            [.symbol(name: "airpods.chargingcase", label: "Case")],
            symbolImage: { _ in nil }
        )

        XCTAssertTrue(String(describing: text).contains("Case"))
        XCTAssertFalse(String(describing: text).contains("airpods.chargingcase"))
    }

    func testAvailableSymbolStillKeepsThePercentageText() {
        let text = BluetoothBatteryLevelText.drawn(
            [.symbol(name: "battery.100", label: "Case"), .text(" 70%")],
            symbolImage: { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        )

        XCTAssertNotEqual(text, Text(verbatim: "Case 70%"))
    }
}
