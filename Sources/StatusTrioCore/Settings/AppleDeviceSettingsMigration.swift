import Foundation

@MainActor
struct AppleDeviceSettingsMigration {
    struct Result {
        let isEnabled: Bool
        let archivedLegacyBLESelections: [NearbyBLEDeviceSelection]
        let trustedAppleDeviceMetadata: [AppleDeviceCandidate]
    }

    static let migrationVersion = 2

    static func migrate(defaults: UserDefaults) -> Result {
        let existingSelections = decodeArray([LegacyAppleDeviceSelection].self,
                                              from: defaults.data(forKey: SettingsStore.appleDeviceSelectionsDefaultsKey))
        let existingArchive = decodeArray([NearbyBLEDeviceSelection].self,
                                          from: defaults.data(forKey: SettingsStore.archivedLegacyNearbyBLESelectionsDefaultsKey))
        let legacyBLE = decodeArray([NearbyBLEDeviceSelection].self,
                                    from: defaults.data(forKey: SettingsStore.nearbyBLESelectionsDefaultsKey))
        var archived = existingArchive
        for value in legacyBLE {
            if !archived.contains(where: { $0.id == value.id }) {
                archived.append(value)
            }
        }
        for selection in existingSelections {
            guard case let .ble(id) = selection.id,
                  !archived.contains(where: { $0.id == id }) else { continue }
            archived.append(NearbyBLEDeviceSelection(
                id: id,
                name: selection.name,
                vendor: .apple,
                model: selection.model
            ))
        }

        let storedVersion = defaults.integer(forKey: SettingsStore.appleDeviceSettingsMigrationVersionDefaultsKey)
        let enabled = (defaults.object(forKey: SettingsStore.showsAppleDevicesAndBatteryDefaultsKey) as? Bool)
            ?? (storedVersion < migrationVersion && (defaults.bool(forKey: SettingsStore.showsNearbyBluetoothBatteryDevicesDefaultsKey)
                || defaults.bool(forKey: SettingsStore.showsMobileDeviceBatteryLevelsDefaultsKey)))
        let cachedMetadata = decodeArray([AppleDeviceCandidate].self,
                                         from: defaults.data(forKey: SettingsStore.trustedAppleDeviceMetadataDefaultsKey))
        let trustedMetadata = storedVersion < migrationVersion
            ? mergeTrustedMetadata(legacy: migratedTrustedMetadata(from: existingSelections), cached: cachedMetadata)
            : cachedMetadata.filter { $0.isVerifiedTrustedAppleDevice }
        let result = Result(isEnabled: enabled,
                            archivedLegacyBLESelections: deduplicatedLegacy(archived),
                            trustedAppleDeviceMetadata: trustedMetadata)

        // Write all snapshots before the marker so an interrupted migration is safely repeatable.
        if storedVersion < migrationVersion {
            defaults.set(enabled, forKey: SettingsStore.showsAppleDevicesAndBatteryDefaultsKey)
        }
        defaults.set(Data("[]".utf8), forKey: SettingsStore.appleDeviceSelectionsDefaultsKey)
        if let data = try? JSONEncoder().encode(result.archivedLegacyBLESelections) {
            defaults.set(data, forKey: SettingsStore.archivedLegacyNearbyBLESelectionsDefaultsKey)
        }
        if storedVersion < migrationVersion {
            if let data = try? JSONEncoder().encode(result.trustedAppleDeviceMetadata) {
                defaults.set(data, forKey: SettingsStore.trustedAppleDeviceMetadataDefaultsKey)
            }
            defaults.set(migrationVersion, forKey: SettingsStore.appleDeviceSettingsMigrationVersionDefaultsKey)
        }
        return result
    }

    private static func decodeArray<Value: Decodable>(_ type: [Value].Type, from data: Data?) -> [Value] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode(type, from: data)) ?? []
    }

    private static func deduplicatedLegacy(_ values: [NearbyBLEDeviceSelection]) -> [NearbyBLEDeviceSelection] {
        var seen = Set<UUID>()
        return values.filter { seen.insert($0.id).inserted }
    }

    /// The persisted discovery cache is newer than legacy selections. Merge only
    /// stable identities, preserving its latest name/model and known transports.
    private static func mergeTrustedMetadata(
        legacy: [AppleDeviceCandidate], cached: [AppleDeviceCandidate]
    ) -> [AppleDeviceCandidate] {
        var byID: [AppleDeviceID: AppleDeviceCandidate] = [:]
        for candidate in legacy + cached where candidate.isVerifiedTrustedAppleDevice {
            var latest = candidate
            if let previous = byID[candidate.id] {
                latest.transports = [MobileBatteryTransport.usb, .network].filter {
                    previous.transports.contains($0) || candidate.transports.contains($0)
                }
            }
            byID[candidate.id] = latest
        }
        return byID.values.sorted { $0.id.rowID < $1.id.rowID }
    }

    private static func migratedTrustedMetadata(
        from selections: [LegacyAppleDeviceSelection]
    ) -> [AppleDeviceCandidate] {
        var candidates: [AppleDeviceID: AppleDeviceCandidate] = [:]
        for selection in selections {
            let candidate: AppleDeviceCandidate
            switch selection.id {
            case let .trustedDevice(id):
                guard let model = selection.model,
                      model.lowercased().hasPrefix("iphone") || model.lowercased().hasPrefix("ipad") else { continue }
                candidate = AppleDeviceCandidate(
                    id: .trustedDevice(id), name: selection.name, model: model,
                    transports: [.usb, .network], trustRequired: false, evidence: .verifiedAppleModel
                )
            case let .trustedWatch(parentID, id):
                candidate = AppleDeviceCandidate(
                    id: .trustedWatch(parentID: parentID, id: id), name: selection.name, model: selection.model,
                    transports: [.usb, .network], trustRequired: false,
                    evidence: selection.model?.lowercased().hasPrefix("watch") == true
                        ? .verifiedAppleModel
                        : .trustedWatchCompanion
                )
            case .ble:
                continue
            }
            guard candidate.isVerifiedTrustedAppleDevice else { continue }
            candidates[candidate.id] = candidate
        }
        return candidates.values.sorted { $0.id.rowID < $1.id.rowID }
    }
}
