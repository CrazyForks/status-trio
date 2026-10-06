import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
@Suite struct AppleDeviceSettingsTests {
    @Test func sourceIDsAreDistinct() {
        let uuid = UUID(uuidString: "D0B64B72-63E2-45CE-A1B2-0F48E7EF83B8")!
        #expect(AppleDeviceID.ble(uuid).rowID == "ble:d0b64b72-63e2-45ce-a1b2-0f48e7ef83b8")
        #expect(AppleDeviceID.ble(uuid).rowID != AppleDeviceID.trustedDevice(uuid.uuidString).rowID)
        #expect(AppleDeviceID.trustedWatch(parentID: "a", id: "w") != .trustedWatch(parentID: "b", id: "w"))
    }

    @Test(arguments: [
        (false, false, false),
        (false, true, true),
        (true, false, true),
        (true, true, true)
    ])
    func legacySwitchesMigrateByLogicalOR(nearby: Bool, trusted: Bool, expected: Bool) {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(nearby, forKey: SettingsStore.showsNearbyBluetoothBatteryDevicesDefaultsKey)
        suite.defaults.set(trusted, forKey: SettingsStore.showsMobileDeviceBatteryLevelsDefaultsKey)

        let store = SettingsStore(defaults: suite.defaults)
        #expect(store.showsAppleDevicesAndBattery == expected)
        #expect(store.appleDeviceSelections.isEmpty)
    }

    @Test func absentLegacySwitchesDefaultOff() {
        let suite = makeSuite()
        defer { clear(suite) }
        let store = SettingsStore(defaults: suite.defaults)
        #expect(!store.showsAppleDevicesAndBattery)
        #expect(store.appleDeviceSelections.isEmpty)
    }

    @Test func migrationPreservesAppleAndArchivesOtherLegacyBLEChoicesIdempotently() throws {
        let suite = makeSuite()
        defer { clear(suite) }
        let appleID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let unknownID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let legacy = [
            NearbyBLEDeviceSelection(id: appleID, name: "Apple evidence", vendor: .apple, model: nil),
            NearbyBLEDeviceSelection(id: otherID, name: "iPhone", vendor: .other, model: nil),
            NearbyBLEDeviceSelection(id: unknownID, name: "Apple Watch", vendor: .unknown, model: nil)
        ]
        suite.defaults.set(try JSONEncoder().encode(legacy), forKey: SettingsStore.nearbyBLESelectionsDefaultsKey)

        let first = SettingsStore(defaults: suite.defaults)
        #expect(first.appleDeviceSelections.map(\.id) == [.ble(appleID)])
        #expect(first.archivedLegacyNearbyBLESelections == [legacy[1], legacy[2]])

        first.setAppleDeviceSelected(
            AppleDeviceCandidate(id: .ble(appleID), name: "Apple evidence", model: nil, transports: [.bluetooth], trustRequired: false, evidence: .appleBluetoothCompanyID),
            selected: false
        )
        let second = SettingsStore(defaults: suite.defaults)
        #expect(second.appleDeviceSelections.isEmpty)
        #expect(second.archivedLegacyNearbyBLESelections == [legacy[1], legacy[2]])
    }

    @Test func deselectionPersistsAndMasterSwitchDoesNotEraseChoices() {
        let suite = makeSuite()
        defer { clear(suite) }
        let id = UUID()
        let store = SettingsStore(defaults: suite.defaults)
        let candidate = AppleDeviceCandidate(id: .ble(id), name: "iPhone", model: nil, transports: [.bluetooth], trustRequired: false, evidence: .appleBluetoothCompanyID)
        store.setAppleDeviceSelected(candidate, selected: true)
        store.showsAppleDevicesAndBattery = false
        store.showsAppleDevicesAndBattery = true
        #expect(SettingsStore(defaults: suite.defaults).appleDeviceSelections.map(\.id) == [.ble(id)])
        store.setAppleDeviceSelected(candidate, selected: false)
        #expect(SettingsStore(defaults: suite.defaults).appleDeviceSelections.isEmpty)
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "AppleDeviceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removeTestSuite(named: suite.name)
    }
}
