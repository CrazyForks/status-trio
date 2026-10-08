import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The device list used to decide whether it needed a scroll view from the device
/// count alone, assuming every row was one line tall. A component-battery row now
/// renders two lines, so the count is no longer proof of the height: a list can
/// outgrow the 330-point bound well before it reaches the row count the old model
/// allowed. These tests hold the list to the summed-height model, and confirm a
/// short list — inline or component — still creates no `NSScrollView` at all.
@MainActor
final class BluetoothDeviceListLayoutTests: XCTestCase {
    /// A short component list is far under the bound, so it must lay out directly
    /// with no scroll region — the same care the inline list already took, now
    /// extended to taller rows.
    func testAShortComponentListDoesNotScroll() async throws {
        let (devices, levels) = componentDevices(3)
        let hosting = try renderList(devices: devices, batteryLevels: levels)
        defer { hosting.removeFromSuperview() }

        XCTAssertNil(
            firstScrollView(in: hosting),
            "three component rows are nowhere near the bound, so nothing should scroll"
        )
    }

    func testAliasResolvedMobileDetailsDriveTheActualScrollHeight() throws {
        let (devices, unchargedSnapshots) = mobileLayoutFixture(isCharging: false)
        let unchargedHosting = try renderList(
            devices: devices,
            batteryLevels: [:],
            mobileMetadataByDeviceID: unchargedSnapshots
        )
        defer { unchargedHosting.removeFromSuperview() }

        XCTAssertNil(
            firstScrollView(in: unchargedHosting),
            "metadata without a visible detail line must not inflate the viewport estimate"
        )

        let chargingHosting = try renderList(
            devices: devices,
            batteryLevels: [:],
            mobileMetadataByDeviceID: mobileLayoutFixture(isCharging: true).snapshots
        )
        defer { chargingHosting.removeFromSuperview() }

        XCTAssertNotNil(
            firstScrollView(in: chargingHosting),
            "a real charging detail line must count toward the viewport estimate"
        )
    }

    /// The regression the count model could not see. Twelve rows were exactly what
    /// the old `rowsThatFit` allowed — twelve inline rows still fit. But the same
    /// twelve rows, each carrying a component level, render two lines apiece and
    /// overflow the bound, so they have to scroll. Same count, opposite outcome:
    /// only the summed-height model produces this.
    func testTwelveComponentRowsScrollWhereTwelveInlineRowsFit() async throws {
        let (inlineDevices, inlineLevels) = mainDevices(12)
        let inlineHosting = try renderList(devices: inlineDevices, batteryLevels: inlineLevels)
        defer { inlineHosting.removeFromSuperview() }
        XCTAssertNil(
            firstScrollView(in: inlineHosting),
            "twelve single-line rows still fit inside the bound"
        )

        let (componentDevices, componentLevels) = componentDevices(12)
        let componentHosting = try renderList(devices: componentDevices, batteryLevels: componentLevels)
        defer { componentHosting.removeFromSuperview() }
        let scrolling = try XCTUnwrap(
            firstScrollView(in: componentHosting),
            "twelve two-line rows overflow the bound and must scroll, even though the count fits"
        )
        XCTAssertLessThanOrEqual(
            scrolling.frame.height,
            BluetoothDeviceList.maximumRowsHeight + 1,
            "the scroll region has to stop at the list's own bound"
        )
    }

    /// A mixed list is measured by each row's own type, not `deviceCount * pitch`.
    /// Sixteen inline rows overflow on their own; the interesting case is a blend
    /// whose component rows alone push it past the bound the count of inline rows
    /// would have cleared. Here eight inline plus eight component rows must scroll,
    /// where eight inline plus eight rows the model miscounted as inline would not.
    func testMixedRowsAreMeasuredByTheirRealHeight() async throws {
        var devices: [BluetoothDevice] = []
        var levels: [String: BluetoothBatteryLevel] = [:]
        for index in 1...8 {
            let main = makeDevice(index, name: "Mouse \(index)")
            devices.append(main)
            levels[BluetoothBatteryReader.normalizedAddress(main.id)] =
                BluetoothBatteryLevel(deviceAddress: main.id, main: 60, left: nil, right: nil, caseLevel: nil)
            let component = makeDevice(index + 100, name: "Buds \(index)")
            devices.append(component)
            levels[BluetoothBatteryReader.normalizedAddress(component.id)] =
                BluetoothBatteryLevel(deviceAddress: component.id, main: nil, left: 85, right: nil, caseLevel: nil)
        }

        let hosting = try renderList(devices: devices, batteryLevels: levels)
        defer { hosting.removeFromSuperview() }

        // 8 inline (24) + 8 component (30) + 15 gaps (2) = 432 + 30 = well past 330.
        let scrolling = try XCTUnwrap(
            firstScrollView(in: hosting),
            "the component rows have to be counted at their two-line height"
        )
        XCTAssertLessThanOrEqual(
            scrolling.frame.height,
            BluetoothDeviceList.maximumRowsHeight + 1,
            "the blended list still stops at the bound"
        )
    }

