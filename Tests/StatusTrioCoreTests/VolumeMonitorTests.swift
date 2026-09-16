import CoreAudio
import XCTest
@testable import StatusTrioCore

@MainActor
final class VolumeMonitorTests: XCTestCase {
    func testSuccessfulReadingMapsToStatus() async {
        let reading = VolumeReading(
            scalar: 0.42,
            isMuted: true,
            deviceName: "MacBook Pro Speakers"
        )
        let monitor = makeMonitor(reader: FakeVolumeReader(result: reading))

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let status = await iterator.next()

        XCTAssertEqual(
            status,
            VolumeStatus(
                scalar: 0.42,
                isMuted: true,
                deviceName: "MacBook Pro Speakers"
            )
        )
        monitor.stop()
    }

    func testMissingDeviceMapsToUnavailableStatus() async {
        let monitor = makeMonitor(reader: FakeVolumeReader(result: nil))

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let status = await iterator.next()

        XCTAssertNil(status?.scalar)
        XCTAssertFalse(status?.isMuted == true)
        XCTAssertNil(status?.deviceName)
        monitor.stop()
    }

    func testNilScalarWithValidDeviceMapsToStatusInsteadOfPlaceholder() async {
        let monitor = makeMonitor(reader: FakeVolumeReader(result: VolumeReading(
            scalar: nil,
            isMuted: true,
            deviceName: "USB Headset"
        )))

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let status = await iterator.next()

        XCTAssertEqual(
            status,
            VolumeStatus(
                scalar: nil,
                isMuted: true,
                deviceName: "USB Headset"
            )
        )
        monitor.stop()
    }

    func testDetailsAreLazyAndLevelRefreshesReuseCachedDevices() async {
        let reader = FakeVolumeReader(result: makeReading(scalar: 0.25))
        let eventMonitor = FakeVolumeEventMonitor()
        let devices = [
            AudioOutputDevice(
                id: 42,
                name: "Speakers",
                uid: "speakers",
                isCurrent: true,
                volume: 0.25
            )
        ]
        let outputController = FakeAudioOutputController(devices: devices)
        let monitor = VolumeMonitor(
            reader: reader,
            eventMonitor: eventMonitor,
            outputController: outputController
        )
        monitor.setDetailsVisible(false)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        let hiddenInitial = await iterator.next()
        XCTAssertEqual(hiddenInitial?.outputDevices, [])
        XCTAssertEqual(outputController.outputDevicesCallCount, 0)

        monitor.setDetailsVisible(true)
        monitor.refresh()
        let visible = await iterator.next()
        XCTAssertEqual(visible?.outputDevices, devices)
        XCTAssertEqual(outputController.outputDevicesCallCount, 1)

        eventMonitor.sendVolumeChange()
        let levelUpdate = await iterator.next()
        XCTAssertEqual(levelUpdate?.outputDevices, devices)
        XCTAssertEqual(outputController.outputDevicesCallCount, 1)

        monitor.setDetailsVisible(false)
        let hiddenAgain = await iterator.next()
        XCTAssertEqual(hiddenAgain?.outputDevices, [])
        monitor.stop()
    }

    func testDefaultDeviceCallbackRefreshes() async {
        let reader = FakeVolumeReader(result: makeReading(scalar: 0.25))
        let eventMonitor = FakeVolumeEventMonitor()
        let monitor = makeMonitor(reader: reader, eventMonitor: eventMonitor)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        reader.result = makeReading(scalar: 0.75)
        eventMonitor.sendDefaultDeviceChange()
        let status = await iterator.next()

        XCTAssertEqual(status?.scalar, 0.75)
        XCTAssertEqual(reader.readCount, 2)
        monitor.stop()
    }

    func testVolumeCallbacksCoalesceIntoSingleRefresh() async {
        let reader = FakeVolumeReader(result: makeReading(scalar: 0.25))
        let eventMonitor = FakeVolumeEventMonitor()
        let sleeper = ManualEventSleeper()
        let monitor = VolumeMonitor(
            reader: reader,
            eventMonitor: eventMonitor,
            refreshDebounceSleep: { duration in
                await sleeper.sleep(duration)
            }
        )
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        for index in 0..<20 {
            reader.result = makeReading(scalar: Double(index) / 100)
            eventMonitor.sendVolumeChange()
        }

        await sleeper.waitForCallCount(1)
        XCTAssertEqual(reader.readCount, 1)
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(1)
        _ = await iterator.next()

        XCTAssertEqual(reader.readCount, 2)
        monitor.stop()
    }

