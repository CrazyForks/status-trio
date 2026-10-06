import Foundation
import Testing
@testable import StatusTrioCore

struct MobileBatteryPresentationTests {
    @Test func externalRowsStayVisibleWhenBluetoothIsOffOrDenied() {
        let watch = BluetoothDevice(
            id: "mobile-57415443483A70686F6E653A7761746368",
            name: "Apple Watch",
            kind: .mobile(.watch),
            isConnected: false,
            isReadOverTheAir: true
        )
        let options = BluetoothDeviceListOptions.standard

        #expect(BluetoothMobileBatteryPanelVisibility.showsList(
            availability: .poweredOff,
            devices: [watch],
            pairedDevices: [],
            mobileDeviceIDs: [watch.id],
            showsMobileBatteryLevels: true,
            options: options
        ))
        #expect(BluetoothMobileBatteryPanelVisibility.showsList(
            availability: .authorizationDenied,
            devices: [watch],
            pairedDevices: [],
            mobileDeviceIDs: [watch.id],
            showsMobileBatteryLevels: true,
            options: options
        ))
        #expect(!BluetoothMobileBatteryPanelVisibility.showsList(
            availability: .available,
            devices: [watch],
            pairedDevices: [],
            mobileDeviceIDs: [watch.id],
            showsMobileBatteryLevels: false,
            options: options
        ))
    }

    @Test func externalWatchMixedWithUnmatchedNearbyUsesNeutralListHeading() {
        #expect(BluetoothDeviceListHeading.title(
            hasNearbyDevices: true,
            hasExternalMobileDevices: true
        ) == .bluetoothDevicesTitle)
        #expect(BluetoothDeviceListHeading.title(
            hasNearbyDevices: true,
            hasExternalMobileDevices: false
        ) == .bluetoothPairedDevicesTitle)
    }

    @Test func mobileClaimRequiresBothBatteryOptInsAndVisibleDeviceList() {
        #expect(BluetoothMobileBatteryPanelVisibility.shouldClaim(
            showsBatteryLevels: true,
            showsMobileBatteryLevels: true,
            options: BluetoothDeviceListOptions.standard
        ))
        #expect(!BluetoothMobileBatteryPanelVisibility.shouldClaim(
            showsBatteryLevels: false,
            showsMobileBatteryLevels: true,
            options: BluetoothDeviceListOptions.standard
        ))
        #expect(!BluetoothMobileBatteryPanelVisibility.shouldClaim(
            showsBatteryLevels: true,
            showsMobileBatteryLevels: false,
            options: BluetoothDeviceListOptions.standard
        ))
        #expect(!BluetoothMobileBatteryPanelVisibility.shouldClaim(
            showsBatteryLevels: true,
            showsMobileBatteryLevels: true,
            options: BluetoothDeviceListOptions(showsList: false, maxVisibleDevices: 5, order: [])
        ))
    }

    @Test func externalBatteryRowsRemainReadOnly() {
        let watch = BluetoothDevice(
            id: "mobile-57415443483A70686F6E653A7761746368",
            name: "Apple Watch",
            kind: .mobile(.watch),
            isConnected: false,
            isReadOverTheAir: true
        )

        #expect(!BluetoothDeviceActionPolicy.isActionable(watch))
    }

    @Test func pairedRowIdentifiedByMobileReadRemainsVisibleWhenBluetoothIsOff() {
        let phone = BluetoothDevice(
            id: "phone:phone-1", name: "Lina’s iPhone", kind: .mobile(.phone), isConnected: true
        )

        #expect(BluetoothMobileBatteryPanelVisibility.showsList(
            availability: .poweredOff,
            devices: [phone],
            pairedDevices: [phone],
            mobileDeviceIDs: [phone.id],
            showsMobileBatteryLevels: true,
            options: .standard
        ))
    }

    @Test func watchPresentationUsesLocalizedFallbackAndSource() {
        let watch = MobileBatterySnapshot(
            id: "watch-1", parentID: "phone-1", name: "  ", model: "Watch7,1",
            batteryLevel: 61, isCharging: nil, transport: .usb,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(MobileBatteryDeviceRowPresentation.displayName(watch, fallbackWatchName: "Apple Watch") == "Apple Watch")
        #expect(MobileBatteryDeviceRowPresentation.sourceText(watch, viaIPhone: "Via iPhone") == "Via iPhone")
        #expect(MobileBatteryDeviceRowPresentation.chargingText(watch, charging: "Charging") == nil)
    }
}

struct MobileBatteryFailurePresentationTests {
    @Test func mobileFailureRequiresAnActualFailureAndNoSnapshot() {
        #expect(MobileBatteryFailurePresentation.message(
            isEnabled: true,
            snapshots: [],
            failures: [],
            isRefreshing: false
        ) == nil)
        #expect(MobileBatteryFailurePresentation.message(
            isEnabled: true,
            snapshots: [],
            failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: "phone-1")],
            isRefreshing: true
        ) == nil)
        #expect(MobileBatteryFailurePresentation.message(
            isEnabled: false,
            snapshots: [],
            failures: [MobileBatteryReadFailure(category: "read-failed", deviceID: "phone-1")],
            isRefreshing: false
        ) == nil)
    }

    @Test func mobileFailureReportsRealUSBWiFiFailureAndTrustTakesPriority() {
        let readFailure = MobileBatteryReadFailure(category: "read-failed", deviceID: "phone-1")
        let trustFailure = MobileBatteryReadFailure(category: "trust-required", deviceID: "phone-1")
        #expect(MobileBatteryFailurePresentation.message(
            isEnabled: true,
            snapshots: [],
            failures: [readFailure],
            isRefreshing: false
        ) == .mobileBatteryUnavailable)
        #expect(MobileBatteryFailurePresentation.message(
            isEnabled: true,
            snapshots: [],
            failures: [readFailure, trustFailure],
            isRefreshing: false
        ) == .mobileBatteryTrustRequired)
        #expect(MobileBatteryFailurePresentation.message(
            isEnabled: true,
            snapshots: [MobileBatterySnapshot(
                id: "phone-1", parentID: nil, name: "iPhone", model: "iPhone18,1",
                batteryLevel: 80, isCharging: nil, transport: .usb,
                observedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )],
            failures: [readFailure],
            isRefreshing: false
        ) == nil)
    }
}
