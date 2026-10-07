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
        #expect((try? JSONDecoder().decode([LegacyAppleDeviceSelection].self, from: suite.defaults.data(forKey: SettingsStore.appleDeviceSelectionsDefaultsKey) ?? Data()))?.isEmpty == true)
    }

    @Test func absentLegacySwitchesDefaultOff() {
        let suite = makeSuite()
        defer { clear(suite) }
        let store = SettingsStore(defaults: suite.defaults)
        #expect(!store.showsAppleDevicesAndBattery)
        #expect(suite.defaults.data(forKey: SettingsStore.appleDeviceSelectionsDefaultsKey) == Data("[]".utf8))
    }

    @Test func migrationArchivesAllLegacyBLEChoicesWithoutGrantingAppleOwnership() throws {
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
        #expect(try JSONDecoder().decode([LegacyAppleDeviceSelection].self, from: suite.defaults.data(forKey: SettingsStore.appleDeviceSelectionsDefaultsKey) ?? Data()).isEmpty)
        #expect(first.archivedLegacyNearbyBLESelections == legacy)
        let second = SettingsStore(defaults: suite.defaults)
        #expect(try JSONDecoder().decode([LegacyAppleDeviceSelection].self, from: suite.defaults.data(forKey: SettingsStore.appleDeviceSelectionsDefaultsKey) ?? Data()).isEmpty)
        #expect(second.archivedLegacyNearbyBLESelections == legacy)
    }

    @Test func oldAppleBLESelectionIsNeverRestoredAsTrustedSelection() throws {
        let suite = makeSuite()
        defer { clear(suite) }
        let id = UUID()
        let oldSelection = LegacyAppleDeviceSelection(id: .ble(id), name: "iPhone", model: nil)
        suite.defaults.set(try JSONEncoder().encode([oldSelection]), forKey: SettingsStore.appleDeviceSelectionsDefaultsKey)
        suite.defaults.set(AppleDeviceSettingsMigration.migrationVersion, forKey: SettingsStore.appleDeviceSettingsMigrationVersionDefaultsKey)

        let store = SettingsStore(defaults: suite.defaults)
        #expect(try JSONDecoder().decode([LegacyAppleDeviceSelection].self, from: suite.defaults.data(forKey: SettingsStore.appleDeviceSelectionsDefaultsKey) ?? Data()).isEmpty)
        #expect(store.archivedLegacyNearbyBLESelections.map(\.id) == [id])
    }

    @Test func migrationKeepsPreviouslyVerifiedTrustedMetadataButNotBLESelection() throws {
        let suite = makeSuite()
        defer { clear(suite) }
        let nearbyID = UUID()
        let oldSelections = [
            LegacyAppleDeviceSelection(id: .ble(nearbyID), name: "Nearby Phone", model: "iPhone18,1"),
            LegacyAppleDeviceSelection(id: .trustedDevice("trusted-phone"), name: "Trusted Phone", model: "iPhone18,1"),
            LegacyAppleDeviceSelection(id: .trustedWatch(parentID: "trusted-phone", id: "watch-1"), name: "Watch", model: "Watch7,4")
        ]
        suite.defaults.set(try JSONEncoder().encode(oldSelections), forKey: SettingsStore.appleDeviceSelectionsDefaultsKey)

        let store = SettingsStore(defaults: suite.defaults)

        #expect(Set(store.trustedAppleDeviceMetadata.map(\.id)) == Set([
            .trustedDevice("trusted-phone"),
            .trustedWatch(parentID: "trusted-phone", id: "watch-1")
        ]))
        #expect(store.archivedLegacyNearbyBLESelections.map(\.id) == [nearbyID])
    }

    @Test func verifiedTrustedMetadataPersistsOfflineAndRenamesByStableIdentity() throws {
        let suite = makeSuite()
        defer { clear(suite) }
        let store = SettingsStore(defaults: suite.defaults)
        let first = trustedCandidate(name: "Old name", transports: [.usb])
        store.updateTrustedAppleDeviceMetadata([first])

        let renamed = trustedCandidate(name: "Renamed phone", transports: [.network])
        store.updateTrustedAppleDeviceMetadata([renamed])

        for current in [store, SettingsStore(defaults: suite.defaults), SettingsStore(defaults: suite.defaults)] {
            try #require(current.trustedAppleDeviceMetadata.count == 1)
            let metadata = try #require(current.trustedAppleDeviceMetadata.first)
            #expect(metadata.id == .trustedDevice("phone-1"))
            #expect(metadata.name == "Renamed phone")
            #expect(Set(metadata.transports) == Set([.usb, .network]))
        }
    }

    @Test(arguments: [false, true])
    func currentMigrationMarkerPreservesCacheAndMasterAcrossTwoReloads(enabled: Bool) throws {
        let suite = makeSuite()
        defer { clear(suite) }
        let cached = trustedCandidate(name: "Cached phone", transports: [.network])
        suite.defaults.set(try JSONEncoder().encode([cached]), forKey: SettingsStore.trustedAppleDeviceMetadataDefaultsKey)
        suite.defaults.set(AppleDeviceSettingsMigration.migrationVersion, forKey: SettingsStore.appleDeviceSettingsMigrationVersionDefaultsKey)
        suite.defaults.set(enabled, forKey: SettingsStore.showsAppleDevicesAndBatteryDefaultsKey)
        suite.defaults.set(!enabled, forKey: SettingsStore.showsMobileDeviceBatteryLevelsDefaultsKey)

        for _ in 0..<2 {
            let reloaded = SettingsStore(defaults: suite.defaults)
            #expect(reloaded.showsAppleDevicesAndBattery == enabled)
            try #require(reloaded.trustedAppleDeviceMetadata.count == 1)
            #expect(try #require(reloaded.trustedAppleDeviceMetadata.first) == cached)
        }
    }

    @Test(arguments: [false, true])
    func legacyMigrationRepeatMergesByIdentityAndPreservesCacheAndMaster(enabled: Bool) throws {
        let suite = makeSuite()
        defer { clear(suite) }
        let cached = trustedCandidate(name: "Latest name", transports: [.usb])
        let legacy = [
            LegacyAppleDeviceSelection(id: cached.id, name: "Old name", model: cached.model),
            LegacyAppleDeviceSelection(id: .trustedDevice("other-phone"), name: cached.name, model: "iPad16,1"),
            LegacyAppleDeviceSelection(id: .ble(UUID()), name: cached.name, model: "iPhone18,1")
        ]
        suite.defaults.set(try JSONEncoder().encode([cached]), forKey: SettingsStore.trustedAppleDeviceMetadataDefaultsKey)
        suite.defaults.set(try JSONEncoder().encode(legacy), forKey: SettingsStore.appleDeviceSelectionsDefaultsKey)
        suite.defaults.set(1, forKey: SettingsStore.appleDeviceSettingsMigrationVersionDefaultsKey)
        suite.defaults.set(enabled, forKey: SettingsStore.showsAppleDevicesAndBatteryDefaultsKey)
        suite.defaults.set(!enabled, forKey: SettingsStore.showsMobileDeviceBatteryLevelsDefaultsKey)

        for _ in 0..<2 {
            let reloaded = SettingsStore(defaults: suite.defaults)
            #expect(reloaded.showsAppleDevicesAndBattery == enabled)
            try #require(reloaded.trustedAppleDeviceMetadata.count == 2)
            let phone = try #require(reloaded.trustedAppleDeviceMetadata.first { $0.id == cached.id })
            #expect(phone.name == cached.name)
            #expect(Set(phone.transports) == Set([.usb, .network]))
            #expect(reloaded.trustedAppleDeviceMetadata.allSatisfy { $0.isVerifiedTrustedAppleDevice })
        }
    }

    @Test func invalidOrTrustRequiredMetadataIsNotPersisted() {
        let suite = makeSuite()
        defer { clear(suite) }
        let store = SettingsStore(defaults: suite.defaults)
        let nearbyApple = AppleDeviceCandidate(
            id: .ble(UUID()), name: "Nearby iPhone", model: nil,
            transports: [.bluetooth], trustRequired: false, evidence: .appleBluetoothCompanyID
        )
        let needsTrust = AppleDeviceCandidate(
            id: .trustedDevice("untrusted"), name: "Phone", model: "iPhone18,1",
            transports: [.usb], trustRequired: true, evidence: .verifiedAppleModel
        )

        store.updateTrustedAppleDeviceMetadata([nearbyApple, needsTrust])

        #expect(store.trustedAppleDeviceMetadata.isEmpty)
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

    private func trustedCandidate(name: String, transports: [MobileBatteryTransport]) -> AppleDeviceCandidate {
        AppleDeviceCandidate(
            id: .trustedDevice("phone-1"), name: name, model: "iPhone18,1",
            transports: transports, trustRequired: false, evidence: .verifiedAppleModel
        )
    }
}
