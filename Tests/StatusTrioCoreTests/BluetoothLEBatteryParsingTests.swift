import Foundation
import Testing
@testable import StatusTrioCore

struct BluetoothLEBatteryParsingTests {
    @Test func parsesOnlySingleByteBatteryLevelsFromZeroThroughOneHundred() {
        #expect(BluetoothLEBatteryParsing.percentage(Data()) == nil)
        #expect(BluetoothLEBatteryParsing.percentage(Data([0])) == 0)
        #expect(BluetoothLEBatteryParsing.percentage(Data([1])) == 1)
        #expect(BluetoothLEBatteryParsing.percentage(Data([50])) == 50)
        #expect(BluetoothLEBatteryParsing.percentage(Data([100])) == 100)
        #expect(BluetoothLEBatteryParsing.percentage(Data([101])) == nil)
        #expect(BluetoothLEBatteryParsing.percentage(Data([255])) == nil)
        #expect(BluetoothLEBatteryParsing.percentage(Data([50, 0])) == nil)
    }

    @Test func parsesTrimmedUTF8DeviceInformationAndRejectsEmptyOrInvalidValues() {
        #expect(BluetoothLEBatteryParsing.deviceInfo(Data("  Model X  ".utf8)) == "Model X")
        #expect(BluetoothLEBatteryParsing.deviceInfo(Data([0x4B, 0x65, 0x79, 0x00])) == "Key")
        #expect(BluetoothLEBatteryParsing.deviceInfo(Data(" \n\t ".utf8)) == nil)
        #expect(BluetoothLEBatteryParsing.deviceInfo(Data([0xC3, 0x28])) == nil)
    }

    @Test func nearbyDeviceUsesProvidedLocalizedFallbackForAnEmptyName() {
        let now = Date(timeIntervalSince1970: 1_000)
        let device = NearbyBluetoothBatteryDevice(
            id: UUID(),
            name: " \n ",
            batteryLevel: 0,
            model: nil,
            manufacturer: nil,
            lastUpdated: now
        )

        #expect(device.displayName(fallback: "Nearby Device") == "Nearby Device")
        #expect(device.batteryLevel == 0)
        #expect(device.lastUpdated == now)
    }
}
