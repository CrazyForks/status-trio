import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class PanelPresentationWiringTests: XCTestCase {
    func testBluetoothRowRequestsConfirmationBeforeTheSeparateConfirmCallbackActs() {
        let device = BluetoothDevice(
            id: "AA:BB",
            name: "Magic Keyboard",
            kind: .peripheral(.keyboard),
            isConnected: true
        )
        var confirmationAddress: String?
        var requestedAddresses: [String] = []
        var performedAddresses: [String] = []
        let actions = StatusPanelActions(
            bluetoothDevices: { [device] },
            performBluetoothAction: { performedAddresses.append($0.id) },
            requestDisconnect: {
                confirmationAddress = BluetoothBatteryReader.normalizedAddress($0.id)
                requestedAddresses.append($0.id)
            },
            disconnectConfirmationAddress: { confirmationAddress },
        )
        let localization = Localization(preferredLanguages: ["en"])
        let panelState = BluetoothPanelMapper.map(
            availability: .available,
            devices: [device],
            batteryLevels: [:],
            actionStates: [:],
            nearbyDevices: [],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 5, order: []),
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: false,
            confirmingAddress: nil,
            localization: localization
        )
        let rowState = try! XCTUnwrap(panelState.pairedRows.first)
        let row = BluetoothDeviceRow(
            state: rowState,
            isConfirmingDisconnect: false,
            onRowTapped: actions.rowTapped,
            onConfirmDisconnect: actions.confirmBluetoothDisconnect,
            onCancelDisconnect: actions.cancelDisconnect
        )

        row.onRowTapped(row.state.address)
        XCTAssertEqual(requestedAddresses, [device.id])
        XCTAssertTrue(performedAddresses.isEmpty, "a row tap must only request confirmation")

        let confirmationRow = BluetoothDeviceRow(
            state: rowState,
            isConfirmingDisconnect: true,
            onRowTapped: actions.rowTapped,
            onConfirmDisconnect: actions.confirmBluetoothDisconnect,
            onCancelDisconnect: actions.cancelDisconnect
        )
        confirmationRow.onConfirmDisconnect(confirmationRow.state.address)

        XCTAssertEqual(performedAddresses, [device.id], "the confirmation callback performs the action")
    }

    func testBluetoothSummaryKeepsAuthorizationAndPermissionSettingsCallbacksDistinct() {
        let localization = Localization(preferredLanguages: ["en"])
        let state = BluetoothPanelMapper.map(
            availability: .authorizationNotDetermined,
            devices: [],
            batteryLevels: [:],
            actionStates: [:],
            nearbyDevices: [],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: false,
            confirmingAddress: nil,
            localization: localization
        )
        var authorizationRequests = 0
        var settingsRequests = 0
        let view = BluetoothStatusView(
            state: state,
            actions: StatusPanelActions(),
            onSetExpanded: { _ in },
            onRequestAuthorization: { authorizationRequests += 1 },
            onOpenBluetoothSettings: {},
            onOpenBluetoothPermissionSettings: { settingsRequests += 1 }
        )

        XCTAssertEqual(state.summary.intent, .requestBluetoothAuthorization)
        view.onRequestAuthorization()
        XCTAssertEqual(authorizationRequests, 1)
        XCTAssertEqual(settingsRequests, 0)

        let deniedState = BluetoothPanelMapper.map(
            availability: .authorizationDenied,
            devices: [],
            batteryLevels: [:],
            actionStates: [:],
            nearbyDevices: [],
            batteryLevelsReadFailed: false,
            isExpanded: false,
            options: .standard,
            showsBatteryLevels: false,
            showsNearbyBatteryDevices: false,
            confirmingAddress: nil,
            localization: localization
        )
        let deniedView = BluetoothStatusView(
            state: deniedState,
            actions: StatusPanelActions(),
            onSetExpanded: { _ in },
            onRequestAuthorization: { authorizationRequests += 1 },
            onOpenBluetoothSettings: {},
            onOpenBluetoothPermissionSettings: { settingsRequests += 1 }
        )
        XCTAssertEqual(deniedState.summary.intent, .openBluetoothPermissionSettings)
        deniedView.onOpenBluetoothPermissionSettings()
        XCTAssertEqual(authorizationRequests, 1)
        XCTAssertEqual(settingsRequests, 1)
    }

    func testBatteryDetailsAppearanceAndBackCallbackPairTheCollectorLifecycle() async {
        var activations = 0
        var closes = 0
        let actions = StatusPanelActions(
            activateBatteryDetails: { _ in activations += 1 },
            closeBatteryDetails: { closes += 1 }
        )
        let localization = Localization(preferredLanguages: ["en"])
        let state = PanelDetailMapper.battery(
            status: BatteryStatus(
                rawPercentage: 80,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            details: nil,
            localization: localization
        )
        let appeared = expectation(description: "battery details start their collector when displayed")
        let view = BatteryDetailsView(
            state: state,
            onBack: { actions.batteryDetailsClosed() },
            onOpenBatterySettings: {},
            onCopyValue: { _ in },
            onAppear: {
                actions.batteryDetailsAppeared()
                appeared.fulfill()
            }
        )
        let hostingView = NSHostingView(rootView: view.environmentObject(localization))
        hostingView.frame = NSRect(x: 0, y: 0, width: 330, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        await fulfillment(of: [appeared], timeout: 1)
        XCTAssertEqual(activations, 1)

        view.onBack()
        XCTAssertEqual(closes, 1, "the back route closes the collector started by view appearance")
    }
}
