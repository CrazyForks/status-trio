import XCTest
@testable import StatusTrioCore

/// The popover's Bluetooth row shows live device state: device names once the
/// app is authorized, and the level the report carries for each connected
/// device.
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

    /// The row reports the level the report carries for every connected device,
    /// not only for AirPods: a keyboard or mouse level is as useful there as the
    /// detail page already makes it.
    func testConnectedDevicesShowTheLevelTheReportCarries() {
        let summary = BluetoothSummary.presentation(
            availability: .available,
            devices: [device(id: "AA", name: "MX Master 3", kind: .peripheral)],
            batteryLevels: ["AA": BluetoothBatteryLevel(
                deviceAddress: "AA", main: 45, left: nil, right: nil, caseLevel: nil)]
        )

        XCTAssertEqual(summary.deviceNames, "MX Master 3 · 45%")
        XCTAssertTrue(summary.hasConnectedDevices)
    }

    /// A device the report has no level for keeps its name, so a row that mixes
    /// both kinds stays readable.
    func testDevicesWithoutALevelKeepTheirNameOnly() {
        let summary = BluetoothSummary.presentation(
            availability: .available,
            devices: [
                device(id: "AA", name: "机灵的耳机"),
                device(id: "BB", name: "MX Keys", kind: .peripheral)
            ],
            batteryLevels: ["AA": BluetoothBatteryLevel(
                deviceAddress: "AA", main: nil, left: 93, right: nil, caseLevel: nil)]
        )

        XCTAssertEqual(summary.deviceNames, "机灵的耳机 · L 93%、MX Keys")
        XCTAssertTrue(summary.hasConnectedDevices)
    }

    /// A renamed AirPods is just another device here: its level comes from the
    /// report, so the row never has to recognise the model.
    func testRenamedAirPodsShowTheirBatteryLevel() {
        let summary = BluetoothSummary.presentation(
            availability: .available,
            devices: [device(id: "AA", name: "小王的耳机", airPodsModel: .airPods)],
            batteryLevels: ["AA": BluetoothBatteryLevel(
                deviceAddress: "AA", main: nil, left: 80, right: 75, caseLevel: 60)]
        )

        XCTAssertEqual(summary.deviceNames, "小王的耳机 · L 80% · R 75% · Case 60%")
        XCTAssertTrue(summary.hasConnectedDevices)
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
        // The level read is still worth running: a connected device is the gate,
        // not the presence of a readable level.
        XCTAssertTrue(summary.hasConnectedDevices)
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
