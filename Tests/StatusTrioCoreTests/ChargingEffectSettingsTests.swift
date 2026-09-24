import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct ChargingEffectSettingsTests {
    @Test func chargingEffectDefaultsOnAndPersistsThroughIconOptions() throws {
        let domain = "ChargingEffectSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        #expect(defaults.object(forKey: SettingsStore.showsChargingEffectDefaultsKey) == nil)
        let first = SettingsStore(defaults: defaults)
        #expect(first.showsChargingEffect)
        #expect(first.batteryIconOptions.showsChargingEffect)

        first.showsChargingEffect = false
        #expect(defaults.object(forKey: SettingsStore.showsChargingEffectDefaultsKey) as? Bool == false)
        let restored = SettingsStore(defaults: defaults)
        #expect(restored.showsChargingEffect == false)
        #expect(restored.batteryIconOptions.showsChargingEffect == false)

        restored.showsChargingEffect = true
        #expect(SettingsStore(defaults: defaults).batteryIconOptions.showsChargingEffect)
    }
}
