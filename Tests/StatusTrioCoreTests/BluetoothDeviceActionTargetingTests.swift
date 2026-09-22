import XCTest
@testable import StatusTrioCore

/// Every address this codebase holds is the raw `device_address` string from the
/// report, while IOBluetooth spells the same address its own way
/// (`AC:90:85:C2:9C:1F` against `ac-90-85-c2-9c-1f`). Matching only one side
/// turned a mistyped shape into a silent `completion(false)` that the UI reported
/// as a system rejection.
final class BluetoothDeviceActionTargetingTests: XCTestCase {
    private let reported = "ac-90-85-c2-9c-1f"

    func testRawColonSeparatedWantedMatchesIOBluetoothsDashSeparatedReport() {
        XCTAssertTrue(
            BluetoothDeviceActionTargeting.matches(
                reported: reported,
                wanted: "AC:90:85:C2:9C:1F"
            )
        )
    }

    func testColonSeparatedReportedMatchesDashSeparatedWanted() {
        XCTAssertTrue(
            BluetoothDeviceActionTargeting.matches(
                reported: "AC:90:85:C2:9C:1F",
                wanted: "ac-90-85-c2-9c-1f"
            )
        )
    }

    func testMatchingShapeAndCaseVariantsStillMatch() {
        XCTAssertTrue(
            BluetoothDeviceActionTargeting.matches(
                reported: reported,
                wanted: " ac:90:85:c2:9c:1f "
            )
        )
        XCTAssertTrue(
            BluetoothDeviceActionTargeting.matches(reported: "ac9085c29c1f", wanted: "AC9085C29C1F")
        )
    }

    func testADifferentDeviceDoesNotMatch() {
        XCTAssertFalse(
            BluetoothDeviceActionTargeting.matches(
                reported: reported,
                wanted: "D3:6D:6C:40:A3:2E"
            )
        )
        XCTAssertFalse(
            BluetoothDeviceActionTargeting.matches(
                reported: "D3-6D-6C-40-A3-2E",
                wanted: "AC:90:85:C2:9C:1F"
            )
        )
    }

    func testNilReportedDoesNotMatch() {
        XCTAssertFalse(
            BluetoothDeviceActionTargeting.matches(reported: nil, wanted: "AC:90:85:C2:9C:1F")
        )
    }

    func testEmptyReportedDoesNotMatch() {
        XCTAssertFalse(
            BluetoothDeviceActionTargeting.matches(reported: "", wanted: "AC:90:85:C2:9C:1F")
        )
    }

    func testEmptyWantedMatchesNothing() {
        let reports = [reported, "AC:90:85:C2:9C:1F", "", nil]
        for report in reports {
            XCTAssertFalse(
                BluetoothDeviceActionTargeting.matches(reported: report, wanted: ""),
                "an empty request must never target \(report ?? "nil")"
            )
        }
    }

    func testNonHexWantedMatchesNothing() {
        let reports = [reported, "AC:90:85:C2:9C:1F", "", nil]
        for wanted in ["zz-zz-zz", "::::", "   "] {
            for report in reports {
                XCTAssertFalse(
                    BluetoothDeviceActionTargeting.matches(reported: report, wanted: wanted),
                    "\(wanted) is not an address and must not target \(report ?? "nil")"
                )
            }
        }
    }
}
