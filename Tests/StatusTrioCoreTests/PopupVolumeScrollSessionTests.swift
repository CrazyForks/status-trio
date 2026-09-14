import XCTest
@testable import StatusTrioCore

final class PopupVolumeScrollSessionTests: XCTestCase {
    func testSessionStartsFromFallbackAndContinuesFromLocalTarget() throws {
        var session = PopupVolumeScrollSession()

        let initial = try XCTUnwrap(
            session.scalar(at: 1, fallback: 0.4)
        )
        XCTAssertEqual(initial, 0.4, accuracy: 0.000_001)

        let increased = session.applying(delta: 0.2, to: initial)
        XCTAssertEqual(increased, 0.6, accuracy: 0.000_001)

        let continued = try XCTUnwrap(
            session.scalar(at: 1.5, fallback: 0.1)
        )
        XCTAssertEqual(continued, 0.6, accuracy: 0.000_001)
    }

    func testSessionResetsToFallbackAfterInactivity() throws {
        var session = PopupVolumeScrollSession()
        let initial = try XCTUnwrap(session.scalar(at: 1, fallback: 0.4))
        _ = session.applying(delta: 0.2, to: initial)

        let refreshed = try XCTUnwrap(
            session.scalar(
                at: 1 + PopupVolumeScrollSession.timeout + 0.001,
                fallback: 0.8
            )
        )
        XCTAssertEqual(refreshed, 0.8, accuracy: 0.000_001)
    }

    func testSessionClampsAdjustmentsToValidVolumeRange() throws {
        var session = PopupVolumeScrollSession()
        let initial = try XCTUnwrap(session.scalar(at: 1, fallback: 0.99))
        XCTAssertEqual(session.applying(delta: 0.5, to: initial), 1)

        session.reset()
        let lowered = try XCTUnwrap(session.scalar(at: 2, fallback: 0.01))
        XCTAssertEqual(session.applying(delta: -0.5, to: lowered), 0)
    }

    func testSessionRequestsUnmuteOnlyOnceForIncrease() {
        var session = PopupVolumeScrollSession()

        XCTAssertTrue(
            session.shouldUnmute(isMuted: true, isIncreasing: true)
        )
        XCTAssertFalse(
            session.shouldUnmute(isMuted: true, isIncreasing: true)
        )
        XCTAssertFalse(
            session.shouldUnmute(isMuted: false, isIncreasing: true)
        )
        XCTAssertFalse(
            session.shouldUnmute(isMuted: true, isIncreasing: false)
        )
    }

    func testResetAllowsUnmuteRequestInNextSession() {
        var session = PopupVolumeScrollSession()
        XCTAssertTrue(
            session.shouldUnmute(isMuted: true, isIncreasing: true)
        )

        session.reset()

        XCTAssertTrue(
            session.shouldUnmute(isMuted: true, isIncreasing: true)
        )
    }
}
