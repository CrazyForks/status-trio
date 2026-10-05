import Foundation
import Testing
@testable import StatusTrioCore

struct BluetoothMobileDeviceModelTests {
    @Test func readsTheFamilyOutOfTheModelNumber() {
        #expect(BluetoothMobileDeviceModel.kind(forModel: "iPhone14,3") == .mobile(.phone))
        #expect(BluetoothMobileDeviceModel.kind(forModel: "iPhone17,1") == .mobile(.phone))
        #expect(BluetoothMobileDeviceModel.kind(forModel: "iPad11,1") == .mobile(.tablet))
        #expect(BluetoothMobileDeviceModel.kind(forModel: "Watch6,1") == .mobile(.watch))
    }

    /// The number after the family is the hardware revision, which changes every
    /// release and has no glyph of its own, so only the family prefix is read.
    @Test func ignoresTheHardwareRevisionAndSurroundingWhitespace() {
        #expect(BluetoothMobileDeviceModel.kind(forModel: "  iPad8,9 ") == .mobile(.tablet))
        #expect(BluetoothMobileDeviceModel.kind(forModel: "watch4,4") == .mobile(.watch))
    }

    @Test func readsANameThatOnlyContainsTheFamilyAsNoModel() {
        #expect(BluetoothMobileDeviceModel.kind(forModel: "My iPhone") == nil)
        #expect(BluetoothMobileDeviceModel.kind(forModel: "iPhone") == .mobile(.phone))
    }

    /// An iPod is a media player rather than a phone, and the app's mobile forms
    /// are only phone, tablet and watch, so it keeps whatever class it had.
    @Test func doesNotClassifyAFamilyTheAppHasNoFormFor() {
        #expect(BluetoothMobileDeviceModel.kind(forModel: "iPod9,1") == nil)
        #expect(BluetoothMobileDeviceModel.kind(forModel: "MacBookPro18,3") == nil)
        #expect(BluetoothMobileDeviceModel.kind(forModel: "") == nil)
        #expect(BluetoothMobileDeviceModel.kind(forModel: "   ") == nil)
        #expect(BluetoothMobileDeviceModel.kind(forModel: nil) == nil)
    }
}

