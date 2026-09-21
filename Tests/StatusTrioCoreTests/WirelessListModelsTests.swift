import AppKit
import XCTest
@testable import StatusTrioCore

final class WirelessListModelsTests: XCTestCase {
    func testWiFiMergePreservesWhitespaceInSSIDIdentity() {
        let candidates = [
            WiFiNetworkCandidate(
                ssid: " Studio ",
                bssid: "00:00:00:00:00:01",
                rssi: -70,
                channel: 1,
                security: .wpa2Personal
            ),
            WiFiNetworkCandidate(
                ssid: "Studio",
                bssid: "00:00:00:00:00:02",
                rssi: -40,
                channel: 1,
                security: .wpa2Personal
            )
        ]

        let merged = WiFiNetwork.merge(candidates, connectedBSSID: nil)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(Set(merged.map(\.ssid)), [" Studio ", "Studio"])
    }

    func testWiFiMergeNeverMixesDifferentSecurityTypes() {
        let candidates = [
            WiFiNetworkCandidate(ssid: "Office", bssid: "01", rssi: -45, channel: 44, security: .wpa2Personal),
            WiFiNetworkCandidate(ssid: "Office", bssid: "02", rssi: -50, channel: 44, security: .wpa3Personal)
        ]

        let merged = WiFiNetwork.merge(candidates, connectedBSSID: nil)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(Set(merged.map(\.security)), [.wpa2Personal, .wpa3Personal])
    }

