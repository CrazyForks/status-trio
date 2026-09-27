import Foundation
import Testing
@testable import StatusTrioCore

struct BluetoothNearbyBatteryPresentationTests {
    @Test func visibleDevicesKeepValidZeroAndDuplicateNamesSeparate() {
        let sharedName = "Temperature Sensor"
        let zero = nearbyDevice(name: sharedName, level: 0)
        let full = nearbyDevice(name: sharedName, level: 100)
        let invalidHigh = nearbyDevice(name: "Invalid high", level: 101)
        let invalidLow = nearbyDevice(name: "Invalid low", level: -1)

        let visible = BluetoothNearbyBatteryListPresentation.visibleDevices(
            from: [zero, full, invalidHigh, invalidLow],
            enabled: true
        )

        #expect(visible.map(\.id) == [zero.id, full.id])
        #expect(visible.map(\.batteryLevel) == [0, 100])
        #expect(visible.map(\.name) == [sharedName, sharedName])
    }

    @Test func disabledNearbyPresentationShowsNoRows() {
        let visible = BluetoothNearbyBatteryListPresentation.visibleDevices(
            from: [nearbyDevice(name: "Sensor", level: 44)],
            enabled: false
        )

        #expect(visible.isEmpty)
    }

    private func nearbyDevice(name: String, level: Int) -> NearbyBluetoothBatteryDevice {
        NearbyBluetoothBatteryDevice(
            id: UUID(),
            name: name,
            batteryLevel: level,
            model: nil,
            manufacturer: nil,
            lastUpdated: Date()
        )
    }
}
