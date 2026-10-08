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

    @Test func commonViewportReportsOnlyVisibleSelectedBLERows() {
        let visible = row(UUID())
        let clipped = row(UUID())
        let notInSharedLimit = row(UUID())
        let frames = [
            visible.id: CGRect(x: 10, y: 10, width: 40, height: 20),
            clipped.id: CGRect(x: 10, y: 300, width: 40, height: 20),
            notInSharedLimit.id: CGRect(x: 10, y: 20, width: 40, height: 20)
        ]

        #expect(NearbyBLEPanelVisibility.visibleSelectedIDs(
            in: [visible.device, clipped.device],
            frames: frames,
            viewport: CGRect(x: 0, y: 0, width: 100, height: 100)
        ) == [visible.id])
        #expect(NearbyBLEPanelVisibility.visibleSelectedIDs(
            in: [visible.device],
            frames: frames,
            viewport: .zero
        ).isEmpty)
    }

    @Test func edgeOnlyViewportContactHasNoVisibleArea() {
        let edgeOnly = UUID()
        let frames = [edgeOnly: CGRect(x: 10, y: 100, width: 40, height: 20)]

        #expect(NearbyBLEPanelVisibility.intersectingIDs(
            frames: frames,
            viewport: CGRect(x: 0, y: 0, width: 100, height: 100)
        ).isEmpty)
    }

    @Test func settingsProjectionKeepsOnlyUndiscoveredFreshVerifiedAppleRows() {
        let saved = NearbyBLEDeviceSelection(id: UUID(), name: "Saved", vendor: .apple, model: nil)
        let duplicate = UUID()
        let now = Date(timeIntervalSince1970: 30_000)
        let verified = NearbyBLEDeviceSelection(
            id: duplicate, name: "Verified", vendor: .apple, model: nil,
            batteryLevel: 48, batteryLastUpdated: now
        )

        let rows = NearbyBLEDeviceCatalog.settingsCandidates(selections: [saved, verified], now: now)

        #expect(rows.map(\.id) == [verified.id])
        #expect(rows[0].name == "Verified")
    }

    @Test func savedNonAppleMetadataDoesNotCreateASettingsCandidateRow() {
        let savedOther = NearbyBLEDeviceSelection(id: UUID(), name: "Old Mouse", vendor: .other, model: nil)
        let savedUnknown = NearbyBLEDeviceSelection(id: UUID(), name: "Unknown", vendor: .unknown, model: nil)

        let rows = NearbyBLEDeviceCatalog.settingsCandidates(
            selections: [savedOther, savedUnknown]
        )

        #expect(rows.isEmpty)
        #expect([savedOther, savedUnknown].map(\.id) == [savedOther.id, savedUnknown.id])
    }

    @Test func recentMissingReadingHasTheSameNeutralStatusForVisualAndAccessibility() {
        let recent = row(UUID(), batteryLevel: nil, wasSeenRecently: true, readFailed: false)
        let absent = row(UUID(), batteryLevel: nil, wasSeenRecently: false, readFailed: false)

        #expect(recent.status == .pending)
        #expect(absent.status == .notNearby)
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
