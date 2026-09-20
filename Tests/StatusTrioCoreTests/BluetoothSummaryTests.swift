import XCTest
@testable import StatusTrioCore

/// The popover's Bluetooth row shows live device state: device names once the
/// app is authorized, and the battery level only for connected AirPods.
@MainActor
final class BluetoothSummaryTests: XCTestCase {
    private func device(
        id: String = "1",
        name: String,
        kind: BluetoothDeviceKind = .audio,
        isConnected: Bool = true,
        airPodsModel: AirPodsModel? = nil
    ) -> BluetoothDevice {
        BluetoothDevice(
            id: id,
            name: name,
            kind: kind,
            isConnected: isConnected,
            airPodsModel: airPodsModel
        )
    }

    /// The deciding rule is "AirPods only": it drives both the text and whether
    /// the battery reader runs at all. Either signal identifies the model — the
    /// product ID the profiler reports, or the name — and either one alone is
    /// enough.
    func testOnlyConnectedAudioDevicesIdentifiedAsAirPodsCountAsAirPods() {
        XCTAssertTrue(device(name: "AirPods Pro").isAirPods)
        XCTAssertTrue(device(name: "airpods max").isAirPods)
        XCTAssertTrue(device(name: "小王的耳机", airPodsModel: .airPods).isAirPods)
        XCTAssertFalse(device(name: "Sony WH-1000XM5").isAirPods)
        XCTAssertFalse(device(name: "Magic Mouse", kind: .peripheral).isAirPods)
        // The audio class is required: another class never claims a level, even
        // if an AirPods product ID reached it.
        XCTAssertFalse(device(name: "Magic Mouse", kind: .peripheral, airPodsModel: .airPods).isAirPods)
        // A paired but disconnected accessory is not what the row reports.
        XCTAssertFalse(device(name: "AirPods Pro", isConnected: false).isAirPodsSummaryCandidate)
        XCTAssertFalse(
            device(name: "小王的耳机", isConnected: false, airPodsModel: .airPods)
                .isAirPodsSummaryCandidate
        )
    }

    /// A user who renamed their AirPods gets no help from the name, so the row
    /// has to report the level the product ID identifies.
    func testRenamedAirPodsShowTheirBatteryLevel() {
        let summary = BluetoothSummary.presentation(
            availability: .available,
            devices: [device(id: "AA", name: "小王的耳机", airPodsModel: .airPods)],
            batteryLevels: ["AA": BluetoothBatteryLevel(
                deviceAddress: "AA", main: nil, left: 80, right: 75, caseLevel: 60)]
        )

        XCTAssertEqual(summary.deviceNames, "小王的耳机 · L 80% · R 75% · Case 60%")
        XCTAssertTrue(summary.hasConnectedAirPods)
    }

    /// Another vendor's earbuds keep the name-only rule, and a device whose
    /// product ID is not an AirPods never starts a level read.
    func testAnotherVendorsAudioDeviceIsNotAnAirPods() {
        XCTAssertFalse(device(name: "EDIFIER LolliPods 2022版").isAirPods)
        XCTAssertFalse(device(name: "小王的耳机").isAirPodsSummaryCandidate)
    }

    func testUnauthorizedBluetoothAsksForPermissionInsteadOfListingDevices() {
        let summary = BluetoothSummary.presentation(
            availability: .authorizationNotDetermined, devices: [], batteryLevels: [:])
        XCTAssertEqual(summary, .requestAuthorization)
    }

    func testDeniedAndRestrictedBluetoothKeepTheirOwnPrompts() {
        XCTAssertEqual(
            BluetoothSummary.presentation(availability: .authorizationDenied, devices: [], batteryLevels: [:]),
            .authorizationDenied
        )
        XCTAssertEqual(
            BluetoothSummary.presentation(availability: .authorizationRestricted, devices: [], batteryLevels: [:]),
            .authorizationRestricted
        )
    }

    func testConnectedDevicesAreJoinedWithAnIdeographicSeparator() {
        let summary = BluetoothSummary.presentation(
            availability: .available,
            devices: [device(id: "1", name: "AirPods Pro"),
                      device(id: "2", name: "MX Master 3", kind: .peripheral)],
            batteryLevels: [:]
        )
        XCTAssertEqual(summary.deviceNames, "AirPods Pro、MX Master 3")
    }

