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

    func testBluetoothAudioOptionsChangeRendersAgain() {
        var cache = StatusBarRenderCache()
        let standard = makeKey(
            appearance: "darkAqua",
            bluetoothAudioOptions: .standard
        )
        let replacementEnabled = makeKey(
            appearance: "darkAqua",
            bluetoothAudioOptions: BluetoothAudioIconOptions(
                replacesNetworkIcon: true
            )
        )

        XCTAssertTrue(cache.shouldRender(standard))
        XCTAssertTrue(cache.shouldRender(replacementEnabled))
        XCTAssertFalse(cache.shouldRender(replacementEnabled))
    }

    func testBluetoothSymbolScaleChangeRendersAgain() {
        var cache = StatusBarRenderCache()
        let standard = makeKey(
            appearance: "darkAqua",
            bluetoothAudioOptions: .standard
        )
        let scaled = makeKey(
            appearance: "darkAqua",
            bluetoothAudioOptions: BluetoothAudioIconOptions(
                symbolScale: 1.45
            )
        )

        XCTAssertTrue(cache.shouldRender(standard))
        XCTAssertTrue(cache.shouldRender(scaled))
        XCTAssertFalse(cache.shouldRender(scaled))
    }

    func testOutputDevicesDoNotInvalidateMenuBarStatus() {
        let first = makeSnapshot(outputDevices: [makeDevice(id: 1, uid: "one")])
        let second = makeSnapshot(outputDevices: [makeDevice(id: 2, uid: "two")])

        XCTAssertNotEqual(first.volume, second.volume)
        XCTAssertEqual(MenuBarStatus(snapshot: first), MenuBarStatus(snapshot: second))
    }

    /// The ring stroke width is part of both option structs, so the menu bar
    /// cache must treat it as a change and redraw instead of keeping a stale
    /// image.
    func testRingStrokeWidthChangeRendersAgain() {
        var cache = StatusBarRenderCache()
        let light = makeKey(
            appearance: "darkAqua",
            options: BatteryIconOptions(ringStrokeScale: RingStrokeStyle.light.scale)
        )
        let bold = makeKey(
            appearance: "darkAqua",
            options: BatteryIconOptions(ringStrokeScale: RingStrokeStyle.bold.scale)
        )

        XCTAssertTrue(cache.shouldRender(light))
        XCTAssertTrue(cache.shouldRender(bold))
        XCTAssertFalse(cache.shouldRender(bold))
    }

    private func makeKey(
        volumeScalar: Double = 0.5,
        appearance: String,
        options: BatteryIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard
    ) -> StatusBarRenderKey {
        StatusBarRenderKey(
            status: MenuBarStatus(
                snapshot: makeSnapshot(volumeScalar: volumeScalar)
            ),
            iconSize: 28,
            options: options,
            connectionOptions: .standard,
            bluetoothAudioOptions: bluetoothAudioOptions,
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