    func testCoreWLANSecurityRawValuesPreserveOpenAndWPA3Identity() {
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: 0), .open)
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: 4), .wpa2Personal)
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: 13), .wpa3Transition)
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: 14), .owe)
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: Int.max), .unknown)
    }

    func testCurrentBSSIDWinsOverStrongestCandidateForConnectedState() {
        let candidates = [
            WiFiNetworkCandidate(ssid: "Studio", bssid: "01", rssi: -35, channel: 149, security: .wpa2Personal),
            WiFiNetworkCandidate(ssid: "Studio", bssid: "02", rssi: -68, channel: 36, security: .wpa2Personal)
        ]

        let network = try! XCTUnwrap(WiFiNetwork.merge(candidates, connectedBSSID: "02").first)

        XCTAssertTrue(network.isConnected)
        XCTAssertEqual(network.preferredCandidate?.bssid, "01")
        XCTAssertEqual(network.connectedBSSID, "02")
    }

    func testWiFiGroupingSeparatesKnownAndUnknownScannedNetworks() {
        let candidates = [
            WiFiNetworkCandidate(ssid: "Home", bssid: "01", rssi: -40, channel: 1, security: .wpa2Personal),
            WiFiNetworkCandidate(ssid: "Cafe", bssid: "02", rssi: -50, channel: 6, security: .wpa2Personal),
            WiFiNetworkCandidate(ssid: "Office", bssid: "03", rssi: -60, channel: 11, security: .wpa2Personal)
        ]
        let networks = WiFiNetwork.merge(
            candidates,
            connectedBSSID: "03",
            knownSSIDs: ["Home", "Office"]
        )

        let grouped = WiFiNetworkPresentation.grouped(networks)

        XCTAssertEqual(grouped.known.map(\.ssid), ["Office", "Home"])
        XCTAssertEqual(grouped.other.map(\.ssid), ["Cafe"])
    }

    func testEveryWiFiRowOpensSystemSettingsExceptTheConnectedOne() {
        let known = WiFiNetwork.merge(
            [
                WiFiNetworkCandidate(
                    ssid: "Home",
                    bssid: "01",
                    rssi: -40,
                    channel: 1,
                    security: .wpa2Personal
                )
            ],
            connectedBSSID: nil,
            knownSSIDs: ["Home"]
        )[0]
        let unknown = WiFiNetwork.merge(
            [
                WiFiNetworkCandidate(
                    ssid: "Cafe",
                    bssid: "01",
                    rssi: -40,
                    channel: 1,
                    security: .wpa2Personal
                )
            ],
            connectedBSSID: nil
        )[0]
        let connected = WiFiNetwork.merge(
            [
                WiFiNetworkCandidate(
                    ssid: "Office",
                    bssid: "01",
                    rssi: -40,
                    channel: 1,
                    security: .wpa2Personal
                )
            ],
            connectedBSSID: "01"
        )[0]

        XCTAssertEqual(WiFiNetworkPresentation.action(for: known), .openSettings)
        XCTAssertEqual(WiFiNetworkPresentation.action(for: unknown), .openSettings)
        XCTAssertEqual(WiFiNetworkPresentation.action(for: connected), .none)
    }

    func testDetailsToggleStatesTheActionItPerforms() {
        XCTAssertEqual(
            WiFiNetworkPresentation.detailsToggleTitleKey(isExpanded: false),
            .wifiDetailsShow
        )
        XCTAssertEqual(WiFiNetworkPresentation.detailsToggleSymbol(isExpanded: false), "info.circle")

        XCTAssertEqual(
            WiFiNetworkPresentation.detailsToggleTitleKey(isExpanded: true),
            .wifiDetailsHide
        )
        XCTAssertEqual(WiFiNetworkPresentation.detailsToggleSymbol(isExpanded: true), "chevron.up")
    }

    func testPreferredNetworkParserSkipsHeaderAndPreservesSSIDs() {
        let output = """
        Preferred networks on en0:
        \tHome
        \tCafe 5G
        """

        XCTAssertEqual(
            WiFiPreferredNetworkOutputParser.parse(output),
            ["Home", "Cafe 5G"]
        )
    }

    func testAsyncRequestGateRejectsLateResults() {
        var gate = AsyncRequestGate()
        let firstRequest = gate.advance()
        let currentRequest = gate.advance()

        XCTAssertFalse(gate.accepts(firstRequest))
        XCTAssertTrue(gate.accepts(currentRequest))
    }

    func testScanStatesRemainExplicit() {
        XCTAssertNotEqual(WiFiListState.scanning, .ready)
        XCTAssertNotEqual(WiFiListState.poweredOff, .noInterface)
        XCTAssertNotEqual(WiFiListState.permissionDenied, .failed)
        XCTAssertNotEqual(BluetoothAvailability.poweredOff, .unavailable)
    }

    func testAllowsRefreshFollowsTheScanState() {
        XCTAssertFalse(WiFiListState.scanning.allowsRefresh)
        XCTAssertTrue(WiFiListState.idle.allowsRefresh)
        XCTAssertTrue(WiFiListState.ready.allowsRefresh)
        XCTAssertTrue(WiFiListState.poweredOff.allowsRefresh)
        XCTAssertTrue(WiFiListState.permissionDenied.allowsRefresh)
    }

    func testSignalToNoiseRatioRejectsInvalidMeasurements() {
        let valid = makeDetails(rssi: -48, noise: -92)
        let unavailableRSSI = makeDetails(rssi: nil, noise: -92)
        let misleadingNoise = makeDetails(rssi: -48, noise: -20)

        XCTAssertEqual(valid.signalToNoiseRatio, 44)
        XCTAssertNil(unavailableRSSI.signalToNoiseRatio)
        XCTAssertNil(misleadingNoise.signalToNoiseRatio)
    }

    func testBluetoothGroupingKeepsConnectedDevicesFirst() {
        let devices = [
            BluetoothDevice(id: "1", name: "Zebra", kind: .audio, isConnected: false),
            BluetoothDevice(id: "2", name: "Alpha", kind: .computer, isConnected: true),
            BluetoothDevice(id: "3", name: "Bravo", kind: .phone, isConnected: true)
        ]

        let grouped = BluetoothDevicePresentation.grouped(devices)

        XCTAssertEqual(grouped.connected.map(\.name), ["Alpha", "Bravo"])
        XCTAssertEqual(grouped.disconnected.map(\.name), ["Zebra"])
    }

    func testWiFiServiceResolverUsesWiFiServiceRatherThanEthernetOrVPNGlobals() {
    let snapshot: [String: [String: Any]] = [
        "State:/Network/Global/IPv4": ["PrimaryService": "ethernet"],
        "State:/Network/Service/ethernet/Interface": ["DeviceName": "en0"],
        "State:/Network/Service/ethernet/IPv4": ["Router": "192.168.1.1"],
        "State:/Network/Service/vpn/Interface": ["DeviceName": "utun4"],
        "State:/Network/Service/vpn/DNS": ["ServerAddresses": ["10.0.0.53"]],
        "State:/Network/Service/wifi/Interface": ["DeviceName": "en1"],
        "State:/Network/Service/wifi/IPv4": ["Addresses": ["10.42.0.2"], "Router": "10.42.0.1"],
        "State:/Network/Service/wifi/IPv6": ["Addresses": ["fe80::42"]],
        "State:/Network/Service/wifi/DNS": ["ServerAddresses": ["10.42.0.1"]]
    ]
    let resolved = WiFiServiceNetworkConfiguration.resolve(interface: "en1", snapshot: snapshot)
    XCTAssertEqual(resolved.ipv4Addresses, ["10.42.0.2"])
    XCTAssertEqual(resolved.ipv6Addresses, ["fe80::42"])
    XCTAssertEqual(resolved.router, "10.42.0.1")
    XCTAssertEqual(resolved.dnsServers, ["10.42.0.1"])

    let ambiguous = WiFiServiceNetworkConfiguration.resolve(interface: "en9", snapshot: [
        "State:/Network/Service/a/Interface": ["DeviceName": "en9"],
        "State:/Network/Service/b/Interface": ["DeviceName": "en9"]
    ])
    XCTAssertNil(ambiguous.router)
    XCTAssertTrue(ambiguous.dnsServers.isEmpty)
}

