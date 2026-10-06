import CoreGraphics
import Foundation

enum AppleDevicePanelVisibility {
    static func visibleIDs(
        in devices: [BluetoothDevice],
        rowIDs: [String: AppleDeviceID],
        frames: [String: CGRect],
        viewport: CGRect
    ) -> Set<AppleDeviceID> {
        guard viewport.width > 0, viewport.height > 0 else { return [] }
        return Set(devices.compactMap { device in
            guard let id = rowIDs[device.id],
                  let frame = frames[device.id],
                  frame.width > 0, frame.height > 0,
                  frame.intersects(viewport) else { return nil }
            return id
        })
    }
}
