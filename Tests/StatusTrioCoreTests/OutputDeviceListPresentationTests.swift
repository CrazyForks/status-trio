import CoreAudio
import XCTest
@testable import StatusTrioCore

final class OutputDeviceListPresentationTests: XCTestCase {
    func testCollapsedListLimitsVisibleDevices() {
        let devices = makeDevices(count: 6)

        let visibleDevices = OutputDeviceListPresentation.visibleDevices(
            from: devices,
            limit: 5,
            isExpanded: false
        )

        XCTAssertEqual(visibleDevices.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertTrue(
            OutputDeviceListPresentation.canToggleExpansion(
                for: devices,
                limit: 5
            )
        )
    }

    func testExpandedListShowsEveryDevice() {
        let devices = makeDevices(count: 6)

        let visibleDevices = OutputDeviceListPresentation.visibleDevices(
            from: devices,
            limit: 5,
            isExpanded: true
        )

        XCTAssertEqual(visibleDevices.map(\.id), [1, 2, 3, 4, 5, 6])
    }

    func testUnlimitedListDoesNotOfferExpansion() {
        let devices = makeDevices(count: 6)

        XCTAssertEqual(
            OutputDeviceListPresentation.visibleDevices(
                from: devices,
                limit: nil,
                isExpanded: false
            ).map(\.id),
            [1, 2, 3, 4, 5, 6]
        )
        XCTAssertFalse(
            OutputDeviceListPresentation.canToggleExpansion(
                for: devices,
                limit: nil
            )
        )
    }

    private func makeDevices(count: Int) -> [AudioOutputDevice] {
        (1...count).map { index in
            AudioOutputDevice(
                id: AudioDeviceID(index),
                name: "Device \(index)",
                uid: "device-\(index)",
                isCurrent: index == 1
            )
        }
    }
}
