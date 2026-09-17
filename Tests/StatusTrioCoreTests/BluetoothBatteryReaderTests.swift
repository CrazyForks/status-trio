import Foundation
import Testing
@testable import StatusTrioCore

struct BluetoothBatteryReaderTests {
    @Test func parsesComponentAndAggregateBatteryLevels() throws {
        let json = try #require(
            """
            {
              "SPBluetoothDataType": [
                {
                  "device_connected": [
                    {
                      "AirPods Pro": {
                        "device_address": "AC:90:85:C2:9C:1F",
                        "device_batteryLevelMain": "95%",
                        "device_batteryLevelLeft": "85",
                        "device_batteryLevelRight": 80,
                        "device_batteryLevelCase": "70 %"
                      }
                    }
                  ],
                  "device_not_connected": [
                    {
                      "Keyboard": {
                        "device_address": "D3-6D-6C-40-A3-2E",
                        "device_batteryLevel": "63%"
                      }
                    }
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        let levels = BluetoothBatteryReader.parse(json: json)
        let airPods = try #require(levels[BluetoothBatteryReader.normalizedAddress("ac9085c29c1f")])
        let keyboard = try #require(levels[BluetoothBatteryReader.normalizedAddress("D3:6D:6C:40:A3:2E")])

        #expect(airPods.main == 95)
        #expect(airPods.left == 85)
        #expect(airPods.right == 80)
        #expect(airPods.caseLevel == 70)
        #expect(airPods.summary == "95% · L 85% · R 80% · Case 70%")
        #expect(keyboard.main == 63)
        #expect(keyboard.summary == "63%")
    }

    @Test func ignoresInvalidAndOutOfRangeLevels() throws {
        let json = try #require(
            """
            {
              "SPBluetoothDataType": [
                {
                  "device_connected": [
                    {
                      "Headphones": {
                        "device_address": "00:11:22:33:44:55",
                        "device_batteryLevelMain": "not available",
                        "device_batteryLevelLeft": 101,
                        "device_batteryLevelRight": -1,
                        "device_batteryLevelCase": "12.5"
                      }
                    }
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        #expect(BluetoothBatteryReader.parse(json: json).isEmpty)
    }

    @Test func malformedOutputFailsClosed() {
        #expect(BluetoothBatteryReader.parse(json: Data("not json".utf8)).isEmpty)
    }
}
