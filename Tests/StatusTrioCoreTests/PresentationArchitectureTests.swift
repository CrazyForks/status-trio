import Testing
@testable import StatusTrioCore

struct PresentationArchitectureTests {
    @Test func sceneDoesNotDependOnSSID() {
        let base = PresentationFixtures.snapshot()
        let renamed = StatusSnapshot(
            battery: base.battery,
            wifi: WiFiStatus(state: base.wifi.state, rssi: base.wifi.rssi, ssid: "Renamed"),
            connection: base.connection,
            volume: base.volume
        )

        let baseScene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: base, audioIcon: nil),
            configuration: .standard
        )
        let renamedScene = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: renamed, audioIcon: nil),
            configuration: .standard
        )

        #expect(baseScene == renamedScene)
    }
}
