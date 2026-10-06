import Foundation

@MainActor
struct AppleDeviceSettingsMigration {
    struct Result {
        let isEnabled: Bool
        let selections: [AppleDeviceSelection]
        let archivedLegacyBLESelections: [NearbyBLEDeviceSelection]
    }

    static let migrationVersion = 1

    static func migrate(defaults: UserDefaults) -> Result {
        let existingSelections = decodeArray([AppleDeviceSelection].self,
                                              from: defaults.data(forKey: SettingsStore.appleDeviceSelectionsDefaultsKey))
        let existingArchive = decodeArray([NearbyBLEDeviceSelection].self,
                                          from: defaults.data(forKey: SettingsStore.archivedLegacyNearbyBLESelectionsDefaultsKey))
        if defaults.integer(forKey: SettingsStore.appleDeviceSettingsMigrationVersionDefaultsKey) >= migrationVersion {
            return Result(
                isEnabled: defaults.object(forKey: SettingsStore.showsAppleDevicesAndBatteryDefaultsKey) as? Bool ?? false,
                selections: deduplicated(existingSelections),
                archivedLegacyBLESelections: deduplicatedLegacy(existingArchive)
            )
        }

        let legacyBLE = decodeArray([NearbyBLEDeviceSelection].self,
                                    from: defaults.data(forKey: SettingsStore.nearbyBLESelectionsDefaultsKey))
        var selections = existingSelections
        var archived = existingArchive
        var selectedIDs = Set(selections.map(\.id))
        for value in legacyBLE {
            if value.vendor == .apple {
                let id = AppleDeviceID.ble(value.id)
                if selectedIDs.insert(id).inserted {
                    selections.append(AppleDeviceSelection(id: id, name: value.name, model: value.model))
                }
            } else if !archived.contains(where: { $0.id == value.id }) {
                archived.append(value)
            }
        }

        let enabled = (defaults.object(forKey: SettingsStore.showsAppleDevicesAndBatteryDefaultsKey) as? Bool)
            ?? (defaults.bool(forKey: SettingsStore.showsNearbyBluetoothBatteryDevicesDefaultsKey)
                || defaults.bool(forKey: SettingsStore.showsMobileDeviceBatteryLevelsDefaultsKey))
        let result = Result(isEnabled: enabled,
                            selections: deduplicated(selections),
                            archivedLegacyBLESelections: deduplicatedLegacy(archived))

        // Write all snapshots before the marker so an interrupted migration is safely repeatable.
        defaults.set(enabled, forKey: SettingsStore.showsAppleDevicesAndBatteryDefaultsKey)
        if let data = try? JSONEncoder().encode(result.selections) {
            defaults.set(data, forKey: SettingsStore.appleDeviceSelectionsDefaultsKey)
        }
        if let data = try? JSONEncoder().encode(result.archivedLegacyBLESelections) {
            defaults.set(data, forKey: SettingsStore.archivedLegacyNearbyBLESelectionsDefaultsKey)
        }
        defaults.set(migrationVersion, forKey: SettingsStore.appleDeviceSettingsMigrationVersionDefaultsKey)
        return result
    }

    private static func decodeArray<Value: Decodable>(_ type: [Value].Type, from data: Data?) -> [Value] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode(type, from: data)) ?? []
    }

    private static func deduplicated(_ values: [AppleDeviceSelection]) -> [AppleDeviceSelection] {
        var seen = Set<AppleDeviceID>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func deduplicatedLegacy(_ values: [NearbyBLEDeviceSelection]) -> [NearbyBLEDeviceSelection] {
        var seen = Set<UUID>()
        return values.filter { seen.insert($0.id).inserted }
    }
}
