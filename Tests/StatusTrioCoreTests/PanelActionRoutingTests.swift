import AudioToolbox
import XCTest
@testable import StatusTrioCore

@MainActor
final class PanelActionRoutingTests: XCTestCase {
    func testOutputSelectionIgnoresRemovedDeviceAndReusedIDWithDifferentUID() {
        var devices = [makeOutput(id: 7, uid: "old")]
        var selected: [AudioOutputDevice] = []
        let actions = StatusPanelActions(
            outputDevices: { devices },
            selectOutput: { selected.append($0) }
        )
        let oldKey = PanelAudioDeviceID(id: 7, uid: "old")

        devices = []
        actions.selectOutput(oldKey)
        devices = [makeOutput(id: 7, uid: "replacement")]
        actions.selectOutput(oldKey)
        actions.selectOutput(PanelAudioDeviceID(id: 7, uid: nil))

        XCTAssertEqual(selected.map(\.uid), ["replacement"])
    }

    func testInputSelectionIgnoresRemovedDeviceAndReusedIDWithDifferentUID() {
        var devices = [AudioInputDevice(id: AudioDeviceID(9), uid: "old", name: "Mic")]
        var selected: [AudioInputDevice] = []
        let actions = StatusPanelActions(
            inputDevices: { devices },
            selectInput: { selected.append($0) }
        )
        let oldKey = PanelAudioDeviceID(id: 9, uid: "old")

        devices = []
        actions.selectInput(oldKey)
        devices = [AudioInputDevice(id: AudioDeviceID(9), uid: "replacement", name: "Mic")]
        actions.selectInput(oldKey)
        actions.selectInput(PanelAudioDeviceID(id: 9, uid: nil))

        XCTAssertEqual(selected.map(\.uid), ["replacement"])
    }

    func testActionsClampFiniteScalarsFlushAndForwardEachCommandOnce() {
        var outputScalars: [Double] = []
        var inputScalars: [Double] = []
        var finishes = 0
        var muteToggles = 0
        var inputMuteToggles = 0
        let actions = StatusPanelActions(
            setVolume: { outputScalars.append($0) },
            finishVolumeAdjustment: { finishes += 1 },
            toggleMute: { muteToggles += 1 },
            setInputScalar: { inputScalars.append($0) },
            toggleInputMute: { inputMuteToggles += 1 }
        )

        actions.setVolume(0.64)
        actions.setVolume(2)
        actions.setVolume(.infinity)
        actions.finishVolumeAdjustment()
        actions.toggleMute()
        actions.setInputScalar(-1)
        actions.setInputScalar(.nan)
        actions.toggleInputMute()

        XCTAssertEqual(outputScalars, [0.64, 1])
        XCTAssertEqual(inputScalars, [0])
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(muteToggles, 1)
        XCTAssertEqual(inputMuteToggles, 1)
    }

    func testBluetoothActionsResolveCurrentAddressesAndRequireExistingListeningControl() {
        var devices = [
            BluetoothDevice(id: "AA:00:00:00:00:01", name: "Keyboard", kind: .peripheral(.keyboard), isConnected: true),
            BluetoothDevice(id: "AA:00:00:00:00:02", name: "Headphones", kind: .audio, isConnected: true)
        ]
        var performed: [String] = []
        var confirmed: [String] = []
        let pendingConfirmation: String? = nil
        var modes: [(BluetoothListeningMode, String)] = []
        let actions = StatusPanelActions(
            bluetoothDevices: { devices },
            performBluetoothAction: { performed.append($0.id) },
            requestDisconnect: { confirmed.append($0.id) },
            disconnectConfirmationAddress: { pendingConfirmation },
            setListeningMode: { modes.append(($0, $1)) },
            listeningModePresentations: {
                ["AA0000000002": BluetoothListeningModePresentation(
                    availableModes: [.noiseCancellation, .transparency],
                    selectedMode: .noiseCancellation
                )]
            }
        )

        actions.performBluetoothAction(address: "aa-00-00-00-00-02")
        actions.performBluetoothAction(address: "AA:00:00:00:00:09")
        actions.requestDisconnect(address: "AA:00:00:00:00:02")
        actions.requestDisconnect(address: "AA:00:00:00:00:01")
        actions.setListeningMode(address: "aa-00-00-00-00-02", mode: .transparency)
        actions.setListeningMode(address: "aa-00-00-00-00-02", mode: .adaptive)
        actions.setListeningMode(address: "AA:00:00:00:00:01", mode: .transparency)

        devices.removeAll()
        actions.performBluetoothAction(address: "AA:00:00:00:00:02")

        XCTAssertEqual(performed, ["AA:00:00:00:00:02"])
        XCTAssertEqual(confirmed, ["AA:00:00:00:00:01"])
        XCTAssertEqual(modes.count, 1)
        XCTAssertEqual(modes.first?.0, .transparency)
        XCTAssertEqual(modes.first?.1, "AA0000000002")
    }