func testBluetoothAvailabilityMappingKeepsAuthorizationAndAdapterStatesDistinct() {
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .notDetermined, managerState: .unknown),
            .authorizationNotDetermined
        )
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .denied, managerState: .poweredOn),
            .authorizationDenied
        )
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .restricted, managerState: .poweredOn),
            .authorizationRestricted
        )
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .allowed, managerState: .resetting),
            .initializing
        )
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .allowed, managerState: .poweredOff),
            .poweredOff
        )
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .allowed, managerState: .unsupported),
            .unavailable
        )
        XCTAssertEqual(
            BluetoothAvailabilityMapper.preliminary(authorization: .allowed, managerState: .poweredOn),
            .available
        )
    }

    @MainActor
    func testBluetoothControllerRefreshesPairedDevicesAcrossStateAndPanelLifecycle() async {
        let reader = BluetoothReaderStub(result: .success([
            BluetoothDevice(id: "connected", name: "Headphones", kind: .audio, isConnected: true),
            BluetoothDevice(id: "paired", name: "Keyboard", kind: .peripheral, isConnected: false)
        ]))
        let monitor = BluetoothStateMonitorStub(
            authorization: .allowed,
            managerState: .poweredOn
        )
        let notifications = NotificationCenter()
        let controller = BluetoothDeviceController(
            worker: reader,
            stateMonitor: monitor,
            notificationCenter: notifications,
            workspaceNotificationCenter: notifications
        )

        controller.activate()
        await Task.yield()

        XCTAssertEqual(controller.availability, .available)
        XCTAssertEqual(controller.connectedDevices.map(\.id), ["connected"])
        XCTAssertEqual(BluetoothDevicePresentation.grouped(controller.devices).disconnected.map(\.id), ["paired"])
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(monitor.startCount, 1)

        controller.activate()
        XCTAssertEqual(monitor.startCount, 1)

        monitor.emit(authorization: .allowed, managerState: .poweredOff)
        XCTAssertEqual(controller.availability, .poweredOff)

        monitor.emit(authorization: .allowed, managerState: .poweredOn)
        await Task.yield()
        XCTAssertEqual(controller.availability, .available)
        XCTAssertEqual(reader.readCount, 2)

        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()
        XCTAssertEqual(monitor.startCount, 2)
        XCTAssertEqual(reader.readCount, 3)

        controller.deactivate()
        XCTAssertEqual(monitor.stopCount, 1)
        notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()
        XCTAssertEqual(monitor.startCount, 2)

        controller.activate()
        await Task.yield()
        XCTAssertEqual(monitor.startCount, 3)
        controller.deactivate()
        XCTAssertEqual(monitor.stopCount, 2)
    }

    private func makeDetails(rssi: Int?, noise: Int?) -> WiFiConnectionDetails {
        WiFiConnectionDetails(
            ssid: "Studio",
            bssid: "01",
            band: nil,
            channel: nil,
            channelWidth: nil,
            rssi: rssi,
            noise: noise,
            phyMode: nil,
            transmitRateMbps: nil,
            security: .wpa2Personal,
            countryCode: nil,
            interfaceName: nil,
            ipv4Addresses: [],
            ipv6Addresses: [],
            router: nil,
            dnsServers: []
        )
    }
}

private final class BluetoothReaderStub: BluetoothPairedDeviceReading {
    private let result: BluetoothWorkerResult
    private(set) var readCount = 0

    init(result: BluetoothWorkerResult) {
        self.result = result
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        readCount += 1
        completion(result)
    }
}

@MainActor
private final class BluetoothStateMonitorStub: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    var authorization: BluetoothAuthorizationStatus
    private var managerState: BluetoothManagerState
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(authorization: BluetoothAuthorizationStatus, managerState: BluetoothManagerState) {
        self.authorization = authorization
        self.managerState = managerState
    }

    func start() {
        startCount += 1
        onStateChange?(authorization, managerState)
    }

    func stop() {
        stopCount += 1
    }

    func emit(authorization: BluetoothAuthorizationStatus, managerState: BluetoothManagerState) {
        self.authorization = authorization
        self.managerState = managerState
        onStateChange?(authorization, managerState)
    }
}
