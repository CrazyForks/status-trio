import CoreGraphics
import Foundation

enum NearbyBLEPanelVisibility {
    static func shouldClearVisibleIDs(enabled: Bool, batteryLevelsEnabled: Bool, showsList: Bool) -> Bool {
        !enabled || !batteryLevelsEnabled || !showsList
    }

    static func visibleSelectedIDs(
        in visibleDevices: [BluetoothDevice],
        frames: [UUID: CGRect],
        viewport: CGRect
    ) -> Set<UUID> {
        var selectedIDs = Set<UUID>()
        for device in visibleDevices where device.isReadOverTheAir {
            if let id = BluetoothDeviceIdentity.bleUUID(from: device.id) {
                selectedIDs.insert(id)
            }
        }
        return selectedIDs.intersection(intersectingIDs(frames: frames, viewport: viewport))
    }

    static func intersectingIDs(frames: [UUID: CGRect], viewport: CGRect) -> Set<UUID> {
        guard viewport.width > 0, viewport.height > 0 else { return [] }
        return Set(frames.compactMap { id, frame in
            guard frame.width > 0, frame.height > 0 else { return nil }
            return frame.intersects(viewport) ? id : nil
        })
    }
}
