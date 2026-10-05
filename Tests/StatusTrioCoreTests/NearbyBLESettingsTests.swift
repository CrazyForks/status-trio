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

    @Test func sameNameSelectionsPersistByUUIDAndDeselectOnlyTheirOwnPreferences() {
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

    @Test func malformedSelectionDataLoadsAsEmptyAndDuplicateUUIDsAreDeduplicated() throws {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(Data("not json".utf8), forKey: SettingsStore.nearbyBLESelectionsDefaultsKey)
        #expect(SettingsStore(defaults: suite.defaults).nearbyBLESelections.isEmpty)

        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let values = [
            NearbyBLEDeviceSelection(id: id, name: "Old", vendor: .apple, model: nil),
            NearbyBLEDeviceSelection(id: id, name: "New", vendor: .apple, model: nil),
            NearbyBLEDeviceSelection(id: otherID, name: "Mouse", vendor: .other, model: nil)
        ]
        suite.defaults.set(try JSONEncoder().encode(values), forKey: SettingsStore.nearbyBLESelectionsDefaultsKey)

        #expect(SettingsStore(defaults: suite.defaults).nearbyBLESelections.map(\.id) == [id, otherID])
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
