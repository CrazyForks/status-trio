import Foundation
import Testing
@testable import StatusTrioCore

struct AppleDeviceCatalogTests {
    @Test func nearbyAppleBroadcastsNeverBecomeOwnedAppleDevices() {
        let uuid = UUID()
        let ble = [
            NearbyBLEDeviceCandidate(id: uuid, name: "Phone", vendor: .apple, lastSeen: Date()),
            NearbyBLEDeviceCandidate(id: UUID(), name: "iPhone", vendor: .other, lastSeen: Date())
        ]
        let trusted = [candidate(.trustedDevice("udid"), name: "Phone", model: "iPhone18,1")]
        let result = AppleDeviceCatalog.candidates(trusted: trusted)
        #expect(ble.count == 2)
        #expect(result.map(\.id) == [.trustedDevice("udid")])
    }

    @Test func trustedCandidateProjectsAutomaticallyWithoutASelection() {
        let trusted = candidate(.trustedDevice("p"), name: "Phone", model: "iPhone18,1")
        let projection = AppleDeviceCatalog.projection(
            candidates: [trusted], trustedSnapshots: [],
            failures: [], options: .standard
        )
        #expect(projection.rows.map(\.batteryLevel) == [nil])
        #expect(AppleDevicePanelVisibility.visibleIDs(
            in: [], rowIDs: AppleDeviceCatalog.rowIdentityMap(projection.rows), frames: [:], viewport: .zero
        ).isEmpty)
    }

    @Test func trustRequiredCandidateCannotBecomeAnEligibleAppleRow() {
        let candidate = AppleDeviceCandidate(
            id: .trustedDevice("untrusted"), name: "Phone", model: "iPhone18,1",
            transports: [.usb], trustRequired: true, evidence: .verifiedAppleModel
        )
        #expect(!candidate.isVerifiedTrustedAppleDevice)
        #expect(AppleDeviceCatalog.candidates(trusted: [candidate]).isEmpty)
    }

    @Test func trustedDeviceEligibilityRequiresPhoneOrIPadModelAndUSBOrNetwork() {
        let candidates = [
            AppleDeviceCandidate(
                id: .trustedDevice("mac"), name: "Mac", model: "Mac14,7",
                transports: [.bluetooth], trustRequired: false, evidence: .verifiedAppleModel
            ),
            AppleDeviceCandidate(
                id: .trustedDevice("watch-as-phone"), name: "Watch", model: "Watch7,4",
                transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
            ),
            candidate(.trustedDevice("iphone"), name: "Phone", model: "iPhone18,1"),
            candidate(.trustedDevice("ipad"), name: "Tablet", model: "iPad14,3")
        ]

        #expect(candidates.map(\.isVerifiedTrustedAppleDevice) == [false, false, true, true])
    }

    @Test func watchEligibilityRequiresTrustedTransportAndWatchEvidence() {
        let verifiedWatch = AppleDeviceCandidate(
            id: .trustedWatch(parentID: "p", id: "w1"), name: "Watch", model: "Watch7,4",
            transports: [.network], trustRequired: false, evidence: .verifiedAppleModel
        )
        let companionWatch = AppleDeviceCandidate(
            id: .trustedWatch(parentID: "p", id: "w2"), name: "Watch", model: nil,
            transports: [.usb], trustRequired: false, evidence: .trustedWatchCompanion
        )
        let wrongFamily = AppleDeviceCandidate(
            id: .trustedWatch(parentID: "p", id: "w3"), name: "Phone", model: "iPhone18,1",
            transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
        )
        let bluetoothOnly = AppleDeviceCandidate(
            id: .trustedWatch(parentID: "p", id: "w4"), name: "Watch", model: "Watch7,4",
            transports: [.bluetooth], trustRequired: false, evidence: .trustedWatchCompanion
        )
        #expect([verifiedWatch, companionWatch, wrongFamily, bluetoothOnly].map(\.isVerifiedTrustedAppleDevice) == [true, true, false, false])
    }

    @Test func cachedOfflineRowsRemainVisibleButNeedCurrentVerifiedEvidenceForReadPermit() {
        let cached = candidate(.trustedDevice("phone-1"), name: "Offline phone", model: "iPhone18,1")
        let rowID = cached.id
        let projection = AppleDeviceCatalog.projection(
            candidates: [cached], trustedSnapshots: [], options: .standard
        )
        #expect(projection.rows.count == 1)
        #expect(AppleDeviceCatalog.readAuthorizedIDs(
            visibleIDs: [rowID], currentCandidates: []
        ).isEmpty)
        #expect(AppleDeviceCatalog.readAuthorizedIDs(
            visibleIDs: [rowID], currentCandidates: [cached]
        ) == [rowID])
    }

    @Test func sameTrustedIdentityUsesLatestNameAndCombinesTransportMetadata() {
        let old = AppleDeviceCandidate(
            id: .trustedDevice("p"), name: "Old name", model: "iPhone18,1",
            transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
        )
        let renamed = AppleDeviceCandidate(
            id: .trustedDevice("p"), name: "Renamed phone", model: "iPhone18,1",
            transports: [.network], trustRequired: false, evidence: .verifiedAppleModel
        )
        let result = AppleDeviceCatalog.candidates(trusted: [old, renamed])
        #expect(result.map(\.id) == [.trustedDevice("p")])
        #expect(result.map(\.name) == ["Renamed phone"])
        #expect(result.first.map { Set($0.transports) } == Set([.usb, .network]))
    }

    @Test func trustedReadingIsMatchedOnlyByTypedIdentity() {
        let phone = candidate(.trustedDevice("p"), name: "Same", model: "iPhone18,1")
        let watch = AppleDeviceCandidate(
            id: .trustedWatch(parentID: "p", id: "w"), name: "Same", model: "Watch7,4",
            transports: [.usb], trustRequired: false, evidence: .trustedWatchCompanion
        )
        let candidates = [phone, watch]
        let snapshot = MobileBatterySnapshot(id: "w", parentID: "p", name: "Same", model: "Watch7,4", batteryLevel: 77, isCharging: nil, transport: .usb, observedAt: Date())
        let projection = AppleDeviceCatalog.projection(
            candidates: candidates, trustedSnapshots: [snapshot],
            failures: [], options: .standard
        )
        #expect(projection.rows.first(where: { $0.id == .trustedDevice("p") })?.batteryLevel == nil)
        #expect(projection.rows.first(where: { $0.id == .trustedWatch(parentID: "p", id: "w") })?.batteryLevel == 77)
        let watchRowID = AppleDeviceID.trustedWatch(parentID: "p", id: "w").rowID
        #expect(projection.batteryLevels[BluetoothBatteryReader.normalizedAddress(watchRowID)]?.main == 77)
    }

    @Test func trustedSnapshotRenameUpdatesOneStableOfflineRow() {
        let candidate = candidate(.trustedDevice("p"), name: "Previous name", model: "iPhone18,1")
        let snapshot = MobileBatterySnapshot(
            id: "p", parentID: nil, name: "Current name", model: "iPhone18,1",
            batteryLevel: 48, isCharging: false, transport: .network, observedAt: Date()
        )
        let projection = AppleDeviceCatalog.projection(
            candidates: [candidate, candidate], trustedSnapshots: [snapshot, snapshot],
            options: .standard
        )

        #expect(projection.rows.count == 1)
        #expect(projection.rows[0].device.id == AppleDeviceID.trustedDevice("p").rowID)
        #expect(projection.rows[0].device.name == "Current name")
        #expect(projection.rows[0].batteryLevel == 48)
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
