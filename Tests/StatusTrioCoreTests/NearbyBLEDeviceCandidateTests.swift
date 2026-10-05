import Foundation
import Testing
@testable import StatusTrioCore

@Suite struct NearbyBLEDeviceCandidateTests {
    @Test func appleCandidatesSortBeforeOthersThenByTrimmedNameAndUUID() {
        let candidates = [
            NearbyBLEDeviceCandidate(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Mouse", vendor: .other, lastSeen: .distantPast),
            NearbyBLEDeviceCandidate(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: " beta ", vendor: .apple, lastSeen: .distantPast),
            NearbyBLEDeviceCandidate(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Beta", vendor: .apple, lastSeen: .distantPast),
            NearbyBLEDeviceCandidate(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "AirPods", vendor: .unknown, lastSeen: .distantPast)
        ]

        #expect(NearbyBLEDiscoveryPresentation.ordered(candidates).map(\.id) == [
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        ])
    }

    @Test func bleIdentityUsesAnExplicitNamespaceAndPreservesClassicNormalization() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let row = BluetoothDeviceIdentity.bleRowID(id)

        #expect(row == "ble:00000000-0000-0000-0000-000000000001")
        #expect(BluetoothDeviceIdentity.bleUUID(from: row) == id)
        #expect(BluetoothDeviceIdentity.preferenceKey(row) != BluetoothDeviceIdentity.preferenceKey(id.uuidString))
        #expect(BluetoothDeviceIdentity.preferenceKey("aa:bb:cc:dd:ee:ff") == "AABBCCDDEEFF")
    }

    @Test(arguments: [Data(), Data([0x4C]), Data([0x4C, 0x00]), Data([0x01, 0x00])])
    func vendorClassificationRequiresACompleteAppleCompanyIdentifier(_ payload: Data) {
        let expected: NearbyBLEVendor
        switch payload {
        case Data([0x4C, 0x00]): expected = .apple
        case Data([0x01, 0x00]): expected = .other
        default: expected = .unknown
        }
        #expect(NearbyBLEVendor.fromManufacturerData(payload) == expected)
    }
}
