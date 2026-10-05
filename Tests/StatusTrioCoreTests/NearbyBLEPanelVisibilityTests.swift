import Foundation
import Testing
@testable import StatusTrioCore

struct NearbyBLEPanelVisibilityTests {
    @Test func selectionOrHiddenChangesDoNotInvalidateExistingVisibleGeometry() {
        #expect(!NearbyBLEPanelVisibility.shouldClearVisibleIDs(
            enabled: true, batteryLevelsEnabled: true, showsList: true
        ))
        #expect(NearbyBLEPanelVisibility.shouldClearVisibleIDs(
            enabled: true, batteryLevelsEnabled: false, showsList: true
        ))
        #expect(NearbyBLEPanelVisibility.shouldClearVisibleIDs(
            enabled: true, batteryLevelsEnabled: true, showsList: false
        ))
    }

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

        #expect(rows.map(\.id) == [nearby.id, saved.id])
        #expect(rows[1].name == "New broadcast name")
    }

    @Test func settingsUnionSortsTheWholeListAppleFirstIncludingSavedSelections() {
        let savedOther = NearbyBLEDeviceSelection(id: UUID(), name: "Z saved", vendor: .other, model: nil)
        let apple = NearbyBLEDeviceCandidate(id: UUID(), name: "Phone", vendor: .apple, lastSeen: .now)
        let other = NearbyBLEDeviceCandidate(id: UUID(), name: "A nearby", vendor: .other, lastSeen: .now)

        let rows = NearbyBLEDeviceCatalog.settingsCandidates(
            selections: [savedOther], candidates: [other, apple]
        )

        #expect(rows.map(\.id) == [apple.id, other.id, savedOther.id])
    }

    @Test func recentMissingReadingHasTheSameNeutralStatusForVisualAndAccessibility() {
        let recent = row(UUID(), batteryLevel: nil, wasSeenRecently: true, readFailed: false)
        let absent = row(UUID(), batteryLevel: nil, wasSeenRecently: false, readFailed: false)

        #expect(recent.status == .pending)
        #expect(absent.status == .notNearby)
    }

    @Test func settingsOrderLabelsMarkNearbyBLESourceAndDisambiguateNames() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-00000000ABCD")!
        let device = BluetoothDevice(
            id: BluetoothDeviceIdentity.bleRowID(id), name: "Phone", kind: .unknown,
            isConnected: false, isReadOverTheAir: true
        )
        let label = BluetoothDeviceSettingsPresentation.orderLabel(
            device: device,
            nearbyBLENames: [id: "Phone · ABCD"],
            fallback: "Nearby",
            nearbySource: "Nearby BLE"
        )

        #expect(label.title == "Phone · ABCD")
        #expect(label.source == "Nearby BLE")
    }

    private func row(
        _ id: UUID,
        batteryLevel: Int? = nil,
        wasSeenRecently: Bool = false,
        readFailed: Bool = false
    ) -> NearbyBLEPanelRow {
        NearbyBLEPanelRow(
            id: id,
            device: BluetoothDevice(id: BluetoothDeviceIdentity.bleRowID(id), name: "BLE", kind: .unknown, isConnected: false, isReadOverTheAir: true),
            batteryLevel: batteryLevel,
            wasSeenRecently: wasSeenRecently,
            readFailed: readFailed
        )
    }

    private func candidate(_ id: UUID, name: String) -> NearbyBLEDeviceCandidate {
        NearbyBLEDeviceCandidate(id: id, name: name, vendor: .unknown, lastSeen: Date())
    }
}