    func testVolumeCallbackRefreshes() async {
        let reader = FakeVolumeReader(result: makeReading(scalar: 0.25))
        let eventMonitor = FakeVolumeEventMonitor()
        let monitor = makeMonitor(reader: reader, eventMonitor: eventMonitor)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        reader.result = makeReading(scalar: 0.5)
        eventMonitor.sendVolumeChange()
        let status = await iterator.next()

        XCTAssertEqual(status?.scalar, 0.5)
        XCTAssertEqual(reader.readCount, 2)
        monitor.stop()
    }

    func testStartImmediatelyRefreshesAndStartsEventMonitor() async {
        let reader = FakeVolumeReader(result: makeReading(scalar: 0.6))
        let eventMonitor = FakeVolumeEventMonitor()
        let monitor = makeMonitor(reader: reader, eventMonitor: eventMonitor)

        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        let status = await iterator.next()

        XCTAssertEqual(status?.scalar, 0.6)
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(eventMonitor.startCount, 1)
        monitor.stop()
    }

    func testRefreshReconcilesBeforeReading() {
        let reader = FakeVolumeReader(result: makeReading(scalar: 0.5))
        let eventMonitor = FakeVolumeEventMonitor()
        let monitor = makeMonitor(reader: reader, eventMonitor: eventMonitor)

        monitor.refresh()

        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(eventMonitor.reconcileCount, 1)
        monitor.stop()
    }

    func testStartIsOneShot() {
        let reader = FakeVolumeReader(result: makeReading(scalar: 0.5))
        let eventMonitor = FakeVolumeEventMonitor()
        let monitor = makeMonitor(reader: reader, eventMonitor: eventMonitor)

        monitor.start()
        monitor.start()

        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(eventMonitor.startCount, 1)
        monitor.stop()
    }

    func testRecoverReinstallsEventMonitorWithoutRefreshingOrFinishingStream() async {
        let reader = FakeVolumeReader(result: makeReading(scalar: 0.25))
        let eventMonitor = FakeVolumeEventMonitor()
        let monitor = makeMonitor(reader: reader, eventMonitor: eventMonitor)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        monitor.recover()

        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(eventMonitor.recoverCount, 1)

        reader.result = makeReading(scalar: 0.75)
        eventMonitor.sendVolumeChange()
        let recoveredStatus = await iterator.next()
        XCTAssertEqual(recoveredStatus?.scalar, 0.75)
        monitor.stop()
    }

    func testRecoverAfterStopDoesNotReinstallOrEmit() async {
        let reader = FakeVolumeReader(result: makeReading(scalar: 0.5))
        let eventMonitor = FakeVolumeEventMonitor()
        let monitor = makeMonitor(reader: reader, eventMonitor: eventMonitor)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()
        monitor.stop()

        monitor.recover()

        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(eventMonitor.startCount, 1)
        XCTAssertEqual(eventMonitor.stopCount, 1)
        XCTAssertEqual(eventMonitor.recoverCount, 0)
        let finalStatus = await iterator.next()
        XCTAssertNil(finalStatus)
    }

    func testStopIsIdempotentAndFinishesUpdates() async {
        let eventMonitor = FakeVolumeEventMonitor()
        let monitor = makeMonitor(
            reader: FakeVolumeReader(result: makeReading(scalar: 0.5)),
            eventMonitor: eventMonitor
        )
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        monitor.stop()
        monitor.stop()

        XCTAssertEqual(eventMonitor.stopCount, 1)
        let finalStatus = await iterator.next()
        XCTAssertNil(finalStatus)
    }

    func testStartAfterStopIsNoOp() {
        let reader = FakeVolumeReader(result: makeReading(scalar: 0.5))
        let eventMonitor = FakeVolumeEventMonitor()
        let monitor = makeMonitor(reader: reader, eventMonitor: eventMonitor)
        monitor.start()
        monitor.stop()

        monitor.start()

        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(eventMonitor.startCount, 1)
    }

    func testStoppedRefreshDoesNotReadReconcileOrEmit() async {
        let reader = FakeVolumeReader(result: makeReading(scalar: 0.5))
        let eventMonitor = FakeVolumeEventMonitor()
        let monitor = makeMonitor(reader: reader, eventMonitor: eventMonitor)
        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        monitor.stop()
        monitor.refresh()

        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(eventMonitor.reconcileCount, 1)
        let finalStatus = await iterator.next()
        XCTAssertNil(finalStatus)
    }

