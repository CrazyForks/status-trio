import XCTest
@testable import StatusTrioCore

final class PopupVolumeScrollAdjustmentTests: XCTestCase {
    func testPreciseScrollMapsDistanceContinuously() throws {
        let adjustment = PopupVolumeScrollAdjustment()

        let small = try XCTUnwrap(
            adjustment.volumeDelta(deltaY: 4, isPrecise: true)
        )
        XCTAssertEqual(small, 0.008, accuracy: 0.000_001)

        let reverse = try XCTUnwrap(
            adjustment.volumeDelta(deltaY: -2.5, isPrecise: true)
        )
        XCTAssertEqual(reverse, -0.005, accuracy: 0.000_001)
    }

    func testPreciseScrollKeepsFractionalVolumeWithoutStepping() throws {
        let adjustment = PopupVolumeScrollAdjustment()

        let first = try XCTUnwrap(
            adjustment.volumeDelta(deltaY: 1, isPrecise: true)
        )
        let second = try XCTUnwrap(
            adjustment.volumeDelta(deltaY: 9, isPrecise: true)
        )

        XCTAssertEqual(first + second, 0.02, accuracy: 0.000_001)
    }

    func testDiscreteWheelScrollUsesLineDeltaAsStepCount() throws {
        let adjustment = PopupVolumeScrollAdjustment()

        let increase = try XCTUnwrap(
            adjustment.volumeDelta(deltaY: 1, isPrecise: false)
        )
        XCTAssertEqual(increase, 0.02, accuracy: 0.000_001)

        let decrease = try XCTUnwrap(
            adjustment.volumeDelta(deltaY: -2, isPrecise: false)
        )
        XCTAssertEqual(decrease, -0.04, accuracy: 0.000_001)
    }

    func testInvalidAndZeroDeltasAreIgnored() {
        let adjustment = PopupVolumeScrollAdjustment()

        XCTAssertNil(adjustment.volumeDelta(deltaY: .nan, isPrecise: true))
        XCTAssertNil(adjustment.volumeDelta(deltaY: .infinity, isPrecise: true))
        XCTAssertNil(adjustment.volumeDelta(deltaY: -.infinity, isPrecise: true))
        XCTAssertNil(adjustment.volumeDelta(deltaY: 0, isPrecise: true))
        XCTAssertNil(adjustment.volumeDelta(deltaY: 0, isPrecise: false))
    }
}