    func testBluetoothRowTapRequestsInputConfirmationAndConfirmedActionChecksCurrentPendingAddress() {
        let keyboard = BluetoothDevice(id: "AA:00:00:00:00:01", name: "Keyboard", kind: .peripheral(.keyboard), isConnected: true)
        let headphones = BluetoothDevice(id: "AA:00:00:00:00:02", name: "Headphones", kind: .audio, isConnected: true)
        var performed: [String] = []
        var requested: [String] = []
        var pendingAddress: String?
        let actions = StatusPanelActions(
            bluetoothDevices: { [keyboard, headphones] },
            performBluetoothAction: { performed.append($0.id) },
            requestDisconnect: {
                pendingAddress = BluetoothBatteryReader.normalizedAddress($0.id)
                requested.append($0.id)
            },
            disconnectConfirmationAddress: { pendingAddress },
            cancelDisconnect: { pendingAddress = nil }
        )

        actions.rowTapped(address: keyboard.id)
        actions.rowTapped(address: headphones.id)
        actions.performBluetoothAction(address: keyboard.id)
        actions.confirmBluetoothDisconnect(address: "aa-00-00-00-00-01")
        actions.cancelDisconnect()
        actions.confirmBluetoothDisconnect(address: keyboard.id)

        XCTAssertEqual(requested, [keyboard.id])
        XCTAssertEqual(performed, [headphones.id, keyboard.id])
    }