struct BluetoothNearbyDeviceMergeTests {
    private func nearbyDevice(
        name: String,
        level: Int,
        model: String? = "iPhone14,3"
    ) -> NearbyBluetoothBatteryDevice {
        NearbyBluetoothBatteryDevice(
            id: UUID(),
            name: name,
            batteryLevel: level,
            model: model,
            manufacturer: "Apple Inc.",
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func pairedDevice(
        id: String = "AC-CF-5C-ED-1D-CE",
        name: String,
        kind: BluetoothDeviceKind = .unknown,
        isUnpairedGhost: Bool = false
    ) -> BluetoothDevice {
        BluetoothDevice(
            id: id,
            name: name,
            kind: kind,
            isConnected: true,
            isUnpairedGhost: isUnpairedGhost
        )
    }

    @Test func foldsALevelOntoTheRowTheSameDeviceAlreadyHas() {
        let device = pairedDevice(name: "Ling's iPhone")
        let result = BluetoothNearbyDeviceMerge.merged(
            devices: [device],
            batteryLevels: [:],
            nearbyDevices: [nearbyDevice(name: "Ling's iPhone", level: 31)]
        )

        #expect(result.devices.count == 1)
        #expect(result.devices[0].kind == .mobile(.phone))
        let key = BluetoothBatteryReader.normalizedAddress(device.id)
        #expect(result.batteryLevels[key]?.main == 31)
        #expect(result.remainingNearby.isEmpty)
    }

    /// An iPhone the profiler could not classify is a ghost, and the panel hides
    /// ghosts by default. The model string has just classified it, so the flag
    /// has to go with the class or the row carrying the level stays hidden.
    @Test func clearsTheGhostFlagOnceTheModelIdentifiesTheRow() {
        let device = pairedDevice(name: "Ling's iPhone", isUnpairedGhost: true)
        let result = BluetoothNearbyDeviceMerge.merged(
            devices: [device],
            batteryLevels: [:],
            nearbyDevices: [nearbyDevice(name: "Ling's iPhone", level: 31)]
        )

        #expect(result.devices.count == 1)
        #expect(result.devices[0].kind == .mobile(.phone))
        #expect(!result.devices[0].isUnpairedGhost)
    }

    /// The row the reading created is the reading's, including its connection
    /// state. The report calls this phone connected only because the read
    /// connected to it — the state appears within a fifth of a second of the
    /// read and goes when the panel closes and the read ends — so drawing it
    /// would make the row turn blue a few seconds after the panel opens.
    @Test func takesTheConnectionStateAwayFromARowTheReadingIdentified() {
        let device = pairedDevice(name: "Ling's iPhone", isUnpairedGhost: true)
        #expect(device.isConnected, "the report carried it as connected")

        let result = BluetoothNearbyDeviceMerge.merged(
            devices: [device],
            batteryLevels: [:],
            nearbyDevices: [nearbyDevice(name: "Ling's iPhone", level: 31)]
        )

        #expect(!result.devices[0].isConnected)
        #expect(result.devices[0].isReadOverTheAir)
    }

    /// A row the report classified itself is a paired device the user has, and
    /// the reading only adds a level to it: its connection state stays the
    /// report's, and it keeps its connect and disconnect action.
    @Test func leavesARowTheReportClassifiedAlone() {
        let device = pairedDevice(name: "MX Keys", kind: .peripheral(.keyboard))
        let result = BluetoothNearbyDeviceMerge.merged(
            devices: [device],
            batteryLevels: [:],
            nearbyDevices: [nearbyDevice(name: "MX Keys", level: 50, model: "iPad11,1")]
        )

        #expect(result.devices[0].isConnected)
        #expect(!result.devices[0].isReadOverTheAir)
    }

    /// A row the report does not carry at all is the reading's from the start.
    @Test func marksARowItHadToAddAsTheReadingsOwn() {
        let result = BluetoothNearbyDeviceMerge.merged(
            devices: [],
            batteryLevels: [:],
            nearbyDevices: [nearbyDevice(name: "Lingsipad", level: 23, model: "iPad11,1")]
        )

        #expect(result.devices[0].isReadOverTheAir)
        #expect(!result.devices[0].isConnected)
    }

    @Test func preservesAppleWatchModelForAnAddedRowAndUsesItsSpecificGlyph() {
        let result = BluetoothNearbyDeviceMerge.merged(
            devices: [],
            batteryLevels: [:],
            nearbyDevices: [nearbyDevice(name: "Office Watch", level: 45, model: "Watch7,1")]
        )

        #expect(result.devices.count == 1)
        #expect(result.devices[0].name == "Office Watch")
        #expect(BluetoothDeviceRowIcon.symbolName(for: result.devices[0]) == "applewatch")
        #expect(result.devices[0].appleMobileModel == "Watch7,1")
    }

    @Test func existingRowKeepsWatchModelEvidenceWhenRefined() {
        let paired = pairedDevice(name: "Office Watch")
        let result = BluetoothNearbyDeviceMerge.merged(
            devices: [paired],
            batteryLevels: [:],
            nearbyDevices: [nearbyDevice(name: "Office Watch", level: 45, model: "Watch7,1")]
        )

        #expect(result.devices[0].appleMobileModel == "Watch7,1")
        #expect(BluetoothDeviceRowIcon.symbolName(for: result.devices[0]) == "applewatch")
    }

    @Test func knownPairedWatchKeepsItsConnectionAndOwnershipWhenItsModelArrives() {
        let paired = pairedDevice(name: "Office Watch", kind: .mobile(.watch))
        let result = BluetoothNearbyDeviceMerge.merged(
            devices: [paired],
            batteryLevels: [:],
            nearbyDevices: [nearbyDevice(name: "Office Watch", level: 45, model: "Watch7,1")]
        )

        #expect(result.devices[0].isConnected)
        #expect(!result.devices[0].isReadOverTheAir)
        #expect(BluetoothDeviceRowIcon.symbolName(for: result.devices[0]) == "applewatch")
    }

    @Test func appleWatchModelEvidenceWinsOverARenamedName() {
        let renamed = BluetoothDevice(
            id: "watch",
            name: "Kitchen timer",
            kind: .mobile(.watch),
            isConnected: false,
            appleMobileModel: "Watch7,1"
        )
        #expect(BluetoothDeviceRowIcon.symbolName(for: renamed) == "applewatch")
    }

    @Test func genericWatchWithoutAppleModelKeepsGenericGlyph() {
        let generic = BluetoothDevice(id: "watch", name: "Watch", kind: .mobile(.watch), isConnected: false)
        #expect(BluetoothDeviceRowIcon.symbolName(for: generic) == "watch.analog")
    }

    /// The name is the only identity the two sources share, so the comparison
    /// drops case and surrounding whitespace and stops there.
    @Test func matchesTheNameIgnoringCaseAndSurroundingWhitespace() {
        let result = BluetoothNearbyDeviceMerge.merged(
            devices: [pairedDevice(name: "  ling's IPHONE ")],
            batteryLevels: [:],
            nearbyDevices: [nearbyDevice(name: "Ling's iPhone", level: 44)]
        )

        #expect(result.devices.count == 1)
        #expect(result.batteryLevels.values.first?.main == 44)
    }

    @Test func addsARowForAMobileDeviceTheReportDoesNotCarryAtAll() {
        let result = BluetoothNearbyDeviceMerge.merged(
            devices: [],
            batteryLevels: [:],
            nearbyDevices: [nearbyDevice(name: "Lingsipad", level: 23, model: "iPad11,1")]
        )

        #expect(result.devices.count == 1)
        #expect(result.devices[0].name == "Lingsipad")
        #expect(result.devices[0].kind == .mobile(.tablet))
        #expect(result.batteryLevels.values.first?.main == 23)
    }

    /// The paired-device report is the primary source and it also carries the
    /// per-channel parts a scan reading cannot describe, so it is never
    /// overwritten and a class it declared is never replaced.
    @Test func neverOverwritesTheReportsOwnLevelOrDeclaredClass() {
        let device = pairedDevice(name: "Ling's iPhone", kind: .audio)
        let key = BluetoothBatteryReader.normalizedAddress(device.id)
        let reported = BluetoothBatteryLevel(
            deviceAddress: device.id,
            main: 88,
            left: 80,
            right: 81,
            caseLevel: nil
        )

        let result = BluetoothNearbyDeviceMerge.merged(
            devices: [device],
            batteryLevels: [key: reported],
            nearbyDevices: [nearbyDevice(name: "Ling's iPhone", level: 31)]
        )

        #expect(result.batteryLevels[key] == reported)
        #expect(result.devices[0].kind == .audio)
    }

    /// A BLE thermometer is not an iOS device, so it keeps the section it
    /// arrived in rather than being folded into the paired-device list.
    @Test func leavesAScanResultTheModelDoesNotIdentifyInTheNearbySection() {
        let sensor = nearbyDevice(name: "Temperature Sensor", level: 52, model: "TH-02")
        let nameless = nearbyDevice(name: "  ", level: 60)

        let result = BluetoothNearbyDeviceMerge.merged(
            devices: [],
            batteryLevels: [:],
            nearbyDevices: [sensor, nameless]
        )

        #expect(result.devices.isEmpty)
        #expect(result.batteryLevels.isEmpty)
        #expect(result.remainingNearby.map(\.id) == [sensor.id, nameless.id])
    }
}
