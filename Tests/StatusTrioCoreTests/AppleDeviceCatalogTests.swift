import Foundation
import Testing
@testable import StatusTrioCore

struct AppleDeviceCatalogTests {
    @Test func onlyAppleEvidenceEntersAndNamesNeverMergeIdentities() {
        let uuid = UUID()
        let ble = [
            NearbyBLEDeviceCandidate(id: uuid, name: "Phone", vendor: .apple, lastSeen: Date()),
            NearbyBLEDeviceCandidate(id: UUID(), name: "iPhone", vendor: .other, lastSeen: Date())
        ]
        let trusted = [candidate(.trustedDevice("udid"), name: "Phone", model: "iPhone18,1")]
        let result = AppleDeviceCatalog.candidates(ble: ble, trusted: trusted, selections: [])
        #expect(result.map(\.id).count == 2)
        let actualIDs = Set(result.map { $0.id })
        let expectedIDs: Set<AppleDeviceID> = [.ble(uuid), .trustedDevice("udid")]
        #expect(actualIDs == expectedIDs)
    }

    @Test func savedSelectionWithoutReadingStillProjectsRowAndBatteryOffHasNoReadPermit() {
        let selection = AppleDeviceSelection(id: .trustedDevice("p"), name: "Phone", model: "iPhone18,1")
        let candidate = candidate(selection.id, name: "Phone", model: "iPhone18,1")
        let projection = AppleDeviceCatalog.projection(
            selections: [selection], candidates: [candidate], nearbyReadings: [], trustedSnapshots: [],
            failures: [], options: .standard, now: Date()
        )
        #expect(projection.rows.count == 1)
        #expect(projection.rows[0].batteryLevel == nil)
        #expect(AppleDevicePanelVisibility.visibleIDs(
            in: [], rowIDs: AppleDeviceCatalog.rowIdentityMap(projection.rows), frames: [:], viewport: .zero
        ).isEmpty)
    }

    @Test func trustedReadingIsMatchedOnlyByTypedIdentity() {
        let phone = AppleDeviceSelection(id: .trustedDevice("p"), name: "Same", model: "iPhone18,1")
        let watch = AppleDeviceSelection(id: .trustedWatch(parentID: "p", id: "w"), name: "Same", model: "Watch7,4")
        let candidates = [candidate(phone.id, name: "Same", model: phone.model), candidate(watch.id, name: "Same", model: watch.model)]
        let snapshot = MobileBatterySnapshot(id: "w", parentID: "p", name: "Same", model: "Watch7,4", batteryLevel: 77, isCharging: nil, transport: .usb, observedAt: Date())
        let projection = AppleDeviceCatalog.projection(
            selections: [phone, watch], candidates: candidates, nearbyReadings: [], trustedSnapshots: [snapshot],
            failures: [], options: .standard, now: Date()
        )
        #expect(projection.rows.map(\.batteryLevel) == [nil, 77])
        let watchRowID = AppleDeviceID.trustedWatch(parentID: "p", id: "w").rowID
        #expect(projection.batteryLevels[watchRowID]?.main == 77)
    }

    @Test func iPadBatteryWireModelIsAcceptedAndMappedToTabletGlyph() throws {
        let json = Data(#"{"schemaVersion":1,"devices":[{"id":"tablet","parentID":null,"name":"Tablet","model":"iPad14,3","batteryLevel":54,"transport":"usb"}],"failures":[],"watchCandidates":[]}"#.utf8)
        let result = try MobileBatteryWire.decode(json, expectedParentID: "tablet", observedAt: Date())
        #expect(result.snapshots.count == 1)
        #expect(BluetoothMobileDeviceModel.kind(forModel: result.snapshots.first?.model) == .mobile(.tablet))
    }

    private func candidate(_ id: AppleDeviceID, name: String, model: String?) -> AppleDeviceCandidate {
        AppleDeviceCandidate(id: id, name: name, model: model, transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel)
    }
}
