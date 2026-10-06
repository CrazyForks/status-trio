import Foundation
import CoreGraphics
import Testing
@testable import StatusTrioCore

struct AppleDevicePanelVisibilityTests {
    @Test func emptyViewportAndOffscreenRowsGrantNoTargets() {
        let id = AppleDeviceID.trustedDevice("p")
        let device = BluetoothDevice(id: id.rowID, name: "Phone", kind: .mobile(.phone), isConnected: false, isReadOverTheAir: true)
        let map = [device.id: id]
        #expect(AppleDevicePanelVisibility.visibleIDs(in: [device], rowIDs: map, frames: [device.id: CGRect(x: 0, y: 100, width: 20, height: 20)], viewport: .zero).isEmpty)
        #expect(AppleDevicePanelVisibility.visibleIDs(in: [device], rowIDs: map, frames: [device.id: CGRect(x: 0, y: 100, width: 20, height: 20)], viewport: CGRect(x: 0, y: 0, width: 50, height: 50)).isEmpty)
    }

    @Test func onlyActuallyVisibleMappedRowsReceiveTargets() {
        let first = AppleDeviceID.ble(UUID())
        let second = AppleDeviceID.trustedDevice("p")
        let devices = [first, second].map { BluetoothDevice(id: $0.rowID, name: "Device", kind: .unknown, isConnected: false, isReadOverTheAir: true) }
        let rows = Dictionary(uniqueKeysWithValues: zip(devices.map(\.id), [first, second]))
        let frames = [devices[0].id: CGRect(x: 0, y: 0, width: 20, height: 20), devices[1].id: CGRect(x: 0, y: 60, width: 20, height: 20)]
        let visible = AppleDevicePanelVisibility.visibleIDs(in: devices, rowIDs: rows, frames: frames, viewport: CGRect(x: 0, y: 0, width: 50, height: 40))
        #expect(visible == [first])
    }
}
