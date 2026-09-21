import Testing
@testable import StatusTrioCore

/// The detail page shows a device's level when the report carries one, and
/// renders nothing when it does not. Rows for devices whose level macOS cannot
/// read stay quiet instead of repeating a placeholder on every line; a report
/// that could not be read at all is reported once for the whole list.
struct BluetoothDeviceRowBatteryTextTests {
    private func device(_ address: String, name: String = "AirPods Pro") -> BluetoothDevice {
        BluetoothDevice(id: address, name: name, kind: .audio, isConnected: true)
    }

    @Test("A reported level becomes the row text")
    func reportedLevelBecomesRowText() {
        let address = "AC:90:85:C2:9C:1F"

        let text = BluetoothDevicePresentation.batteryLevelText(
            for: device(address),
            batteryLevels: [
                BluetoothBatteryReader.normalizedAddress(address): BluetoothBatteryLevel(
                    deviceAddress: address,
                    main: 64,
                    left: nil,
                    right: nil,
                    caseLevel: nil
                )
            ]
        )

        #expect(text == "64%")
    }

    @Test("The row keeps every channel the report carries")
    func rowKeepsEveryChannel() {
        let address = "AC:90:85:C2:9C:1F"

        let text = BluetoothDevicePresentation.batteryLevelText(
            for: device(address),
            batteryLevels: [
                BluetoothBatteryReader.normalizedAddress(address): BluetoothBatteryLevel(
                    deviceAddress: address,
                    main: nil,
                    left: 85,
                    right: 80,
                    caseLevel: 70
                )
            ]
        )

        #expect(text == "L 85% · R 80% · Case 70%")
    }

    @Test("A device the report has no level for renders no text")
    func deviceWithoutALevelRendersNothing() {
        let level = BluetoothBatteryLevel(
            deviceAddress: "AC:90:85:C2:9C:1F",
            main: 64,
            left: nil,
            right: nil,
            caseLevel: nil
        )

        #expect(
            BluetoothDevicePresentation.batteryLevelText(
                for: device("0C:AE:BD:FE:D7:C3", name: "EDIFIER LolliPods 2022版"),
                batteryLevels: [BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): level]
            ) == nil
        )
    }

    @Test("The first read, still unfinished, renders no placeholder")
    func unfinishedReadRendersNothing() {
        #expect(
            BluetoothDevicePresentation.batteryLevelText(
                for: device("AA:BB:CC:DD:EE:FF"),
                batteryLevels: [:]
            ) == nil
        )
    }

    /// The reader keys levels by normalized address, so the row lookup has to
    /// normalize the device identifier the same way.
    @Test("The lookup normalizes the address the way the reader keys it")
    func lookupNormalizesTheAddress() {
        let text = BluetoothDevicePresentation.batteryLevelText(
            for: device("ac:90:85:c2:9c:1f"),
            batteryLevels: [
                "AC9085C29C1F": BluetoothBatteryLevel(
                    deviceAddress: "AC:90:85:C2:9C:1F",
                    main: nil,
                    left: 85,
                    right: 80,
                    caseLevel: 70
                )
            ]
        )

        #expect(text == "L 85% · R 80% · Case 70%")
    }
}
