import Foundation
import Testing
@testable import StatusTrioCore

struct NearbyBLEDeviceCatalogTests {
    @Test func selectedDeviceWithoutReadingRemainsVisibleAndAppleVendorDoesNotIdentifyFamily() {
        let selection = selection(name: "My Phone", vendor: .apple)

        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [selection],
            candidates: [],
            readings: [],
            failures: [],
            options: .standard,
            now: Date()
        )

        #expect(rows.count == 1)
        #expect(rows[0].batteryLevel == nil)
        #expect(!rows[0].device.isConnected)
        #expect(rows[0].device.id == BluetoothDeviceIdentity.bleRowID(selection.id))
        #expect(rows[0].device.kind == .unknown)
        #expect(rows[0].device.isReadOverTheAir)
        #expect(!rows[0].device.isUnpairedGhost)
    }

    @Test func zeroBatteryIsDifferentFromMissingAndExpiredReading() {
        let now = Date(timeIntervalSince1970: 10_000)
        let zero = selection(name: "Zero")
        let missing = selection(name: "Missing")
        let expired = selection(name: "Expired")
        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [zero, missing, expired],
            candidates: [],
            readings: [
                reading(zero.id, name: zero.name, level: 0, updatedAt: now),
                reading(expired.id, name: expired.name, level: 78, updatedAt: now.addingTimeInterval(-1_801))
            ],
            failures: [],
            options: .standard,
            now: now
        )

        #expect(rows.map(\.id) == [zero.id, missing.id, expired.id])
        #expect(rows.map(\.batteryLevel) == [0, nil, nil])
    }

    @Test func hiddenRowsAreFilteredAndSavedOrderBeatsAppleFirstDiscoveryOrder() {
        let apple = selection(name: "Apple", vendor: .apple)
        let other = selection(name: "Other", vendor: .other)
        let hidden = selection(name: "Hidden")
        let options = BluetoothDeviceListOptions(
            showsList: true,
            maxVisibleDevices: 5,
            order: [BluetoothDeviceIdentity.bleRowID(other.id), BluetoothDeviceIdentity.bleRowID(apple.id)],
            hiddenDeviceAddresses: [BluetoothDeviceIdentity.bleRowID(hidden.id)]
        )
        let candidates = [
            candidate(apple.id, name: apple.name, vendor: .apple),
            candidate(other.id, name: other.name, vendor: .other),
            candidate(hidden.id, name: hidden.name, vendor: .unknown)
        ]

        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [apple, other, hidden],
            candidates: candidates,
            readings: [],
            failures: [hidden.id],
            options: options,
            now: Date()
        )

        #expect(rows.map(\.id) == [other.id, apple.id])
        #expect(rows.map(\.wasSeenRecently) == [true, true])
        #expect(rows.allSatisfy { !$0.readFailed })
    }

    @Test func sameNamedSelectedUUIDsStayDistinctFromEachOtherAndSystemRows() {
        let first = selection(name: "Shared Name")
        let second = selection(name: "Shared Name")
        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [first, second],
            candidates: [],
            readings: [],
            failures: [],
            options: .standard,
            now: Date()
        )
        let system = BluetoothDevice(id: "AA:BB:CC:DD:EE:FF", name: "Shared Name", kind: .mobile(.phone), isConnected: true)

        #expect(rows.count == 2)
        #expect(rows[0].device.name == system.name && rows[1].device.name == system.name)
        #expect(rows[0].id != rows[1].id)
        #expect(rows.allSatisfy { !$0.device.isConnected })
        #expect(rows.allSatisfy { $0.device.id != system.id })
    }

    @Test func recentCandidateAndReadFailureAreReportedBySelectedUUIDOnly() {
        let now = Date(timeIntervalSince1970: 20_000)
        let fresh = selection(name: "Fresh")
        let stale = selection(name: "Stale")
        let stranger = UUID()
        let rows = NearbyBLEDeviceCatalog.panelRows(
            selections: [fresh, stale],
            candidates: [
                candidate(fresh.id, name: "Fresh", vendor: .apple, seenAt: now),
                candidate(stale.id, name: "Stale", vendor: .unknown, seenAt: now.addingTimeInterval(-61)),
                candidate(stranger, name: "Not selected", vendor: .other, seenAt: now)
            ],
            readings: [],
            failures: [fresh.id, stranger],
            options: .standard,
            now: now
        )

        #expect(rows.map(\.wasSeenRecently) == [true, false])
        #expect(rows.map(\.readFailed) == [true, false])
    }

    @Test func settingsDevicesUseNamespacedIdentityAndPreserveSelectionOrder() {
        let first = selection(name: "Same")
        let second = selection(name: "Same")
        let devices = NearbyBLEDeviceCatalog.settingsDevices(selections: [first, second])

        #expect(devices.map(\.id) == [BluetoothDeviceIdentity.bleRowID(first.id), BluetoothDeviceIdentity.bleRowID(second.id)])
        #expect(devices.allSatisfy { $0.kind == .unknown && !$0.isConnected && $0.isReadOverTheAir })
    }

    private func selection(name: String, vendor: NearbyBLEVendor = .unknown) -> NearbyBLEDeviceSelection {
        NearbyBLEDeviceSelection(id: UUID(), name: name, vendor: vendor, model: nil)
    }

    private func reading(_ id: UUID, name: String, level: Int, updatedAt: Date) -> NearbyBluetoothBatteryDevice {
        NearbyBluetoothBatteryDevice(id: id, name: name, batteryLevel: level, model: nil, manufacturer: nil, lastUpdated: updatedAt)
    }

    private func candidate(
        _ id: UUID,
        name: String,
        vendor: NearbyBLEVendor,
        seenAt: Date = Date()
    ) -> NearbyBLEDeviceCandidate {
        NearbyBLEDeviceCandidate(id: id, name: name, vendor: vendor, lastSeen: seenAt)
    }
}
