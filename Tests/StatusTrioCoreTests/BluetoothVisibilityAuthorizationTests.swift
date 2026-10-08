import XCTest
@testable import StatusTrioCore

final class BluetoothVisibilityAuthorizationTests: XCTestCase {
    func testTrustedAuthorizationUsesTheChangedCandidateSnapshot() {
        let first = AppleDeviceCandidate(
            id: .trustedDevice("first"), name: "First", model: "iPhone18,1",
            transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
        )
        let second = AppleDeviceCandidate(
            id: .trustedDevice("second"), name: "Second", model: "iPhone18,1",
            transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
        )

        let authorized = BluetoothVisibilityAuthorization.trustedIDs(
            visibleIDs: [first.id, second.id],
            currentCandidates: [second]
        )

        XCTAssertEqual(authorized, [second.id])
    }

    func testNearbyAuthorizationUsesTheChangedSettingsSnapshot() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertEqual(
            BluetoothVisibilityAuthorization.nearbyIDs(
                visibleIDs: [id],
                showsBatteryLevels: true,
                showsAppleDevicesAndBattery: false,
                showsList: true
            ),
            []
        )
        XCTAssertEqual(
            BluetoothVisibilityAuthorization.nearbyIDs(
                visibleIDs: [id],
                showsBatteryLevels: true,
                showsAppleDevicesAndBattery: true,
                showsList: true
            ),
            [id]
        )
    }
}
