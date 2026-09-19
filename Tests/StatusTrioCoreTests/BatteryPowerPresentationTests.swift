import Foundation
import XCTest
@testable import StatusTrioCore

final class BatteryPowerPresentationTests: XCTestCase {
    private let batteryTime = Date(timeIntervalSince1970: 100)
    private let systemTime = Date(timeIntervalSince1970: 125)

    func testConnectedUsesSystemPowerEvenWhenBatteryIsIdleOrCharging() {
        for amps in [0.0, 2, -1] {
            let details = BatteryDetails(
                power: BatteryPowerSample(volts: 12, amps: amps, updatedAt: batteryTime),
                systemPower: SystemPowerSample(watts: 17.25, readAt: systemTime))
            let row = BatteryPowerPresentation(details: details, isConnectedToPower: true)
            XCTAssertEqual(row.title, .batteryDetailsSystemPower)
            XCTAssertEqual(row.watts, 17.25)
            XCTAssertEqual(row.timestamp, systemTime)
            XCTAssertEqual(row.timestampTitle, .batteryDetailsSystemReadAt)
        }
    }

    func testDisconnectedUsesDischargeMagnitudeAndBatterySampleTime() {
        let details = BatteryDetails(
            power: BatteryPowerSample(volts: 12, amps: -1.5, updatedAt: batteryTime),
            systemPower: SystemPowerSample(watts: 17.25, readAt: systemTime))
        let row = BatteryPowerPresentation(details: details, isConnectedToPower: false)
        XCTAssertEqual(row.title, .batteryDetailsDischarging)
        XCTAssertEqual(row.watts, 18)
        XCTAssertEqual(row.timestamp, batteryTime)
        XCTAssertEqual(row.timestampTitle, .batteryDetailsSampled)
    }

    func testMissingSelectedSourceNeverFallsBackToTheOtherMetric() {
        let batteryOnly = BatteryDetails(power: BatteryPowerSample(volts: 12, amps: 0, updatedAt: batteryTime))
        let connected = BatteryPowerPresentation(details: batteryOnly, isConnectedToPower: true)
        XCTAssertNil(connected.watts)
        XCTAssertNil(connected.timestamp)
        XCTAssertEqual(connected.unavailableTitle, .batteryDetailsUnavailable)
        let systemOnly = BatteryDetails(powerAvailability: .collecting,
                                       systemPower: SystemPowerSample(watts: 17.25, readAt: systemTime))
        let unplugged = BatteryPowerPresentation(details: systemOnly, isConnectedToPower: false)
        XCTAssertNil(unplugged.watts)
        XCTAssertNil(unplugged.timestamp)
        XCTAssertEqual(unplugged.unavailableTitle, .batteryDetailsCollecting)
    }

    func testPowerSourceTransitionDoesNotShowAnOldChargingOrIdleBatteryAsDischarge() {
        for amps in [0.0, 2] {
            let details = BatteryDetails(power: BatteryPowerSample(volts: 12, amps: amps, updatedAt: batteryTime))
            let row = BatteryPowerPresentation(details: details, isConnectedToPower: false)
            XCTAssertNil(row.watts)
            XCTAssertNil(row.timestamp)
        }
    }

    func testChargingKeepsItsOwnRowOnExternalPower() {
        let charging = BatteryDetails(
            power: BatteryPowerSample(volts: 12, amps: 1.5, updatedAt: batteryTime),
            systemPower: SystemPowerSample(watts: 17.25, readAt: systemTime))
        let row = BatteryPowerPresentation(details: charging, isConnectedToPower: true)
        XCTAssertEqual(row.watts, 17.25, "The primary row stays the system total while charging")
        XCTAssertEqual(row.chargingWatts, 18)
    }

    func testChargeRowNeedsPositiveCurrentOnExternalPower() {
        let idle = BatteryPowerPresentation(
            details: BatteryDetails(power: BatteryPowerSample(volts: 12, amps: 0, updatedAt: batteryTime)),
            isConnectedToPower: true)
        XCTAssertNil(idle.chargingWatts, "An idle battery at a charge limit is not charging")
        let discharging = BatteryPowerPresentation(
            details: BatteryDetails(power: BatteryPowerSample(volts: 12, amps: -1.5, updatedAt: batteryTime)),
            isConnectedToPower: true)
        XCTAssertNil(discharging.chargingWatts, "Discharge is never reported as charge power")
        let unplugged = BatteryPowerPresentation(
            details: BatteryDetails(power: BatteryPowerSample(volts: 12, amps: 1.5, updatedAt: batteryTime)),
            isConnectedToPower: false)
        XCTAssertNil(unplugged.chargingWatts, "Charging cannot happen while unplugged")
    }
}
