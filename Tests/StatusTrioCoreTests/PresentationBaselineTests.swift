import XCTest
@testable import StatusTrioCore

final class PresentationBaselineTests: XCTestCase {
    func testDotBucketAndSignalBucketBaseline() {
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -61), 2)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -62), 2)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.51, isMuted: false), 3)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.74, isMuted: false), 3)
    }

    func testSharedSnapshotFixtureKeepsItsPresentationInputs() {
        let snapshot = PresentationFixtures.snapshot(rssi: -79, scalar: 0.74, muted: true)

        XCTAssertEqual(snapshot.battery.rawPercentage, 68)
        XCTAssertEqual(snapshot.battery.isPresent, true)
        XCTAssertEqual(snapshot.wifi.state, .connected)
        XCTAssertEqual(snapshot.wifi.rssi, -79)
        XCTAssertEqual(snapshot.connection, .wifi)
        XCTAssertEqual(snapshot.volume.scalar, 0.74)
        XCTAssertEqual(snapshot.volume.isMuted, true)
        XCTAssertEqual(snapshot.volume.deviceName, "Output")
    }

    func testSharedBluetoothDeviceUsesSheetHardwareFixture() {
        XCTAssertEqual(PresentationFixtures.bluetoothDevice, SheetFixtures.bluetoothDevice)
        XCTAssertEqual(PresentationFixtures.bluetoothDevice.transport, .bluetooth)
    }
}
