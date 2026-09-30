import XCTest
@testable import StatusTrioCore

@MainActor
final class BluetoothPanelMapperTests: XCTestCase {
    func testMapperPreservesConnectedGroupsSavedOrderFiltersBatteryOptionsAndConfirmation() {
        let localization = makeLocalization()
        let devices = [
            device("AA:00:00:00:00:02", "Mouse", connected: false),
            device("AA:00:00:00:00:03", "AirPods", connected: true),
            device("AA:00:00:00:00:01", "Hidden", connected: true),
            device("AA:00:00:00:00:05", "Keyboard", connected: false),
            device("AA:00:00:00:00:04", "Ghost", connected: false, ghost: true)
        ]
        let state = BluetoothPanelMapper.map(
            availability: .available,
            devices: devices,
            batteryLevels: ["AA0000000003": BluetoothBatteryLevel(
                deviceAddress: "AA:00:00:00:00:03", main: 82, left: nil, right: nil, caseLevel: nil
            )],
            actionStates: [:],
            nearbyDevices: [nearby("Tracker", level: 42)],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: BluetoothDeviceListOptions(
                showsList: true,
                maxVisibleDevices: 2,
                order: ["AA0000000002", "AA0000000003"],
                hidesGhostDevices: true,
                hiddenDeviceAddresses: ["AA0000000001"]
            ),
            showsBatteryLevels: true,
            showsNearbyBatteryDevices: true,
            confirmingAddress: "AA0000000002",
            localization: localization
        )

        XCTAssertEqual(state.pairedRows.map(\.address), ["AA0000000003", "AA0000000002"])
        XCTAssertEqual(state.pairedRows[0].batteryText, "82%")
        XCTAssertEqual(state.pairedRows[1].batteryText, nil)
        XCTAssertEqual(state.nearbyRows.map(\.title), ["Tracker"])
        XCTAssertEqual(state.confirmationAddress, "AA0000000002")
        XCTAssertTrue(state.canExpand)
        XCTAssertTrue(state.showsPairedHeading)
    }

    func testMapperHidesBatteryRowsAndNearbyRowsWhenTheirSettingsAreOff() {
        let state = BluetoothPanelMapper.map(
            availability: .available,
            devices: [device("AA:00:00:00:00:01", "AirPods", connected: true)],
            batteryLevels: ["AA0000000001": BluetoothBatteryLevel(
                deviceAddress: "AA:00:00:00:00:01", main: 82, left: nil, right: nil, caseLevel: nil
            )],
            actionStates: [:],
            nearbyDevices: [nearby("Tracker", level: 42)],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: true,
            confirmingAddress: nil,
            localization: makeLocalization()
        )

        XCTAssertNil(state.pairedRows.first?.batteryText)
        XCTAssertTrue(state.nearbyRows.isEmpty)
    }

    func testMapperPresentsBatteryReadFailureOnlyWhenPairedRowsAreVisible() {
        let state = BluetoothPanelMapper.map(
            availability: .available,
            devices: [device("AA:00:00:00:00:01", "AirPods", connected: true)],
            batteryLevels: [:],
            actionStates: [:],
            nearbyDevices: [],
            batteryLevelsReadFailed: true,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: true,
            showsNearbyBatteryDevices: false,
            confirmingAddress: nil,
            localization: makeLocalization()
        )

        XCTAssertEqual(state.errorText, makeLocalization().string(.bluetoothBatteryUnavailable))
    }

    func testMapperKeepsBusyAndFailedActionTextAndMapsBluetoothRefreshFailure() {
        let localization = makeLocalization()
        let device = device("AA:00:00:00:00:01", "Headphones", connected: false)
        let state = BluetoothPanelMapper.map(
            availability: .failed,
            devices: [device],
            batteryLevels: [:],
            actionStates: ["AA0000000001": .failed(.connect)],
            nearbyDevices: [],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: false,
            confirmingAddress: "AA-00-00-00-00-01",
            localization: localization
        )

        XCTAssertTrue(state.pairedRows.isEmpty, "unavailable Bluetooth must not leave stale device rows visible")
        XCTAssertEqual(state.summary.subtitle, localization.string(.bluetoothReadFailed))
        XCTAssertEqual(state.confirmationAddress, "AA0000000001")

        let available = BluetoothPanelMapper.map(
            availability: .available,
            devices: [device],
            batteryLevels: [:],
            actionStates: ["AA0000000001": .failed(.connect)],
            nearbyDevices: [],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: false,
            confirmingAddress: nil,
            localization: localization
        )
        XCTAssertEqual(available.pairedRows[0].subtitle, localization.string(.bluetoothStateConnectFailed))
        XCTAssertTrue(available.pairedRows[0].actionEnabled)
        XCTAssertFalse(available.pairedRows[0].isBusy)

        let busy = BluetoothPanelMapper.map(
            availability: .available,
            devices: [device],
            batteryLevels: [:],
            actionStates: ["AA0000000001": .connecting],
            nearbyDevices: [],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: false,
            confirmingAddress: nil,
            localization: localization
        )
        XCTAssertFalse(busy.pairedRows[0].actionEnabled)
        XCTAssertTrue(busy.pairedRows[0].isBusy)
    }

    private func device(_ address: String, _ name: String, connected: Bool, ghost: Bool = false) -> BluetoothDevice {
        BluetoothDevice(id: address, name: name, kind: .audio, isConnected: connected, isUnpairedGhost: ghost)
    }

    private func nearby(_ name: String, level: Int) -> NearbyBluetoothBatteryDevice {
        NearbyBluetoothBatteryDevice(id: UUID(), name: name, batteryLevel: level, model: nil, manufacturer: nil, lastUpdated: Date())
    }

    private func makeLocalization() -> Localization {
        let suite = "BluetoothPanelMapperTests.\(UUID().uuidString)"
        return Localization(defaults: UserDefaults(suiteName: suite) ?? .standard, preferredLanguages: ["en"])
    }
}