    func testDeinitWithoutStopStopsEventMonitorAndFinishesUpdates() async {
        let eventMonitor = FakeVolumeEventMonitor()
        var monitor: VolumeMonitor? = makeMonitor(
            reader: FakeVolumeReader(result: makeReading(scalar: 0.5)),
            eventMonitor: eventMonitor
        )
        weak var weakMonitor = monitor
        monitor?.start()
        var iterator = monitor?.updates.makeAsyncIterator()
        _ = await iterator?.next()

        monitor = nil

        XCTAssertNil(weakMonitor)
        XCTAssertEqual(eventMonitor.stopCount, 1)
        let finalStatus = await iterator?.next()
        XCTAssertNil(finalStatus)
    }

    func testReaderRejectsUnknownDevice() {
        let client = FakeCoreAudioClient()
        client.defaultDeviceID = kAudioObjectUnknown
        let reader = CoreAudioVolumeReader(client: client)

        XCTAssertNil(reader.read())
        XCTAssertEqual(client.deviceClassReadCount, 0)
    }

    func testReaderRejectsWrongDeviceClass() {
        let client = FakeCoreAudioClient()
        client.defaultDeviceID = 42
        client.deviceClasses[42] = kAudioObjectClassID
        client.aliveDevices.insert(42)
        let reader = CoreAudioVolumeReader(client: client)

        XCTAssertNil(reader.read())
        XCTAssertEqual(client.alivenessReadCount, 0)
    }

    func testReaderRejectsDeadDefaultDevice() {
        let client = FakeCoreAudioClient()
        client.defaultDeviceID = 42
        client.deviceClasses[42] = kAudioDeviceClassID
        let reader = CoreAudioVolumeReader(client: client)

        XCTAssertNil(reader.read())
        XCTAssertEqual(client.alivenessReadCount, 1)
    }

    func testReaderReturnsValidDeviceWhenScalarIsMissing() {
        let client = FakeCoreAudioClient()
        client.configureDevice(42, scalar: nil, isMuted: true, name: "USB Headset")
        let reader = CoreAudioVolumeReader(client: client)

        XCTAssertEqual(
            reader.read(),
            VolumeReading(
                scalar: nil,
                isMuted: true,
                deviceName: "USB Headset"
            )
        )
    }

    func testReaderLeavesMissingDeviceNameOptional() {
        let client = FakeCoreAudioClient()
        client.configureDevice(42, scalar: 0.3, isMuted: false, name: nil)
        let reader = CoreAudioVolumeReader(client: client)

        XCTAssertNil(reader.read()?.deviceName)
    }

    func testFirstValueFallsBackThroughOutputElements() {
        let value: Float32? = CoreAudioVolumeReader.firstValue { element in
            element == 2 ? 0.42 : nil
        }

        XCTAssertEqual(value, 0.42)
    }

    func testMissingMuteValueMeansUnmuted() {
        XCTAssertFalse(CoreAudioVolumeReader.isMuted { _ in nil })
    }

    func testEventMonitorReconcileIsNoOpBeforeStart() {
        let client = FakeCoreAudioClient()
        client.configureDevice(42, scalar: 0.5, isMuted: false, name: "Speakers")
        let monitor = CoreAudioVolumeEventMonitor(client: client)

        monitor.reconcile()

        XCTAssertTrue(client.addAttempts.isEmpty)
        XCTAssertTrue(client.removals.isEmpty)
    }

    func testEventMonitorRecoverRemovesAndReinstallsListeners() {
        let client = FakeCoreAudioClient()
        client.configureDevice(
            42,
            scalar: 0.5,
            isMuted: false,
            name: "Speakers",
            supportedElements: [kAudioObjectPropertyElementMain]
        )
        let monitor = CoreAudioVolumeEventMonitor(client: client)
        monitor.start(onDefaultDeviceChange: {}, onVolumeChange: {})
        let initialListeners = client.activeListeners
        let initialSuccessfulAdds = client.successfulAdds

        monitor.recover()

        XCTAssertEqual(client.addAttempts.count, initialSuccessfulAdds.count * 2)
        XCTAssertEqual(client.successfulAdds.count, initialSuccessfulAdds.count * 2)
        XCTAssertEqual(Set(client.activeListeners), Set(initialListeners))
        XCTAssertTrue(initialListeners.allSatisfy { client.removals.contains($0) })
        monitor.stop()
    }

