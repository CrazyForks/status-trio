import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

final class BatteryPowerBreakdownTests: XCTestCase {
    private let now = Date()

    private func sample(_ watts: Double, at offset: TimeInterval = 0) -> SystemPowerSample {
        SystemPowerSample(watts: watts, readAt: now.addingTimeInterval(offset))
    }

    private func usb(_ watts: Double, at offset: TimeInterval = 0) -> USBOutputSample {
        USBOutputSample(watts: watts, readAt: now.addingTimeInterval(offset), portCount: 1)
    }

    func testSplitsAdapterInputIntoMeasuredBranchesAndResidual() throws {
        let split = try XCTUnwrap(BatteryPowerBreakdown.resolve(
            input: sample(60, at: -1), charging: 10, display: sample(8, at: -1),
            soc: sample(30, at: -1), usb: usb(5, at: -1), now: now))
        XCTAssertEqual(split.inputWatts, 60)
        XCTAssertEqual(split.display?.watts, 8)
        XCTAssertEqual(split.usb?.watts, 5)
        XCTAssertEqual(split.soc.watts, 30)
        XCTAssertEqual(split.other.watts, 7, accuracy: 0.0001)
    }

    func testRejectsResidualThatCannotBeRounding() {
        // 20 W cannot pay for 4 W of charging, 8 W of backlight and 30 W of chip.
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            input: sample(20), charging: 4, display: sample(8), soc: sample(30),
            usb: nil, now: now))
    }

    func testTreatsSmallNegativeResidualAsRounding() throws {
        let split = try XCTUnwrap(BatteryPowerBreakdown.resolve(
            input: sample(43.6), charging: 0, display: sample(8), soc: sample(36),
            usb: nil, now: now))
        XCTAssertEqual(split.other.watts, 0)
    }

    func testRequiresEveryBranchToShareOneWindow() {
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            input: sample(60, at: -120), charging: 0, display: sample(8), soc: sample(30),
            usb: nil, now: now))
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            input: sample(60), charging: 0, display: sample(8, at: -120), soc: sample(30),
            usb: nil, now: now))
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            input: sample(60), charging: 0, display: sample(8), soc: sample(30, at: -120),
            usb: nil, now: now))
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            input: sample(60), charging: 0, display: sample(8), soc: sample(30),
            usb: usb(4, at: -120), now: now))
    }

    func testMissingAnchorsProduceNoSplit() {
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            input: nil, charging: 0, display: sample(8), soc: sample(30), usb: nil, now: now))
        // An unread charge rail would silently inflate the residual.
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            input: sample(60), charging: nil, display: sample(8), soc: sample(30), usb: nil, now: now))
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            input: sample(60), charging: 0, display: sample(8), soc: nil, usb: nil, now: now))
        XCTAssertNil(BatteryPowerBreakdown.resolve(
            input: sample(0), charging: 0, display: sample(8), soc: sample(30), usb: nil, now: now))
    }

    func testUnreadableDisplayStillLeavesACoherentSplit() throws {
        // Without PDBR the backlight disappears into the residual instead of
        // being invented from the system total.
        let split = try XCTUnwrap(BatteryPowerBreakdown.resolve(
            input: sample(50), charging: 0, display: nil, soc: sample(30), usb: nil, now: now))
        XCTAssertNil(split.display)
        XCTAssertEqual(split.other.watts, 20, accuracy: 0.0001)
    }

    func testUSBOutputReaderSumsPortsAndRejectsUnknownShapes() {
        let registry: [String: Any] = ["PowerOutDetails": [
            ["PortIndex": 1, "Watts": 7_000],
            ["PortIndex": 2, "PDPowermW": 5_000]
        ]]
        XCTAssertEqual(USBOutputReader.parse(registry: registry)?.watts, 12)
        XCTAssertEqual(USBOutputReader.parse(registry: registry)?.portCount, 2)
        XCTAssertNil(USBOutputReader.parse(registry: [:]), "no key means nothing is attached")
        XCTAssertNil(USBOutputReader.parse(registry: ["PowerOutDetails": []]))
        XCTAssertNil(USBOutputReader.parse(registry: ["PowerOutDetails": [["PortIndex": 1]]]),
                     "a port without a power value is not a zero-watt output")
        XCTAssertNil(USBOutputReader.parse(registry: ["PowerOutDetails": [["Watts": 900_000]]]))
    }
}

@MainActor
final class BatteryPowerBreakdownPresentationTests: XCTestCase {
    private func localization() throws -> (Localization, UserDefaults, String) {
        let suite = "BatteryPowerBreakdownPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (Localization(defaults: defaults, preferredLanguages: ["en"]), defaults, suite)
    }

