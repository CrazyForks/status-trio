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

    func testSameOutputCoreAudioRefreshPreservesConfirmedDDCVolumeAndRow() async {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = MutableAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: false, canMute: false
        ), devices: [row])
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: PresentationDDCTransport())
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        let confirmed = await iterator.next()
        XCTAssertEqual(confirmed?.scalar, 0.75)

        monitor.refresh()
        let refreshed = await iterator.next()

        XCTAssertEqual(refreshed?.scalar, 0.75)
        XCTAssertTrue(refreshed?.canSetVolume == true)
        XCTAssertFalse(refreshed?.canMute == true)
        XCTAssertEqual(refreshed?.outputDevices.first(where: { $0.isCurrent })?.volume, 0.75)

        monitor.setVolume(0.6)
        let sliderRefresh = await iterator.next()
        XCTAssertEqual(sliderRefresh?.scalar, 0.75)
        XCTAssertEqual(sliderRefresh?.outputDevices.first(where: { $0.isCurrent })?.volume, 0.75)
        monitor.stop()
    }

    func testSameOutputRefreshKeepsDDCMuteDisabledWhenCoreAudioReportsMute() async {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = MutableAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: false, canMute: false
        ), devices: [row])
        let commands = MuteCommandRecorder()
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   outputController: commands, ddcTransport: PresentationDDCTransport())
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        let confirmed = await iterator.next()
        XCTAssertEqual(confirmed?.scalar, 0.75)

        reader.reading = VolumeReading(scalar: nil, isMuted: true, deviceName: "XV272U",
                                       currentDevice: row, canSetVolume: true, canMute: true)
        monitor.refresh()
        let refreshed = await iterator.next()

        XCTAssertEqual(refreshed?.scalar, 0.75)
        XCTAssertFalse(refreshed?.isMuted == true)
        XCTAssertFalse(refreshed?.canMute == true)
        monitor.toggleMute()
        XCTAssertEqual(commands.muteCount, 0)
        monitor.stop()
    }

    func testReadableWritableCoreAudioScalarKeepsPriorityOverDDC() async {
        let row = AudioOutputDevice(id: 42, name: "Speakers", uid: "DISPLAY-A", isCurrent: true, volume: 0.5)
        let reader = FixedAudioStatusReader(reading: VolumeReading(
            scalar: 0.5, isMuted: false, deviceName: "Speakers", currentDevice: row,
            canSetVolume: true, canMute: true
        ), devices: [row])
        let transport = TrackingPresentationDDCTransport()
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: transport)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        let status = await iterator.next()

        XCTAssertEqual(status?.scalar, 0.5)
        XCTAssertEqual(transport.readCount, 0)
        monitor.stop()
    }

    func testReadableButUnsettableScalarFallsBackToDDC() async {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = FixedAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: true, canMute: true
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
        monitor.stop()
    }

    func testDeviceDisappearanceCancelsPendingDDCWrite() async throws {
        let row = AudioOutputDevice(id: 42, name: "XV272U", uid: "DISPLAY-A", isCurrent: true)
        let reader = MutableAudioStatusReader(reading: VolumeReading(
            scalar: nil, isMuted: false, deviceName: "XV272U", currentDevice: row,
            canSetVolume: false, canMute: false
        ), devices: [row])
        let transport = TrackingPresentationDDCTransport()
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: PresentationVolumeEvents(),
                                   ddcTransport: transport)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        _ = await iterator.next()
        monitor.setVolume(0.5)
        reader.reading = nil
        monitor.refresh()
        let disappeared = await iterator.next()
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertNil(disappeared?.scalar)
        XCTAssertEqual(transport.writeCount, 0)
        monitor.stop()
    }

    func testTopologyChangeClearsConfirmedDDCVolumeAndSelectedRowImmediately() async {
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
        let confirmed = await iterator.next()
        XCTAssertEqual(confirmed?.scalar, 0.75)

        monitor.topologyChanged()
        let invalidated = await iterator.next()

        XCTAssertNil(invalidated?.scalar)
        XCTAssertNil(invalidated?.currentDevice?.volume)
        XCTAssertFalse(invalidated?.canSetVolume == true)
        XCTAssertNil(invalidated?.outputDevices.first(where: { $0.isCurrent })?.volume)
        monitor.stop()
    }

    func testMuteCapabilityRemainsAvailableWithoutVolumeCapability() async {
        let volume = CapabilityFakeVolumeMonitor()
        let store = SystemStatusStore(
            batteryMonitor: CapabilityBatteryMonitor(), wifiMonitor: CapabilityWiFiMonitor(), volumeMonitor: volume
        )
        store.start()
        let status = VolumeStatus(scalar: nil, isMuted: false, deviceName: "Speakers",
                                  canSetVolume: false, canMute: true)
        volume.send(status)
        for _ in 0..<100 where store.liveVolume != status { await Task.yield() }

        XCTAssertTrue(store.isVolumeControllerAvailable)
        XCTAssertFalse(store.liveVolume.canSetVolume)
        XCTAssertTrue(store.liveVolume.canMute)
        store.stop()
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
private final class MutableAudioStatusReader: AudioStatusReadingProviding {
    var reading: VolumeReading?
    var devices: [AudioOutputDevice]
    init(reading: VolumeReading, devices: [AudioOutputDevice]) { self.reading = reading; self.devices = devices }
    func read(includeOutputDevices: Bool, completion: @escaping @MainActor @Sendable (AudioStatusReading) -> Void) {
        completion(AudioStatusReading(volume: reading, outputDevices: includeOutputDevices ? devices : nil))
    }
}

@MainActor
private final class CapabilityFakeVolumeMonitor: VolumeMonitoring, VolumeControlling {
    let updates: AsyncStream<VolumeStatus>
    private let continuation: AsyncStream<VolumeStatus>.Continuation
    private(set) var toggleMuteCount = 0
    init() { (updates, continuation) = MonitorStream.make(of: VolumeStatus.self) }
    func send(_ status: VolumeStatus) { continuation.yield(status) }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
    func setDisplayAsleep(_ asleep: Bool) {}
    func topologyChanged() {}
    func setVolume(_ scalar: Double) {}
    func toggleMute() { toggleMuteCount += 1 }
    func selectOutputDevice(_ deviceID: AudioDeviceID) {}
}

@MainActor
private final class MuteCommandRecorder: AudioOutputControlling {
    private(set) var muteCount = 0
    func setVolume(_ scalar: Double) -> Bool { true }
    func toggleMute() -> Bool { muteCount += 1; return true }
    func selectOutputDevice(_ deviceID: AudioDeviceID) -> Bool { true }
}

@MainActor
private final class CapabilityBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation
    init() { (updates, continuation) = MonitorStream.make(of: BatteryStatus.self) }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
}

@MainActor
private final class CapabilityWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private let continuation: AsyncStream<WiFiStatus>.Continuation
    init() { (updates, continuation) = MonitorStream.make(of: WiFiStatus.self) }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
    func setDetailsVisible(_ visible: Bool) {}
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

private final class TrackingPresentationDDCTransport: DDCVolumeTransport {
    private let lock = NSLock()
    private var writes = 0
    private var reads = 0
    var writeCount: Int { lock.lock(); defer { lock.unlock() }; return writes }
    var readCount: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReply? {
        lock.lock(); reads += 1; lock.unlock()
        return DDCVolumeReply(current: 75, maximum: 100)
    }
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool {
        lock.lock(); writes += 1; lock.unlock()
        return true
    }
}
