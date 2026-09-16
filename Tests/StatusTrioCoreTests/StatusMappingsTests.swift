import XCTest
@testable import StatusTrioCore

final class StatusMappingsTests: XCTestCase {
    func testWiFiSignalBoundaries() {
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -59), 3)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -60), 3)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -61), 2)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -78), 2)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -79), 1)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -88), 1)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -89), 0)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: nil), 0)
    }

    func testWiFiSummaryRequiresLocationPermissionBeforeOpeningAssociatedNetworkDetails() {
        let notDetermined = WiFiStatus(
            state: .connected,
            rssi: -50,
            nameAccess: .notDetermined
        )
        XCTAssertEqual(
            StatusMappings.wifiSummaryAction(for: notDetermined),
            .requestNameAccess
        )

        let authorized = WiFiStatus(
            state: .connected,
            rssi: -50,
            nameAccess: .authorized
        )
        XCTAssertEqual(
            StatusMappings.wifiSummaryAction(for: authorized),
            .openDetails
        )

        let denied = WiFiStatus(
            state: .connected,
            rssi: -50,
            nameAccess: .denied
        )
        XCTAssertEqual(
            StatusMappings.wifiSummaryAction(for: denied),
            .openLocationSettings
        )

        let unavailable = WiFiStatus(
            state: .unavailable,
            rssi: nil,
            nameAccess: .notDetermined
        )
        XCTAssertEqual(
            StatusMappings.wifiSummaryAction(for: unavailable),
            .openDetails
        )
    }

    func testVolumeBoundaries() {
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0, isMuted: false), 0)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: -0.1, isMuted: false), 0)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.01, isMuted: false), 1)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.25, isMuted: false), 1)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.26, isMuted: false), 2)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.50, isMuted: false), 2)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.51, isMuted: false), 3)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.75, isMuted: false), 3)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.76, isMuted: false), 4)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 1.0, isMuted: false), 4)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 1.1, isMuted: false), 4)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.8, isMuted: true), 0)
        XCTAssertNil(StatusMappings.volumeSteps(scalar: nil, isMuted: false))
    }

    func testBatteryProgress() {
        XCTAssertEqual(StatusMappings.batteryProgress(makeBattery(rawPercentage: 0)), 0.0)
        XCTAssertEqual(StatusMappings.batteryProgress(makeBattery(rawPercentage: 100)), 1.0)
        XCTAssertEqual(StatusMappings.batteryProgress(makeBattery(rawPercentage: -1)), 0.0)
        XCTAssertEqual(StatusMappings.batteryProgress(makeBattery(rawPercentage: 101)), 1.0)
    }

    func testBatteryColorPriority() {
        let normal = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
        XCTAssertEqual(StatusMappings.batteryColorRole(normal), .foreground)

        let lowPower = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: true,
            isConnectedToPower: false
        )
        XCTAssertEqual(StatusMappings.batteryColorRole(lowPower), .lowPower)

        let chargingOnly = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        XCTAssertEqual(StatusMappings.batteryColorRole(chargingOnly), .charging)

        let charging = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: true,
            isConnectedToPower: true
        )
        XCTAssertEqual(StatusMappings.batteryColorRole(charging), .lowPower)

        let connectedOnly = BatteryStatus(
            rawPercentage: 80,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        XCTAssertEqual(StatusMappings.batteryColorRole(connectedOnly), .charging)
    }

    func testBatteryCriticalThreshold() {
        let battery = makeBattery(rawPercentage: 20)

        XCTAssertEqual(StatusMappings.batteryColorRole(battery), .foreground)
        XCTAssertEqual(
            StatusMappings.batteryColorRole(battery, criticalThreshold: 20),
            .foreground
        )
        XCTAssertEqual(
            StatusMappings.batteryColorRole(
                makeBattery(rawPercentage: 19),
                criticalThreshold: 20
            ),
            .critical
        )
    }

    func testCriticalPrecedesLowPowerAndCharging() {
        let battery = BatteryStatus(
            rawPercentage: 19,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: true,
            isConnectedToPower: true
        )

        XCTAssertEqual(
            StatusMappings.batteryColorRole(battery, criticalThreshold: 20),
            .critical
        )
    }

    func testBatteryGapContentDecisionTable() {
        XCTAssertEqual(
            StatusMappings.batteryGapContent(chargingBattery(), options: .standard),
            .bolt
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(connectedBattery(), options: .standard),
            .plug
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(chargedOnPower(), options: .standard),
            .plug
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(makeBattery(rawPercentage: 80), options: .standard),
            .percentage
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(absentBattery(), options: .standard),
            .percentage
        )
    }

    func testBatteryGapContentUsesThePercentageForConnectedPowerWhenEnabled() {
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                connectedBattery(),
                options: batteryOptions(showsPercentageWhenConnected: true)
            ),
            .percentage
        )
    }

    func testBatteryGapContentKeepsTheBoltWhileCharging() {
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                chargingBattery(),
                options: batteryOptions(showsPercentageWhenConnected: true)
            ),
            .bolt
        )
    }

    func testBatteryGapContentFallsBackWhenNothingCanBeDrawn() {
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                connectedBattery(),
                options: batteryOptions(showsIndicator: false, showsPercentage: false)
            ),
            .empty
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                connectedBattery(),
                options: batteryOptions(showsIndicator: false)
            ),
            .percentage
        )
        XCTAssertEqual(
            StatusMappings.batteryGapContent(
                connectedBattery(),
                options: batteryOptions(
                    showsPercentage: false,
                    showsPercentageWhenConnected: true
                )
            ),
            .plug
        )
    }

    private func chargingBattery() -> BatteryStatus {
        BatteryStatus(
            rawPercentage: 80,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
    }

    private func connectedBattery() -> BatteryStatus {
        BatteryStatus(
            rawPercentage: 80,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
    }

    private func absentBattery() -> BatteryStatus {
        BatteryStatus(
            rawPercentage: nil,
            isPresent: false,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
    }

    private func batteryOptions(
        showsIndicator: Bool = true,
        showsPercentage: Bool = true,
        showsPercentageWhenConnected: Bool = false
    ) -> BatteryIconOptions {
        BatteryIconOptions(
            showsPercentage: showsPercentage,
            showsChargingIndicator: showsIndicator,
            usesStatusColors: true,
            criticalThreshold: 20,
            showsPercentageWhenConnected: showsPercentageWhenConnected
        )
    }

    private func chargedOnPower() -> BatteryStatus {
        BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: false,
            isCharged: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
    }

    private func makeBattery(rawPercentage: Int?) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: rawPercentage,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
    }
}