    func testEventMonitorRetriesFailedDefaultDeviceListener() {
        let client = FakeCoreAudioClient()
        client.configureDevice(42, scalar: 0.5, isMuted: false, name: "Speakers")
        client.failNextAdd(for: client.defaultDeviceListenerKey)
        let monitor = CoreAudioVolumeEventMonitor(client: client)

        monitor.start(onDefaultDeviceChange: {}, onVolumeChange: {})
        XCTAssertFalse(client.hasDefaultDeviceListener)
        XCTAssertEqual(client.defaultDeviceAddAttemptCount, 1)

        monitor.reconcile()

        XCTAssertTrue(client.hasDefaultDeviceListener)
        XCTAssertEqual(client.defaultDeviceAddAttemptCount, 2)
        monitor.stop()
    }

    func testEventMonitorReconcileRepairsPartialDeviceRegistration() {
        let client = FakeCoreAudioClient()
        client.configureDevice(
            42,
            scalar: 0.5,
            isMuted: false,
            name: "Speakers",
            supportedElements: [kAudioObjectPropertyElementMain]
        )
        let volumeKey = client.propertyKey(
            objectID: 42,
            selector: kAudioDevicePropertyVolumeScalar,
            element: kAudioObjectPropertyElementMain
        )
        client.failNextAdd(for: volumeKey)
        let monitor = CoreAudioVolumeEventMonitor(client: client)

        monitor.start(onDefaultDeviceChange: {}, onVolumeChange: {})
        XCTAssertEqual(
            Set(client.successfulDeviceListenerKeys(for: 42)),
            [client.propertyKey(
                objectID: 42,
                selector: kAudioDevicePropertyMute,
                element: kAudioObjectPropertyElementMain
            )]
        )

        monitor.reconcile()

        XCTAssertEqual(
            Set(client.successfulDeviceListenerKeys(for: 42)),
            [volumeKey, client.propertyKey(
                objectID: 42,
                selector: kAudioDevicePropertyMute,
                element: kAudioObjectPropertyElementMain
            )]
        )
        XCTAssertEqual(client.addAttemptCount(for: volumeKey), 2)
        monitor.stop()
    }

    func testDefaultDeviceChangeMigratesListenersUsingExactOperations() async {
        let client = FakeCoreAudioClient()
        client.configureDevice(
            10,
            scalar: 0.5,
            isMuted: false,
            name: "First",
            supportedElements: [kAudioObjectPropertyElementMain]
        )
        client.configureDevice(
            20,
            scalar: 0.5,
            isMuted: false,
            name: "Second",
            supportedElements: [kAudioObjectPropertyElementMain]
        )
        client.defaultDeviceID = 10
        let callbackExpectation = expectation(description: "default device callback")
        let monitor = CoreAudioVolumeEventMonitor(client: client)

        monitor.start(
            onDefaultDeviceChange: { callbackExpectation.fulfill() },
            onVolumeChange: {}
        )
        let firstDeviceListeners = client.activeDeviceListeners(for: 10)
        XCTAssertFalse(firstDeviceListeners.isEmpty)

        client.defaultDeviceID = 20
        client.triggerDefaultOutputDeviceChange()
        await fulfillment(of: [callbackExpectation], timeout: 1)

        XCTAssertEqual(Set(client.removals.filter { $0.objectID == 10 }), Set(firstDeviceListeners))
        XCTAssertEqual(Set(client.activeDeviceListeners(for: 20)), Set(client.successfulDeviceListeners(for: 20)))
        XCTAssertTrue(client.activeDeviceListeners(for: 10).isEmpty)
        XCTAssertTrue(client.hasDefaultDeviceListener)
        monitor.stop()
    }

    private func makeReading(scalar: Double?) -> VolumeReading {
        VolumeReading(
            scalar: scalar,
            isMuted: false,
            deviceName: "MacBook Pro Speakers"
        )
    }

    private func makeMonitor(
        reader: FakeVolumeReader,
        eventMonitor: FakeVolumeEventMonitor = FakeVolumeEventMonitor()
    ) -> VolumeMonitor {
        VolumeMonitor(reader: reader, eventMonitor: eventMonitor)
    }
}

