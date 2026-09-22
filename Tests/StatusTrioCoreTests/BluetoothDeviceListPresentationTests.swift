import XCTest
@testable import StatusTrioCore

final class BluetoothDeviceListPresentationTests: XCTestCase {
    func testConnectedDevicesLeadAndOrderOnlyAppliesWithinAGroup() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "Mouse", isConnected: false),
            makeDevice(address: "AA:00:00:00:00:02", name: "Keyboard", isConnected: false),
            makeDevice(address: "AA:00:00:00:00:03", name: "AirPods", isConnected: true)
        ]

        // The saved order ranks a disconnected device first, but the group rule
        // wins: a drag can never lift it above a connected device. The stale
        // address matches no device and changes nothing.
        let ordered = BluetoothDeviceListPresentation.orderedDevices(
            devices,
            using: ["AA0000000001", "STALE-ADDRESS", "AA0000000003", "AA0000000002"]
        )

        XCTAssertEqual(ordered.map(\.name), ["AirPods", "Mouse", "Keyboard"])
    }

    func testUnlistedDevicesKeepIncomingOrderAfterRankedOnes() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "First", isConnected: true),
            makeDevice(address: "AA:00:00:00:00:02", name: "Second", isConnected: true),
            makeDevice(address: "AA:00:00:00:00:03", name: "Third", isConnected: true)
        ]

        let ordered = BluetoothDeviceListPresentation.orderedDevices(
            devices,
            using: ["AA0000000002"]
        )

        XCTAssertEqual(ordered.map(\.name), ["Second", "First", "Third"])
    }

    func testOrderEntriesAreNormalizedBeforeTheyRankDevices() {
        // A saved entry written with separators or in lowercase has to rank the
        // device it names. Before the order side was normalized too, these
        // entries silently ranked nothing and the list kept the system order.
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "First", isConnected: true),
            makeDevice(address: "AA:00:00:00:00:02", name: "Second", isConnected: true),
            makeDevice(address: "AA:00:00:00:00:03", name: "Third", isConnected: true)
        ]

        XCTAssertEqual(
            BluetoothDeviceListPresentation.orderedDevices(
                devices,
                using: ["aa:00:00:00:00:03", "AA-00-00-00-00-01"]
            ).map(\.name),
            ["Third", "First", "Second"]
        )
    }

    func testEmptyOrderKeepsGroupingOrder() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "Idle", isConnected: false),
            makeDevice(address: "AA:00:00:00:00:02", name: "Live", isConnected: true)
        ]

        XCTAssertEqual(
            BluetoothDeviceListPresentation.orderedDevices(devices, using: []).map(\.name),
            ["Live", "Idle"]
        )
    }

    func testConnectedDevicesFillTheLimitFirst() {
        // The disconnected device leads the fixture, so the expected result can
        // only come from the connected-first rule rather than from the incoming
        // order happening to already match it.
        let devices = [
            makeDevice(address: "AA:00:00:00:00:02", name: "Idle", isConnected: false),
            makeDevice(address: "AA:00:00:00:00:01", name: "Live", isConnected: true),
            makeDevice(address: "AA:00:00:00:00:03", name: "Idle2", isConnected: false)
        ]

        let model = BluetoothDeviceListModel.make(
            devices: devices,
            order: [],
            limit: 2,
            isExpanded: false
        )

        XCTAssertEqual(model.visibleDevices.map(\.name), ["Live", "Idle"])
        XCTAssertTrue(model.canToggleExpansion)
    }

    func testExpansionShowsEveryDeviceAndDisappearsWhenEverythingFits() {
        let devices = (1...3).map {
            makeDevice(address: "AA:00:00:00:00:0\($0)", name: "Device \($0)", isConnected: true)
        }

        XCTAssertEqual(
            BluetoothDeviceListPresentation.visibleDevices(from: devices, limit: 1, isExpanded: true)
                .map(\.name),
            ["Device 1", "Device 2", "Device 3"]
        )
        XCTAssertFalse(
            BluetoothDeviceListPresentation.canToggleExpansion(for: devices, limit: 3)
        )
        XCTAssertTrue(
            BluetoothDeviceListPresentation.canToggleExpansion(for: devices, limit: 2)
        )
        XCTAssertEqual(
            BluetoothDeviceListPresentation.visibleDevices(from: [], limit: 5, isExpanded: false),
            []
        )
    }

    func testListVisibilityFollowsAvailabilityAndEmptyState() {
        let devices = [
            makeDevice(address: "AA:00:00:00:00:01", name: "Idle", isConnected: false)
        ]
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 5, order: [])

        XCTAssertTrue(
            BluetoothPanelListVisibility.showsList(
                availability: .available,
                devices: devices,
                options: options
            )
        )
        XCTAssertFalse(
            BluetoothPanelListVisibility.showsList(
                availability: .poweredOff,
                devices: devices,
                options: options
            )
        )
        XCTAssertFalse(
            BluetoothPanelListVisibility.showsList(
                availability: .available,
                devices: [],
                options: options
            )
        )
        XCTAssertFalse(
            BluetoothPanelListVisibility.showsList(
                availability: .available,
                devices: devices,
                options: BluetoothDeviceListOptions(showsList: false, maxVisibleDevices: 5, order: [])
            )
        )
    }

    func testSubtitleIsReplacedOnlyWhenTheListCarriesConnectedNames() {
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 5, order: [])
        let connected = [makeDevice(address: "AA:00:00:00:00:01", name: "Live", isConnected: true)]
        let idle = [makeDevice(address: "AA:00:00:00:00:02", name: "Idle", isConnected: false)]

        XCTAssertTrue(
            BluetoothPanelListVisibility.hidesRowSubtitle(
                availability: .available,
                devices: connected,
                options: options
            )
        )
        // Nothing connected: the row keeps saying so, and the list still shows
        // the paired devices underneath.
        XCTAssertFalse(
            BluetoothPanelListVisibility.hidesRowSubtitle(
                availability: .available,
                devices: idle,
                options: options
            )
        )
        XCTAssertFalse(
            BluetoothPanelListVisibility.hidesRowSubtitle(
                availability: .available,
                devices: connected,
                options: BluetoothDeviceListOptions(showsList: false, maxVisibleDevices: 5, order: [])
            )
        )
    }

    private func makeDevice(
        address: String,
        name: String,
        isConnected: Bool
    ) -> BluetoothDevice {
        BluetoothDevice(id: address, name: name, kind: .audio, isConnected: isConnected)
    }
}
