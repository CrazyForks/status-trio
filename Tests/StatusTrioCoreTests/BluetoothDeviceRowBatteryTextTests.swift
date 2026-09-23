import Testing
@testable import StatusTrioCore

/// The detail row shows a device's level when the report carries one, and
/// renders nothing when it does not. Rows for devices whose level macOS cannot
/// read stay quiet instead of repeating a placeholder on every line; a report
/// that could not be read at all is reported once for the whole list.
///
/// The level reaches the row as pieces rather than as a finished string, so the
/// charging case is drawn as a glyph while every text-only surface — the
/// accessibility value and the popover's summary — still reads the word. Both
/// forms are pinned here, since the glyph must not take the meaning with it.
struct BluetoothDeviceRowBatteryTextTests {
    private func device(_ address: String, name: String = "AirPods Pro") -> BluetoothDevice {
        BluetoothDevice(id: address, name: name, kind: .audio, isConnected: true)
    }

    /// The row's text-only form, which is what the assertions below compare
    /// against: the pieces the row draws, spelled out.
    private func rowText(
        for address: String,
        levels: [String: BluetoothBatteryLevel]
    ) -> String? {
        BluetoothDevicePresentation.batteryLevelSegments(
            for: device(address),
            batteryLevels: levels
        )?.plainText
    }

    @Test("A reported level becomes the row text")
    func reportedLevelBecomesRowText() {
        let address = "AC:90:85:C2:9C:1F"

        let text = rowText(
            for: address,
            levels: [
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

        let text = rowText(
            for: address,
            levels: [
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

    /// The charging case is the one channel the row cannot spell out: "Case" is
    /// hard-coded English that none of the app's localizations carry, and the row
    /// has no room for a word there. It is drawn as a glyph, and the percentage
    /// beside it stays text because the word was the part with no room.
    @Test("The charging case is a glyph in the row and a word in its text form")
    func theChargingCaseIsAGlyphInTheRow() throws {
        let address = "AC:90:85:C2:9C:1F"

        let segments = try #require(
            BluetoothDevicePresentation.batteryLevelSegments(
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
        )

        // The symbol name is pinned as a literal on purpose: it is what the row
        // draws, and a rename that this test did not catch would either draw
        // nothing or draw another device's glyph.
        #expect(segments == [
            .text("L 85%"),
            .text(" · "),
            .text("R 80%"),
            .text(" · "),
            .symbol(name: "airpods.chargingcase", label: "Case"),
            .text(" 70%")
        ])
        #expect(segments.plainText == "L 85% · R 80% · Case 70%")
    }

    /// A level carrying no case channel is all text, so the row draws no glyph.
    @Test("A level without a case channel carries no symbol")
    func aLevelWithoutACaseCarriesNoSymbol() throws {
        let address = "AC:90:85:C2:9C:1F"

        let segments = try #require(
            BluetoothDevicePresentation.batteryLevelSegments(
                for: device(address),
                batteryLevels: [
                    BluetoothBatteryReader.normalizedAddress(address): BluetoothBatteryLevel(
                        deviceAddress: address,
                        main: nil,
                        left: 85,
                        right: 80,
                        caseLevel: nil
                    )
                ]
            )
        )

        #expect(segments == [.text("L 85%"), .text(" · "), .text("R 80%")])
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
            rowText(
                for: "0C:AE:BD:FE:D7:C3",
                levels: [BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): level]
            ) == nil
        )
    }

    @Test("The first read, still unfinished, renders no placeholder")
    func unfinishedReadRendersNothing() {
        #expect(rowText(for: "AA:BB:CC:DD:EE:FF", levels: [:]) == nil)
    }

    /// The reader keys levels by normalized address, so the row lookup has to
    /// normalize the device identifier the same way.
    @Test("The lookup normalizes the address the way the reader keys it")
    func lookupNormalizesTheAddress() {
        let text = rowText(
            for: "ac:90:85:c2:9c:1f",
            levels: [
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
