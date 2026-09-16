import CoreAudio
import XCTest
@testable import StatusTrioCore

final class StatusBarRenderCacheTests: XCTestCase {
    func testSameRenderKeyIsSuppressed() {
        var cache = StatusBarRenderCache()
        let key = makeKey(volumeScalar: 0.5, appearance: "darkAqua")

        XCTAssertTrue(cache.shouldRender(key))
        XCTAssertFalse(cache.shouldRender(key))
    }

    func testAppearanceChangeRendersAgain() {
        var cache = StatusBarRenderCache()
        let aquaKey = makeKey(appearance: "aqua")
        let darkAquaKey = makeKey(appearance: "darkAqua")

        XCTAssertTrue(cache.shouldRender(aquaKey))
        XCTAssertTrue(cache.shouldRender(darkAquaKey))
        XCTAssertFalse(cache.shouldRender(darkAquaKey))
    }

    func testOutputDevicesDoNotInvalidateMenuBarStatus() {
        let first = makeSnapshot(outputDevices: [makeDevice(id: 1, uid: "one")])
        let second = makeSnapshot(outputDevices: [makeDevice(id: 2, uid: "two")])

        XCTAssertNotEqual(first.volume, second.volume)
        XCTAssertEqual(MenuBarStatus(snapshot: first), MenuBarStatus(snapshot: second))
    }

    private func makeKey(
        volumeScalar: Double = 0.5,
        appearance: String
    ) -> StatusBarRenderKey {
        StatusBarRenderKey(
            status: MenuBarStatus(
                snapshot: makeSnapshot(volumeScalar: volumeScalar)
            ),
            iconSize: 28,
            options: .standard,
            connectionOptions: .standard,
            appearanceName: appearance
        )
    }

    private func makeSnapshot(
        volumeScalar: Double = 0.5,
        outputDevices: [AudioOutputDevice] = []
    ) -> StatusSnapshot {
        StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            connection: .wifi,
            volume: VolumeStatus(
                scalar: volumeScalar,
                isMuted: false,
                deviceName: "Speakers",
                outputDevices: outputDevices
            )
        )
    }

    private func makeDevice(id: AudioDeviceID, uid: String) -> AudioOutputDevice {
        AudioOutputDevice(
            id: id,
            name: uid,
            uid: uid,
            isCurrent: id == 1,
            volume: 0.5
        )
    }
}