    /// AirPods carry their level inside the device entry, joined with the
    /// existing " · " separator so it reads as a property of the device rather
    /// than another device in the list.
    func testConnectedAirPodsShowTheirBatteryLevel() {
        let summary = BluetoothSummary.presentation(
            availability: .available,
            devices: [device(id: "AA", name: "AirPods Pro")],
            batteryLevels: ["AA": BluetoothBatteryLevel(
                deviceAddress: "AA", main: nil, left: 80, right: 75, caseLevel: 60)]
        )
        XCTAssertEqual(summary.deviceNames, "AirPods Pro · L 80% · R 75% · Case 60%")
    }

    func testAirPodsWithoutAReadableLevelShowOnlyTheirName() {
        let summary = BluetoothSummary.presentation(
            availability: .available,
            devices: [device(id: "AA", name: "AirPods Pro")],
            batteryLevels: [:]
        )
        XCTAssertEqual(summary.deviceNames, "AirPods Pro")
        // The level read is still worth running: the connected name is the
        // gate, not the presence of a readable level.
        XCTAssertTrue(summary.hasConnectedAirPods)
    }

    /// Other accessories stay name-only; their detail is the device page.
    func testNonAirPodsDevicesNeverShowBattery() {
        let summary = BluetoothSummary.presentation(
            availability: .available,
            devices: [device(id: "AA", name: "MX Master 3", kind: .peripheral)],
            batteryLevels: ["AA": BluetoothBatteryLevel(
                deviceAddress: "AA", main: 45, left: nil, right: nil, caseLevel: nil)]
        )
        XCTAssertEqual(summary.deviceNames, "MX Master 3")
        XCTAssertFalse(summary.hasConnectedAirPods)
    }

    /// The reader keys levels by normalized address, so the lookup has to
    /// normalize the device identifier the same way.
    func testBatteryLookupNormalizesTheDeviceAddress() {
        let summary = BluetoothSummary.presentation(
            availability: .available,
            devices: [device(id: "aa:bb:cc:dd:ee:ff", name: "AirPods Pro")],
            batteryLevels: ["AABBCCDDEEFF": BluetoothBatteryLevel(
                deviceAddress: "AABBCCDDEEFF", main: 64, left: nil, right: nil, caseLevel: nil)]
        )
        XCTAssertEqual(summary.deviceNames, "AirPods Pro · 64%")
    }

    func testAuthorizedBluetoothWithNothingConnectedSaysSo() {
        XCTAssertEqual(
            BluetoothSummary.presentation(availability: .available, devices: [], batteryLevels: [:]),
            .noConnectedDevices
        )
        XCTAssertEqual(
            BluetoothSummary.presentation(
                availability: .available,
                devices: [device(name: "Keyboard", kind: .peripheral, isConnected: false)],
                batteryLevels: [:]
            ),
            .noConnectedDevices
        )
    }

    func testUnavailableStatesMapToTheirOwnMessages() {
        let cases: [(BluetoothAvailability, BluetoothSummary)] = [
            (.initializing, .initializing),
            (.poweredOff, .poweredOff),
            (.unavailable, .unavailable),
            (.failed, .readFailed)
        ]
        for (availability, expected) in cases {
            XCTAssertEqual(
                BluetoothSummary.presentation(availability: availability, devices: [], batteryLevels: [:]),
                expected
            )
        }
    }

    /// Reading device names needs no CoreBluetooth grant, but starting the
    /// monitor is what raises the system prompt: only an already-authorized app
    /// may be activated on its own.
    func testOnlyAnAuthorizedAppIsActivatedWhenThePopoverOpens() {
        XCTAssertTrue(BluetoothPanelActivation.shouldActivate(authorization: .allowed))
        XCTAssertFalse(BluetoothPanelActivation.shouldActivate(authorization: .notDetermined))
        XCTAssertFalse(BluetoothPanelActivation.shouldActivate(authorization: .denied))
        XCTAssertFalse(BluetoothPanelActivation.shouldActivate(authorization: .restricted))
    }
}