@MainActor
private final class FakeAudioOutputController: AudioOutputControlling {
    let devices: [AudioOutputDevice]
    private(set) var outputDevicesCallCount = 0

    init(devices: [AudioOutputDevice]) {
        self.devices = devices
    }

    func outputDevices() -> [AudioOutputDevice] {
        outputDevicesCallCount += 1
        return devices
    }

    func setVolume(_ scalar: Double) -> Bool { true }
    func toggleMute() -> Bool { true }
    func selectOutputDevice(_ deviceID: AudioDeviceID) -> Bool { true }
}

private final class FakeVolumeReader: VolumeReadingProviding {
    var result: VolumeReading?
    private(set) var readCount = 0

    init(result: VolumeReading?) {
        self.result = result
    }

    func read() -> VolumeReading? {
        readCount += 1
        return result
    }
}

@MainActor
private final class FakeVolumeEventMonitor: VolumeEventMonitoring {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var reconcileCount = 0
    private(set) var recoverCount = 0
    private var onDefaultDeviceChange: (@MainActor @Sendable () -> Void)?
    private var onVolumeChange: (@MainActor @Sendable () -> Void)?

    func start(
        onDefaultDeviceChange: @escaping @MainActor @Sendable () -> Void,
        onVolumeChange: @escaping @MainActor @Sendable () -> Void
    ) {
        startCount += 1
        self.onDefaultDeviceChange = onDefaultDeviceChange
        self.onVolumeChange = onVolumeChange
    }

    func reconcile() {
        reconcileCount += 1
    }

    func recover() {
        recoverCount += 1
    }

    func stop() {
        stopCount += 1
        onDefaultDeviceChange = nil
        onVolumeChange = nil
    }

    func sendDefaultDeviceChange() {
        onDefaultDeviceChange?()
    }

    func sendVolumeChange() {
        onVolumeChange?()
    }
}

private struct ListenerOperation: Hashable {
    let objectID: AudioObjectID
    let selector: AudioObjectPropertySelector
    let scope: AudioObjectPropertyScope
    let element: AudioObjectPropertyElement
}

private struct CoreAudioPropertyKey: Hashable {
    let objectID: AudioObjectID
    let selector: AudioObjectPropertySelector
    let scope: AudioObjectPropertyScope
    let element: AudioObjectPropertyElement
}

private final class FakeCoreAudioClient: CoreAudioClient {
    var defaultDeviceID: AudioDeviceID?
    var deviceClasses: [AudioDeviceID: AudioClassID] = [:]
    var aliveDevices: Set<AudioDeviceID> = []
    var availableProperties: Set<CoreAudioPropertyKey> = []
    var uint32Values: [CoreAudioPropertyKey: UInt32] = [:]
    var float32Values: [CoreAudioPropertyKey: Float32] = [:]
    var stringValues: [CoreAudioPropertyKey: String] = [:]
    private(set) var deviceClassReadCount = 0
    private(set) var alivenessReadCount = 0
    private(set) var addAttempts: [ListenerOperation] = []
    private(set) var successfulAdds: [ListenerOperation] = []
    private(set) var removals: [ListenerOperation] = []
    private(set) var activeListeners: [ListenerOperation] = []
    private var listenerFailures: [CoreAudioPropertyKey: Int] = [:]
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?

    var defaultDeviceListenerKey: CoreAudioPropertyKey {
        propertyKey(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain
        )
    }

    var defaultDeviceAddAttemptCount: Int {
        addAttempts.filter { $0 == defaultDeviceListenerKey.operation }.count
    }

    var hasDefaultDeviceListener: Bool {
        defaultDeviceListener != nil
    }

    func configureDevice(
        _ deviceID: AudioDeviceID,
        scalar: Float32?,
        isMuted: Bool,
        name: String?,
        supportedElements: [AudioObjectPropertyElement] = CoreAudioVolumeReader.outputElements
    ) {
        defaultDeviceID = deviceID
        deviceClasses[deviceID] = kAudioDeviceClassID
        aliveDevices.insert(deviceID)

        for element in supportedElements {
            let volumeKey = propertyKey(
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                element: element
            )
            let muteKey = propertyKey(
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                element: element
            )
            availableProperties.insert(volumeKey)
            availableProperties.insert(muteKey)
            if let scalar {
                float32Values[volumeKey] = scalar
            }
            uint32Values[muteKey] = isMuted ? 1 : 0
        }

        if let name {
            stringValues[propertyKey(
                objectID: deviceID,
                selector: kAudioObjectPropertyName,
                scope: kAudioObjectPropertyScopeGlobal,
                element: kAudioObjectPropertyElementMain
            )] = name
        }
    }