    private func details(breakdown: BatteryPowerBreakdown?) -> BatteryDetails {
        let now = Date()
        return BatteryDetails(
            power: BatteryPowerSample(volts: 12, amps: 0.5, updatedAt: now),
            systemPower: SystemPowerSample(watts: 25, readAt: now),
            inputPower: SystemPowerSample(watts: 60, readAt: now),
            breakdown: breakdown
        )
    }

    private func breakdown() -> BatteryPowerBreakdown {
        let now = Date()
        let input = SystemPowerSample(watts: 60, readAt: now)
        return BatteryPowerBreakdown(
            inputWatts: 60,
            display: .init(watts: 8, readAt: now),
            soc: .init(watts: 30, readAt: now),
            usb: .init(watts: 5, readAt: now),
            other: .init(watts: 11, readAt: now),
            readAt: now
        )
    }

    func testSplitReplacesTheSystemNodeWithFiveBranches() throws {
        let (localization, defaults, suite) = try localization()
        defer { defaults.removeTestSuite(named: suite) }
        let status = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: true,
            isLowPowerMode: false, isConnectedToPower: true)
        let state = PanelDetailMapper.battery(status: status, details: details(breakdown: breakdown()),
            localization: localization,
            powerOptions: BatteryPowerDisplayOptions(showsInput: true, showsCharging: true,
                showsSystem: true, showsBreakdown: true))
        let flow = try XCTUnwrap(state.powerFlow)
        XCTAssertEqual(flow.destinations.map(\.kind), [.charging, .display, .usb, .soc, .other])
        XCTAssertEqual(flow.destinations.map(\.watts), [6, 8, 5, 30, 11])
        XCTAssertEqual(flow.input?.watts, 60)
        // Branch widths share one scale, bounded by the measured sum, not the
        // lagging system total.
        XCTAssertEqual(try XCTUnwrap(flow.flowFraction(for: flow.destinations[3])), 0.5, accuracy: 0.0001)
    }

    func testSwitchOffOrMissingSplitKeepsTheLegacyDiagram() throws {
        let (localization, defaults, suite) = try localization()
        defer { defaults.removeTestSuite(named: suite) }
        let status = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: true,
            isLowPowerMode: false, isConnectedToPower: true)

        let switchedOff = PanelDetailMapper.battery(status: status,
            details: details(breakdown: breakdown()), localization: localization,
            powerOptions: BatteryPowerDisplayOptions(showsInput: true, showsCharging: true,
                showsSystem: true, showsBreakdown: false))
        XCTAssertEqual(switchedOff.powerFlow?.destinations.map(\.kind), [.charging, .system])
        XCTAssertEqual(switchedOff.powerFlow?.system?.watts, 25)

        let unavailable = PanelDetailMapper.battery(status: status,
            details: details(breakdown: nil), localization: localization,
            powerOptions: BatteryPowerDisplayOptions(showsInput: true, showsCharging: true,
                showsSystem: true, showsBreakdown: true))
        XCTAssertEqual(unavailable.powerFlow?.destinations.map(\.kind), [.charging, .system])

        // The system total may never be relabelled as a measured "other".
        XCTAssertNil(unavailable.powerFlow?.destinations.first { $0.kind == .other })
    }

    func testSwitchIsPersistedIndependently() throws {
        let (_, defaults, suite) = try localization()
        defer { defaults.removeTestSuite(named: suite) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.showsPowerBreakdown)
        store.showsPowerBreakdown = false
        XCTAssertFalse(SettingsStore(defaults: defaults).showsPowerBreakdown)
        XCTAssertTrue(SettingsStore(defaults: defaults).showsSystemPower)
    }
}

@MainActor
final class BatteryPowerFlowLayoutTests: XCTestCase {
    /// Five branches must stay inside a compact column: tall enough to separate
    /// the nodes, short enough that the page below still fits the popover.
    func testFiveBranchDiagramUsesCompactHeight() {
        let metrics = (0..<5).map { index in
            BatteryPowerFlowState.Metric(label: "L\(index)", value: "\(index) W",
                                        watts: [41.21, 8.07, 4.5, 10.5, 2.72][index],
                                        kind: [BatteryPowerFlowState.Kind.charging, .display, .usb, .soc, .other][index])
        }
        let state = BatteryPowerFlowState(
            input: .init(label: "in", value: "67 W", watts: 67),
            destinations: metrics)
        let hosting = NSHostingView(rootView: BatteryPowerFlowView(state: state).frame(width: 302))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(hosting.fittingSize.height, 248, accuracy: 0.5)
    }
}
