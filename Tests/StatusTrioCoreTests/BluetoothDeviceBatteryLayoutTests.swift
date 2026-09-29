import Testing
@testable import StatusTrioCore

/// Which layout a device row uses is a pure function of the level the report
/// carries, never of the device's brand or model. These cases pin the rule the
/// row and the list's height model both consume: a component channel — left,
/// right, or charging case — takes the level onto its own line, and everything
/// else stays inline.
///
/// The tests are logic-only on purpose. They assert the policy directly rather
/// than rendering it, so a change to the rule fails here with a clear reason;
/// `BluetoothDeviceRowLayoutTests` is where the rendered geometry is pinned.
struct BluetoothDeviceBatteryLayoutTests {
    private func device(_ address: String, name: String = "Ling's AirPods Pro") -> BluetoothDevice {
        // `.unknown` on purpose: the layout must not depend on the device being
        // recognised as AirPods, so nothing here is audio-classified or named to
        // help the row along.
        BluetoothDevice(id: address, name: name, kind: .unknown, isConnected: true)
    }

    private func layout(
        main: Int?,
        left: Int?,
        right: Int?,
        caseLevel: Int?
    ) -> BluetoothBatteryLayout {
        let address = "AC:90:85:C2:9C:1F"
        return BluetoothDevicePresentation.batteryLayout(
            for: device(address),
            batteryLevels: [
                BluetoothBatteryReader.normalizedAddress(address): BluetoothBatteryLevel(
                    deviceAddress: address,
                    main: main,
                    left: left,
                    right: right,
                    caseLevel: caseLevel
                )
            ]
        )
    }

    @Test("A device with no level at all stays inline")
    func noLevelStaysInline() {
        #expect(layout(main: nil, left: nil, right: nil, caseLevel: nil) == .inline)
    }

    @Test("An ordinary whole-device level stays inline")
    func mainOnlyStaysInline() {
        #expect(layout(main: 84, left: nil, right: nil, caseLevel: nil) == .inline)
    }

    @Test("A left channel takes the component layout")
    func leftIsComponent() {
        #expect(layout(main: nil, left: 85, right: nil, caseLevel: nil) == .components)
    }

    @Test("A right channel takes the component layout")
    func rightIsComponent() {
        #expect(layout(main: nil, left: nil, right: 80, caseLevel: nil) == .components)
    }

    @Test("A charging-case channel takes the component layout")
    func caseIsComponent() {
        #expect(layout(main: nil, left: nil, right: nil, caseLevel: 70) == .components)
    }

    @Test("Left and right together take the component layout")
    func leftAndRightAreComponent() {
        #expect(layout(main: nil, left: 85, right: 80, caseLevel: nil) == .components)
    }

    @Test("Left, right and case together take the component layout")
    func fullEarbudSetIsComponent() {
        #expect(layout(main: nil, left: 85, right: 80, caseLevel: 70) == .components)
    }

    /// A report that carries both the aggregate and a component is still a
    /// component device: the component gets the whole second line. This is the
    /// case a `channelCount >= 2` shortcut would get wrong.
    @Test("A whole-device level alongside a component is still the component layout")
    func mainPlusComponentIsComponent() {
        #expect(layout(main: 85, left: nil, right: nil, caseLevel: 70) == .components)
    }

    /// The layout reaches the row through the same normalized lookup the drawn
    /// segments use, so an identifier written with separators and lowercase still
    /// matches the level the reader keyed by its bare uppercase form.
    @Test("The layout lookup normalizes the address the way the reader keys it")
    func layoutNormalizesTheAddress() {
        let level = BluetoothBatteryLevel(
            deviceAddress: "AC:90:85:C2:9C:1F",
            main: nil,
            left: 85,
            right: 80,
            caseLevel: 70
        )

        let layout = BluetoothDevicePresentation.batteryLayout(
            for: device("ac:90:85:c2:9c:1f"),
            batteryLevels: ["AC9085C29C1F": level]
        )

        #expect(layout == .components)
    }

    @Test("A device the report has no level for falls back to inline")
    func unknownDeviceFallsBackToInline() {
        #expect(
            BluetoothDevicePresentation.batteryLayout(
                for: device("0C:AE:BD:FE:D7:C3"),
                batteryLevels: [:]
            ) == .inline
        )
    }
}
