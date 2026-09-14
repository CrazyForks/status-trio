import XCTest
@testable import StatusTrioCore

final class NetworkConnectionTests: XCTestCase {
    func testDisconnectedPathIsOfflineEvenWhenInterfacesReportAvailability() {
        XCTAssertEqual(
            NetworkConnection.resolve(connected: false, wired: true, wireless: true),
            .offline
        )
    }

    func testWiredConnectionTakesPriorityOverWireless() {
        XCTAssertEqual(
            NetworkConnection.resolve(connected: true, wired: true, wireless: true),
            .ethernet
        )
    }

    func testWirelessConnectionIsUsedWhenWiredIsUnavailable() {
        XCTAssertEqual(
            NetworkConnection.resolve(connected: true, wired: false, wireless: true),
            .wifi
        )
    }

    func testConnectedPathWithoutWiredOrWirelessIsOther() {
        XCTAssertEqual(
            NetworkConnection.resolve(connected: true, wired: false, wireless: false),
            .other
        )
    }
}
