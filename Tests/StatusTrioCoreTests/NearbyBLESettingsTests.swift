import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
@Suite struct NearbyBLESettingsTests {
    @Test func nearbyFeatureUpgradeDoesNotSelectPreviouslyObservedDevices() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(true, forKey: SettingsStore.showsNearbyBluetoothBatteryDevicesDefaultsKey)

        #expect(SettingsStore(defaults: suite.defaults).nearbyBLESelections.isEmpty)
    }

    @Test func existingBLEUUIDMetadataSurvivesMigrationWithoutConsentSemantics() throws {
        let suite = makeSuite()
        defer { clear(suite) }
        let firstID = UUID(uuidString: "D625ED7E-322D-649D-19B4-33469BD00286")!
        let secondID = UUID(uuidString: "12D9DF08-0C3B-8A3E-3F1C-5189ABE60EB8")!
        let old = [
            NearbyBLEDeviceSelection(id: firstID, name: "Phone", vendor: .apple, model: nil),
            NearbyBLEDeviceSelection(id: secondID, name: "iPad", vendor: .apple, model: nil)
        ]
        suite.defaults.set(try JSONEncoder().encode(old), forKey: SettingsStore.nearbyBLEConsentDefaultsKey)

        #expect(SettingsStore(defaults: suite.defaults).nearbyBLESelections.map(\.id) == [firstID, secondID])
    }

    @Test func successfulReadRenameSurvivesRestartAndMasterOffWithoutAddingSameNamedUUID() throws {
        let suite = makeSuite()
        defer { clear(suite) }
        let id = UUID(), other = UUID()
        let store = SettingsStore(defaults: suite.defaults)
        store.setNearbyBLEDeviceSelected(.init(id: id, name: "Old", vendor: .apple, lastSeen: .now), selected: true)
        store.updateNearbyBLEMetadata([
            .init(id: id, name: "Renamed", batteryLevel: 75, model: "iPhone6,2", manufacturer: "Apple Inc.", lastUpdated: .now),
            .init(id: other, name: "Renamed", batteryLevel: 51, model: nil, manufacturer: "Apple Inc.", lastUpdated: .now)
        ])
        store.showsAppleDevicesAndBattery = false
        for _ in 0..<2 {
            let reloaded = SettingsStore(defaults: suite.defaults)
            #expect(reloaded.nearbyBLESelections.count == 2)
            let saved = try #require(reloaded.nearbyBLESelections.first { $0.id == id })
            #expect(saved.id == id)
            #expect(saved.name == "Renamed")
            #expect(reloaded.nearbyBLESelections.contains { $0.id == other })
            #expect(!reloaded.showsAppleDevicesAndBattery)
        }
    }

    @Test func sameNameMetadataPersistsByUUIDAndRemovalTouchesOnlyItsOwnPreferences() {
        let suite = makeSuite()
        defer { clear(suite) }
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let first = NearbyBLEDeviceCandidate(id: firstID, name: "Phone", vendor: .apple, lastSeen: .now)
        let second = NearbyBLEDeviceCandidate(id: secondID, name: "Phone", vendor: .apple, lastSeen: .now)
        let store = SettingsStore(defaults: suite.defaults)

        store.setNearbyBLEDeviceSelected(first, selected: true)
        store.setNearbyBLEDeviceSelected(second, selected: true)
        let firstKey = BluetoothDeviceIdentity.bleRowID(firstID)
        store.setBluetoothDeviceHidden(firstKey, hidden: true)
        #expect(SettingsStore(defaults: suite.defaults).nearbyBLESelections.map(\.id) == [firstID, secondID])

        store.setNearbyBLEDeviceSelected(first, selected: false)
        #expect(!store.bluetoothDeviceOrder.contains(firstKey))
        #expect(!store.hiddenBluetoothDeviceAddresses.contains(firstKey))
        #expect(store.bluetoothDeviceOrder.contains(BluetoothDeviceIdentity.bleRowID(secondID)))

        store.setNearbyBLEDeviceSelected(first, selected: true)
        #expect(!store.hiddenBluetoothDeviceAddresses.contains(firstKey))
        #expect(SettingsStore(defaults: suite.defaults).nearbyBLESelections.map(\.id) == [secondID, firstID])
    }

    @Test func archivedLegacyUUIDMetadataIsNotResurrected() throws {
        let suite = makeSuite()
        defer { clear(suite) }
        let oldID = UUID()
        suite.defaults.set(try JSONEncoder().encode([
            NearbyBLEDeviceSelection(id: oldID, name: "Old row", vendor: .apple, model: nil)
        ]), forKey: SettingsStore.archivedLegacyNearbyBLESelectionsDefaultsKey)

        #expect(SettingsStore(defaults: suite.defaults).nearbyBLESelections.isEmpty)
    }

    @Test func malformedSelectionDataLoadsAsEmptyAndDuplicateUUIDsAreDeduplicated() throws {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(Data("not json".utf8), forKey: SettingsStore.nearbyBLEConsentDefaultsKey)
        #expect(SettingsStore(defaults: suite.defaults).nearbyBLESelections.isEmpty)

        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let values = [
            NearbyBLEDeviceSelection(id: id, name: "Old", vendor: .apple, model: nil),
            NearbyBLEDeviceSelection(id: id, name: "New", vendor: .apple, model: nil),
            NearbyBLEDeviceSelection(id: otherID, name: "Mouse", vendor: .other, model: nil)
        ]
        suite.defaults.set(try JSONEncoder().encode(values), forKey: SettingsStore.nearbyBLEConsentDefaultsKey)

        #expect(SettingsStore(defaults: suite.defaults).nearbyBLESelections.map(\.id) == [id, otherID])
    }

    @Test func candidateDiscoveryDoesNotPersistOrCreateRows() {
        let suite = makeSuite()
        defer { clear(suite) }
        let selectedID = UUID()
        let unselectedID = UUID()
        let store = SettingsStore(defaults: suite.defaults)
        let selectedRowID = BluetoothDeviceIdentity.bleRowID(selectedID)
        store.setBluetoothDeviceHidden(selectedRowID, hidden: true)

        let candidates = [
            NearbyBLEDeviceCandidate(id: selectedID, name: "Current name", vendor: .apple, lastSeen: .now),
            NearbyBLEDeviceCandidate(id: unselectedID, name: "Nearby device", vendor: .apple, lastSeen: .now)
        ]
        #expect(NearbyBLEDeviceCatalog.settingsCandidates(selections: store.nearbyBLESelections).isEmpty)
        #expect(candidates.map(\.id) == [selectedID, unselectedID])
        #expect(store.nearbyBLESelections.isEmpty)
        #expect(store.hiddenBluetoothDeviceAddresses.contains(selectedRowID))
        #expect(!store.bluetoothDeviceOrder.contains(selectedRowID))
    }

    @Test func discoveryRefreshRepairsDuplicateSavedUUIDsWithoutResettingRowPreferences() throws {
        let suite = makeSuite()
        defer { clear(suite) }
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000081")!
        let duplicate = UUID(uuidString: "00000000-0000-0000-0000-000000000082")!
        let saved = [
            NearbyBLEDeviceSelection(id: id, name: "Old", vendor: .apple, model: "iPhone18,1"),
            NearbyBLEDeviceSelection(id: id, name: "Duplicate", vendor: .apple, model: nil),
            NearbyBLEDeviceSelection(id: duplicate, name: "Other", vendor: .apple, model: nil)
        ]
        suite.defaults.set(try JSONEncoder().encode(saved), forKey: SettingsStore.nearbyBLEConsentDefaultsKey)
        let store = SettingsStore(defaults: suite.defaults)
        let idRow = BluetoothDeviceIdentity.bleRowID(id)
        let duplicateRow = BluetoothDeviceIdentity.bleRowID(duplicate)
        store.setBluetoothDeviceHidden(idRow, hidden: true)
        let orderBefore = store.bluetoothDeviceOrder

        store.updateNearbyBLEMetadata([
            NearbyBluetoothBatteryDevice(id: id, name: "Current", batteryLevel: 73, model: "iPhone18,1", manufacturer: "Apple Inc.", lastUpdated: .now)
        ])
        let reloaded = SettingsStore(defaults: suite.defaults)

        #expect(reloaded.nearbyBLESelections.map(\.id) == [id, duplicate])
        #expect(reloaded.nearbyBLESelections.first?.name == "Current")
        #expect(reloaded.nearbyBLESelections.first?.model == "iPhone18,1")
        #expect(reloaded.nearbyBLESelections.first?.batteryLevel == 73)
        #expect(reloaded.hiddenBluetoothDeviceAddresses.contains(idRow))
        #expect(reloaded.bluetoothDeviceOrder == orderBefore)
        #expect(!reloaded.hiddenBluetoothDeviceAddresses.contains(duplicateRow))
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "NearbyBLESettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removePersistentDomain(forName: suite.name)
    }
}
