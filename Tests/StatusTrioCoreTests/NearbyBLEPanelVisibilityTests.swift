import Foundation
import Testing
@testable import StatusTrioCore

struct NearbyBLEPanelVisibilityTests {
    @Test func noListOrZeroLimitHasNoReadEligibleRows() {
        let rows = [row(UUID()), row(UUID())]
        #expect(NearbyBLEPanelVisibility.eligibleIDs(rows: rows, showsList: false, limit: 2, expanded: true).isEmpty)
        #expect(NearbyBLEPanelVisibility.eligibleIDs(rows: rows, showsList: true, limit: 0, expanded: true).isEmpty)
    }

    @Test func collapsedUsesFirstLimitRowsAndExpandedUsesAllRows() {
        let rows = [row(UUID()), row(UUID()), row(UUID())]
        #expect(NearbyBLEPanelVisibility.eligibleIDs(rows: rows, showsList: true, limit: 2, expanded: false) == [rows[0].id, rows[1].id])
        #expect(NearbyBLEPanelVisibility.eligibleIDs(rows: rows, showsList: true, limit: 2, expanded: true) == Set(rows.map(\.id)))
    }

    @Test func rowWithoutBatteryIsStillEligible() {
        let noReading = row(UUID(), batteryLevel: nil)
        let hasReading = row(UUID(), batteryLevel: 14)
        #expect(NearbyBLEPanelVisibility.eligibleIDs(rows: [noReading, hasReading], showsList: true, limit: 2, expanded: false) == [noReading.id, hasReading.id])
    }

    @Test func viewportIntersectionIncludesOnlyPositiveVisibleArea() {
        let visible = UUID()
        let offscreen = UUID()
        let edgeOnly = UUID()
        let frames = [
            visible: CGRect(x: 10, y: 10, width: 40, height: 20),
            offscreen: CGRect(x: 10, y: 300, width: 40, height: 20),
            edgeOnly: CGRect(x: 10, y: 100, width: 40, height: 20)
        ]

        #expect(NearbyBLEPanelVisibility.intersectingIDs(frames: frames, viewport: CGRect(x: 0, y: 0, width: 100, height: 100)) == [visible])
        #expect(NearbyBLEPanelVisibility.intersectingIDs(frames: frames, viewport: .zero).isEmpty)
    }

    @Test func settingsUnionKeepsUndiscoveredSavedSelectionsAndDeduplicatesUUIDs() {
        let saved = NearbyBLEDeviceSelection(id: UUID(), name: "Saved", vendor: .other, model: nil)
        let duplicate = candidate(saved.id, name: "New broadcast name")
        let nearby = candidate(UUID(), name: "Nearby")

        let rows = NearbyBLEDeviceCatalog.settingsCandidates(selections: [saved], candidates: [duplicate, nearby])

        #expect(rows.map(\.id) == [saved.id, nearby.id])
        #expect(rows[0].name == "New broadcast name")
    }

    private func row(_ id: UUID, batteryLevel: Int? = nil) -> NearbyBLEPanelRow {
        NearbyBLEPanelRow(
            id: id,
            device: BluetoothDevice(id: BluetoothDeviceIdentity.bleRowID(id), name: "BLE", kind: .unknown, isConnected: false, isReadOverTheAir: true),
            batteryLevel: batteryLevel,
            wasSeenRecently: false,
            readFailed: false
        )
    }

    private func candidate(_ id: UUID, name: String) -> NearbyBLEDeviceCandidate {
        NearbyBLEDeviceCandidate(id: id, name: name, vendor: .unknown, lastSeen: Date())
    }
}