    func failNextAdd(for key: CoreAudioPropertyKey) {
        listenerFailures[key, default: 0] += 1
    }

    func triggerDefaultOutputDeviceChange() {
        guard let defaultDeviceListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        withUnsafePointer(to: &address) { pointer in
            defaultDeviceListener(1, pointer)
        }
    }

    func propertyKey(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput,
        element: AudioObjectPropertyElement
    ) -> CoreAudioPropertyKey {
        CoreAudioPropertyKey(
            objectID: objectID,
            selector: selector,
            scope: scope,
            element: element
        )
    }

    func addAttemptCount(for key: CoreAudioPropertyKey) -> Int {
        addAttempts.filter { $0 == key.operation }.count
    }

    func successfulDeviceListenerKeys(for deviceID: AudioDeviceID) -> [CoreAudioPropertyKey] {
        successfulAdds
            .filter { $0.objectID == deviceID }
            .map(\.key)
            .sorted(by: keySort)
    }

    func successfulDeviceListeners(for deviceID: AudioDeviceID) -> [ListenerOperation] {
        successfulAdds.filter { $0.objectID == deviceID }
    }

    func activeDeviceListeners(for deviceID: AudioDeviceID) -> [ListenerOperation] {
        activeListeners.filter { $0.objectID == deviceID }
    }

    func defaultOutputDevice() -> AudioDeviceID? {
        defaultDeviceID
    }

    func deviceClass(of deviceID: AudioDeviceID) -> AudioClassID? {
        deviceClassReadCount += 1
        return deviceClasses[deviceID]
    }

    func isDeviceAlive(_ deviceID: AudioDeviceID) -> Bool {
        alivenessReadCount += 1
        return aliveDevices.contains(deviceID)
    }

    func readUInt32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> UInt32? {
        uint32Values[propertyKey(
            objectID: objectID,
            selector: selector,
            scope: scope,
            element: element
        )]
    }

    func readFloat32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Float32? {
        float32Values[propertyKey(
            objectID: objectID,
            selector: selector,
            scope: scope,
            element: element
        )]
    }

    func readString(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> String? {
        stringValues[propertyKey(
            objectID: objectID,
            selector: selector,
            scope: scope,
            element: element
        )]
    }

    func hasProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        availableProperties.contains(propertyKey(
            objectID: objectID,
            selector: selector,
            scope: scope,
            element: element
        ))
    }

    func addListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue?,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        let key = propertyKey(
            objectID: objectID,
            selector: address.mSelector,
            scope: address.mScope,
            element: address.mElement
        )
        let operation = key.operation
        addAttempts.append(operation)

        if let remaining = listenerFailures[key], remaining > 0 {
            listenerFailures[key] = remaining - 1
            return kAudioHardwareUnspecifiedError
        }

        successfulAdds.append(operation)
        activeListeners.append(operation)
        if key == defaultDeviceListenerKey {
            defaultDeviceListener = block
        }
        return noErr
    }

    func removeListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue?,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        let key = propertyKey(
            objectID: objectID,
            selector: address.mSelector,
            scope: address.mScope,
            element: address.mElement
        )
        let operation = key.operation
        removals.append(operation)
        activeListeners.removeAll { $0 == operation }
        if key == defaultDeviceListenerKey {
            defaultDeviceListener = nil
        }
        return noErr
    }

    private func keySort(_ lhs: CoreAudioPropertyKey, _ rhs: CoreAudioPropertyKey) -> Bool {
        if lhs.selector != rhs.selector {
            return lhs.selector < rhs.selector
        }
        return lhs.element < rhs.element
    }
}

private extension CoreAudioPropertyKey {
    var operation: ListenerOperation {
        ListenerOperation(
            objectID: objectID,
            selector: selector,
            scope: scope,
            element: element
        )
    }
}

private extension ListenerOperation {
    var key: CoreAudioPropertyKey {
        CoreAudioPropertyKey(
            objectID: objectID,
            selector: selector,
            scope: scope,
            element: element
        )
    }
}
