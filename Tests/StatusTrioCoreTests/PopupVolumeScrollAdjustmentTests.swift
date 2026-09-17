import XCTest
@testable import StatusTrioCore

final class PopupVolumeScrollAdjustmentTests: XCTestCase {
    private let adjustment = PopupVolumeScrollAdjustment()

    func testScrollUpGestureRaisesVolumeWithNaturalScrolling() throws {
        // Natural scrolling reports a negative delta for a two-finger swipe up.
        let delta = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: -4,
                isPrecise: true,
                isDirectionInverted: true,
                direction: .up
            )
        )

        XCTAssertEqual(delta, 0.008, accuracy: 0.000_001)
    }

    func testScrollUpGestureRaisesVolumeWithoutNaturalScrolling() throws {
        let delta = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 4,
                isPrecise: true,
                isDirectionInverted: false,
                direction: .up
            )
        )

        XCTAssertEqual(delta, 0.008, accuracy: 0.000_001)
    }

    func testScrollDownPreferenceReversesTheGestureOnBothDevices() throws {
        let natural = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: -4,
                isPrecise: true,
                isDirectionInverted: true,
                direction: .down
            )
        )
        XCTAssertEqual(natural, -0.008, accuracy: 0.000_001)

        let classic = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 4,
                isPrecise: true,
                isDirectionInverted: false,
                direction: .down
            )
        )
        XCTAssertEqual(classic, -0.008, accuracy: 0.000_001)
    }

    func testPreciseScrollKeepsFractionalVolumeWithoutStepping() throws {
        let first = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 1,
                isPrecise: true,
                isDirectionInverted: false,
                direction: .up
            )
        )
        let second = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 9,
                isPrecise: true,
                isDirectionInverted: false,
                direction: .up
            )
        )

        XCTAssertEqual(first + second, 0.02, accuracy: 0.000_001)
    }

    func testDiscreteWheelScrollUsesLineDeltaAsStepCount() throws {
        let increase = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 1,
                isPrecise: false,
                isDirectionInverted: false,
                direction: .up
            )
        )
        XCTAssertEqual(increase, 0.02, accuracy: 0.000_001)

        let decrease = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: -2,
                isPrecise: false,
                isDirectionInverted: false,
                direction: .up
            )
        )
        XCTAssertEqual(decrease, -0.04, accuracy: 0.000_001)
    }

    func testBothDeviceSetupsCanReproduceTheOriginalMapping() throws {
        // 1.1.0 applied the raw delta, so each device setup reaches that
        // mapping through exactly one of the two choices.
        let classic = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 2.5,
                isPrecise: true,
                isDirectionInverted: false,
                direction: .up
            )
        )
        XCTAssertEqual(classic, 0.005, accuracy: 0.000_001)

        let natural = try XCTUnwrap(
            adjustment.volumeDelta(
                deltaY: 2.5,
                isPrecise: true,
                isDirectionInverted: true,
                direction: .down
            )
        )
        XCTAssertEqual(natural, 0.005, accuracy: 0.000_001)
    }

    func testInvalidAndZeroDeltasAreIgnored() {
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: .nan,
                isPrecise: true,
                isDirectionInverted: false,
                direction: .up
            )
        )
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: .infinity,
                isPrecise: true,
                isDirectionInverted: true,
                direction: .up
            )
        )
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: -.infinity,
                isPrecise: false,
                isDirectionInverted: false,
                direction: .down
            )
        )
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: 0,
                isPrecise: true,
                isDirectionInverted: false,
                direction: .up
            )
        )
        XCTAssertNil(
            adjustment.volumeDelta(
                deltaY: 0,
                isPrecise: false,
                isDirectionInverted: true,
                direction: .down
            )
        )
    }
}
