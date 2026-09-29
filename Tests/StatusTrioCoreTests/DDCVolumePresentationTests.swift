import CoreAudio
import XCTest
@testable import StatusTrioCore

@MainActor
final class DDCVolumePresentationTests: XCTestCase {
    func testConfirmedDDCUpdateReplacesCoreAudioPlaceholderAndSelectedRowVolume() async {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = FixedAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: false, canMute: false
        ), devices: [row])
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: PresentationDDCTransport())
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        let status = await iterator.next()

        XCTAssertEqual(status?.scalar, 0.75)
        XCTAssertTrue(status?.canSetVolume == true)
        XCTAssertFalse(status?.canMute == true)
        XCTAssertFalse(status?.isMuted == true)
        XCTAssertEqual(status?.outputDevices.first(where: { $0.isCurrent })?.volume, 0.75)
        monitor.stop()
    }

    func testDDCVolumeCanBePresentedWithoutMuteCapability() {
        let status = VolumeStatus(
            scalar: 0.75,
            isMuted: false,
            deviceName: "XV272U",
            canSetVolume: true,
            canMute: false
        )

        XCTAssertEqual(status.scalar, 0.75)
        XCTAssertTrue(status.canSetVolume)
        XCTAssertFalse(status.canMute)
        XCTAssertFalse(status.isMuted)
    }

    func testOutputDeviceCopyCanReplaceConfirmedVolume() {
        let device = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let updated = device.replacingVolume(0.75)

        XCTAssertEqual(updated.volume, 0.75)
        XCTAssertEqual(updated.uid, "DISPLAY-A")
        XCTAssertTrue(updated.isCurrent)
    }

    func testZeroDDCScalarIsZeroPercentAndNotMuted() {
        let status = VolumeStatus(
            scalar: 0,
            isMuted: false,
            deviceName: "XV272U",
            canSetVolume: true,
            canMute: false
        )

        XCTAssertEqual(status.scalar, 0)
        XCTAssertFalse(status.isMuted)
        XCTAssertTrue(status.canSetVolume)
        XCTAssertFalse(status.canMute)
    }
}

@MainActor
private final class FixedAudioStatusReader: AudioStatusReadingProviding {
    private let reading: VolumeReading
    private let devices: [AudioOutputDevice]
    init(reading: VolumeReading, devices: [AudioOutputDevice]) { self.reading = reading; self.devices = devices }
    func read(includeOutputDevices: Bool, completion: @escaping @MainActor @Sendable (AudioStatusReading) -> Void) {
        completion(AudioStatusReading(volume: reading, outputDevices: includeOutputDevices ? devices : nil))
    }
}

@MainActor
private final class PresentationVolumeEvents: VolumeEventMonitoring {
    func start(onDefaultDeviceChange: @escaping @MainActor @Sendable () -> Void,
               onVolumeChange: @escaping @MainActor @Sendable () -> Void) {}
    func reconcile() {}
    func recover() {}
    func stop() {}
}

private final class PresentationDDCTransport: DDCVolumeTransport {
    func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReply? { DDCVolumeReply(current: 75, maximum: 100) }
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool { true }
}