    func testDetailAndVisibleSurfaceActionsRouteLifecycleAndWiFiCommands() {
        var activatedBattery: BatteryPowerState?
        var batteryCloseCount = 0
        var wifiActivations: [WiFiNameAccess] = []
        var wifiCloseCount = 0
        var wifiPower: [Bool] = []
        var wifiRefresh: [WiFiNameAccess] = []
        var heldSummary = 0
        var releasedSummary = 0
        var refreshedModes = 0
        var stoppedModes = 0
        var permissionRequests = 0
        var permissionSettingsOpens = 0

        let battery = BatteryStatus(
            rawPercentage: 42,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        let actions = StatusPanelActions(
            requestBluetoothAuthorization: { permissionRequests += 1 },
            openBluetoothPermissionSettings: { permissionSettingsOpens += 1 },
            batteryStatus: { battery },
            activateBatteryDetails: { activatedBattery = $0 },
            closeBatteryDetails: { batteryCloseCount += 1 },
            wifiNameAccess: { .denied },
            activateWiFiDetails: { wifiActivations.append($0) },
            closeWiFiDetails: { wifiCloseCount += 1 },
            setWiFiPower: { wifiPower.append($0) },
            refreshWiFi: { wifiRefresh.append($0) },
            openWiredDetails: { heldSummary += 1 },
            closeWiredDetails: { releasedSummary += 1 },
            holdBluetoothSummary: { heldSummary += 1 },
            releaseBluetoothSummary: { releasedSummary += 1 },
            refreshVolumeListeningModes: { refreshedModes += 1 },
            stopVolumeListeningModes: { stoppedModes += 1 }
        )

        actions.batteryDetailsAppeared()
        actions.batteryDetailsClosed()
        actions.wifiDetailsOpened()
        actions.wifiDetailsClosed()
        actions.setWiFiPower(false)
        actions.refreshWiFi()
        actions.wiredDetailsOpened()
        actions.wiredDetailsClosed()
        actions.bluetoothSummaryAppeared()
        actions.bluetoothSummaryDisappeared()
        actions.volumeListAppeared()
        actions.volumeListDisappeared()
        actions.requestBluetoothAuthorization()
        actions.openBluetoothPermissionSettings()

        XCTAssertEqual(activatedBattery, BatteryPowerState(battery))
        XCTAssertEqual(batteryCloseCount, 1)
        XCTAssertEqual(wifiActivations, [.denied])
        XCTAssertEqual(wifiCloseCount, 1)
        XCTAssertEqual(wifiPower, [false])
        XCTAssertEqual(wifiRefresh, [.denied])
        XCTAssertEqual(heldSummary, 2)
        XCTAssertEqual(releasedSummary, 2)
        XCTAssertEqual(refreshedModes, 1)
        XCTAssertEqual(stoppedModes, 1)
        XCTAssertEqual(permissionRequests, 1)
        XCTAssertEqual(permissionSettingsOpens, 1)
    }

    func testBluetoothSummaryClaimsStayIndependentAndOnlyReadLevelsForConnectedAvailableDevices() {
        let connected = BluetoothDevice(id: "AA:00:00:00:00:01", name: "AirPods", kind: .audio, isConnected: true)
        var availability: BluetoothAvailability = .available
        var devices = [connected]
        var batteryClaims: [String] = []
        var batteryReleases: [String] = []
        var nearbyClaims: [String] = []
        var nearbyReleases: [String] = []
        let actions = StatusPanelActions(
            bluetoothDevices: { devices },
            bluetoothAvailability: { availability },
            requestBatteryLevels: { batteryClaims.append($0) },
            releaseBatteryLevels: { batteryReleases.append($0) },
            requestNearbyBatteryDevices: { nearbyClaims.append($0) },
            releaseNearbyBatteryDevices: { nearbyReleases.append($0) }
        )

        actions.updateBluetoothBatteryLevelsClaim(enabled: true)
        actions.updateBluetoothNearbyBatteryClaim(enabled: true)
        availability = .poweredOff
        actions.updateBluetoothBatteryLevelsClaim(enabled: true)
        availability = .available
        devices.removeAll()
        actions.updateBluetoothBatteryLevelsClaim(enabled: true)
        actions.updateBluetoothNearbyBatteryClaim(enabled: false)
        actions.bluetoothSummaryAppeared()
        actions.bluetoothSummaryDisappeared()

        XCTAssertEqual(batteryClaims, ["bluetooth.summary"])
        XCTAssertEqual(batteryReleases, ["bluetooth.summary", "bluetooth.summary", "bluetooth.summary"])
        XCTAssertEqual(nearbyClaims, ["bluetooth.summary.nearbyBatteryDevices"])
        XCTAssertEqual(nearbyReleases, ["bluetooth.summary.nearbyBatteryDevices"])
    }

    func testDeviceMovesForwardCurrentOffsetsToTheSettingsOrderWriters() {
        var outputMove: (IndexSet, Int)?
        var bluetoothMove: (IndexSet, Int)?
        let actions = StatusPanelActions(
            moveOutputDevices: { outputMove = ($0, $1) },
            moveBluetoothDevices: { bluetoothMove = ($0, $1) }
        )

        actions.moveOutputDevices(from: IndexSet(integer: 1), to: 3)
        actions.moveBluetoothDevices(from: IndexSet(integer: 0), to: 2)

        XCTAssertEqual(outputMove?.0, IndexSet(integer: 1))
        XCTAssertEqual(outputMove?.1, 3)
        XCTAssertEqual(bluetoothMove?.0, IndexSet(integer: 0))
        XCTAssertEqual(bluetoothMove?.1, 2)
    }

    func testSettingsBackedBluetoothMoveUsesFilteredCollapsedRowsAndPreservesHiddenRanks() async throws {
        let suiteName = "StatusTrioCoreTests.PanelBluetoothMove.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let hidden = "AA0000000001"
        let mouse = "AA0000000002"
        let ghost = "AA0000000003"
        let keyboard = "AA0000000004"
        let beyondCollapsed = "AA0000000005"
        defaults.set([hidden, mouse, ghost, keyboard, beyondCollapsed], forKey: SettingsStore.bluetoothDeviceOrderDefaultsKey)

        let settings = SettingsStore(defaults: defaults)
        settings.hiddenBluetoothDeviceAddresses = [hidden]
        settings.maxVisibleBluetoothDevices = 2
        let devices = [
            BluetoothDevice(id: hidden, name: "A Hidden", kind: .audio, isConnected: true),
            BluetoothDevice(id: mouse, name: "B Mouse", kind: .peripheral(.mouse), isConnected: true),
            BluetoothDevice(id: ghost, name: "C Ghost", kind: .unknown, isConnected: true, isUnpairedGhost: true),
            BluetoothDevice(id: keyboard, name: "D Keyboard", kind: .peripheral(.keyboard), isConnected: true),
            BluetoothDevice(id: beyondCollapsed, name: "E Headphones", kind: .audio, isConnected: true)
        ]
        let bluetooth = BluetoothDeviceController(
            worker: PanelActionRoutingBluetoothReader(devices),
            stateMonitor: PanelActionRoutingBluetoothStateMonitor(),
            batteryReader: PanelActionRoutingBluetoothBatteryReader()
        )
        let store = SystemStatusStore(
            batteryMonitor: PanelActionRoutingBatteryMonitor(),
            wifiMonitor: PanelActionRoutingWiFiMonitor(),
            volumeMonitor: PanelActionRoutingVolumeMonitor(),
            bluetoothDevices: bluetooth
        )
        let actions = StatusPanelActions(store: store, settings: settings)
        bluetooth.activate()
        await waitUntil { bluetooth.devices == devices }

        let resolvedRows = BluetoothDeviceListModel.make(
            devices: bluetooth.devices,
            order: settings.bluetoothDeviceOrder,
            limit: settings.maxVisibleBluetoothDevices,
            isExpanded: false,
            options: settings.bluetoothDeviceListOptions
        ).visibleDevices
        XCTAssertEqual(resolvedRows.map(\.id), [mouse, keyboard])

        actions.moveBluetoothDevices(
            from: IndexSet(integer: 0),
            to: 2,
            displayedAddresses: resolvedRows.map(\.id)
        )

        XCTAssertEqual(settings.bluetoothDeviceOrder, [hidden, keyboard, ghost, mouse, beyondCollapsed])
        actions.moveBluetoothDevices(
            from: IndexSet(integer: 0),
            to: 1,
            displayedAddresses: resolvedRows.map(\.id)
        )
        XCTAssertEqual(settings.bluetoothDeviceOrder, [hidden, keyboard, ghost, mouse, beyondCollapsed], "A stale displayed prefix must not reorder current rows")
        let movedVisibleRows = BluetoothDeviceListModel.make(
            devices: bluetooth.devices,
            order: settings.bluetoothDeviceOrder,
            limit: settings.maxVisibleBluetoothDevices,
            isExpanded: false,
            options: settings.bluetoothDeviceListOptions
        ).visibleDevices
        XCTAssertEqual(movedVisibleRows.map(\.id), [keyboard, mouse])
        bluetooth.deactivate()
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for Bluetooth devices")
    }

    private func makeOutput(id: UInt32, uid: String?) -> AudioOutputDevice {
        AudioOutputDevice(id: AudioDeviceID(id), name: "Speaker", uid: uid, isCurrent: false)
    }
}

private final class PanelActionRoutingBluetoothReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let devices: [BluetoothDevice]

    init(_ devices: [BluetoothDevice]) { self.devices = devices }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(.success(devices))
    }
}

private final class PanelActionRoutingBluetoothBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}

@MainActor
private final class PanelActionRoutingBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() { onStateChange?(authorization, .poweredOn) }
    func stop() {}
}

@MainActor
private final class PanelActionRoutingBatteryMonitor: BatteryMonitoring {
    var updates: AsyncStream<BatteryStatus> { AsyncStream { $0.finish() } }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class PanelActionRoutingWiFiMonitor: WiFiMonitoring {
    var updates: AsyncStream<WiFiStatus> { AsyncStream { $0.finish() } }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class PanelActionRoutingVolumeMonitor: VolumeMonitoring {
    var updates: AsyncStream<VolumeStatus> { AsyncStream { $0.finish() } }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
    func setDisplayAsleep(_ asleep: Bool) {}
    func topologyChanged() {}
}