    // MARK: - Fixtures

    private func makeDevice(_ index: Int, name: String) -> BluetoothDevice {
        BluetoothDevice(
            id: String(format: "AA:00:00:00:00:%02X", index),
            name: name,
            kind: .audio,
            isConnected: true
        )
    }

    private func mainDevices(_ count: Int) -> ([BluetoothDevice], [String: BluetoothBatteryLevel]) {
        var devices: [BluetoothDevice] = []
        var levels: [String: BluetoothBatteryLevel] = [:]
        for index in 1...count {
            let device = makeDevice(index, name: "Device \(index)")
            devices.append(device)
            levels[BluetoothBatteryReader.normalizedAddress(device.id)] =
                BluetoothBatteryLevel(deviceAddress: device.id, main: 50, left: nil, right: nil, caseLevel: nil)
        }
        return (devices, levels)
    }

    private func componentDevices(_ count: Int) -> ([BluetoothDevice], [String: BluetoothBatteryLevel]) {
        var devices: [BluetoothDevice] = []
        var levels: [String: BluetoothBatteryLevel] = [:]
        for index in 1...count {
            let device = makeDevice(index, name: "Device \(index)")
            devices.append(device)
            levels[BluetoothBatteryReader.normalizedAddress(device.id)] =
                BluetoothBatteryLevel(deviceAddress: device.id, main: nil, left: 85, right: 80, caseLevel: 70)
        }
        return (devices, levels)
    }

    private func mobileLayoutFixture(
        isCharging: Bool
    ) -> (devices: [BluetoothDevice], snapshots: [String: MobileBatterySnapshot]) {
        var devices: [BluetoothDevice] = []
        var snapshots: [String: MobileBatterySnapshot] = [:]
        for index in 1...12 {
            let name = "iPhone \(index)"
            let phoneID = "phone-\(index)"
            let bleID = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", index))!
            let ble = BluetoothDevice(
                id: BluetoothDeviceIdentity.bleRowID(bleID),
                name: name,
                kind: .mobile(.phone),
                isConnected: false,
                appleMobileModel: "iPhone18,1",
                isReadOverTheAir: true
            )
            let trustedID = AppleDeviceID.trustedDevice(phoneID).rowID
            let trusted = BluetoothDevice(
                id: trustedID,
                name: name,
                kind: .mobile(.phone),
                isConnected: false,
                appleMobileModel: "iPhone18,1",
                isReadOverTheAir: true
            )
            devices.append(contentsOf: [ble, trusted])
            snapshots[trustedID] = MobileBatterySnapshot(
                id: phoneID,
                parentID: nil,
                name: name,
                model: "iPhone18,1",
                batteryLevel: 61,
                isCharging: isCharging,
                transport: .bluetooth,
                observedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            )
        }
        return (devices, snapshots)
    }

    // MARK: - Harness

    /// Renders the device list at the width the panel gives it, every device
    /// visible, so the only thing deciding a scroll view is the list's own height
    /// model. The `BluetoothDeviceList` is driven directly — not through the whole
    /// panel — to isolate the rows from the summary and the expansion control.
    private func renderList(
        devices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel],
        mobileMetadataByDeviceID: [String: MobileBatterySnapshot] = [:]
    ) throws -> NSHostingView<AnyView> {
        let suite = "StatusTrioCoreTests.BluetoothDeviceList.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])

        let list = BluetoothDeviceList(
            devices: devices,
            batteryLevels: batteryLevels,
            mobileMetadataByDeviceID: mobileMetadataByDeviceID,
            actionStates: [:],
            confirmingAddress: nil,
            options: BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: devices.count, order: []),
            onPerformAction: { _ in },
            onRequestDisconnect: { _ in },
            onCancelDisconnect: {}
        )
        .padding(14)
        .frame(width: 330)
        .background(Color(white: 0.96))
        .environmentObject(localization)
        .environment(\.colorScheme, .light)

        let hosting = NSHostingView(rootView: AnyView(list))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        var pending = view.subviews
        while let next = pending.popLast() {
            if let scrollView = next as? NSScrollView { return scrollView }
            pending.append(contentsOf: next.subviews)
        }
        return nil
    }
}
