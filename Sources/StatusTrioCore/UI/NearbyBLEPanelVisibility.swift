import CoreGraphics
import Foundation

enum NearbyBLEPanelVisibility {
    static func shouldClearVisibleIDs(enabled: Bool, batteryLevelsEnabled: Bool, showsList: Bool) -> Bool {
        !enabled || !batteryLevelsEnabled || !showsList
    }

    static func eligibleIDs(
        rows: [NearbyBLEPanelRow],
        showsList: Bool,
        limit: Int,
        expanded: Bool
    ) -> Set<UUID> {
        guard showsList, limit > 0 else { return [] }
        let eligibleRows = expanded ? rows : Array(rows.prefix(limit))
        return Set(eligibleRows.map(\.id))
    }

    static func intersectingIDs(frames: [UUID: CGRect], viewport: CGRect) -> Set<UUID> {
        guard viewport.width > 0, viewport.height > 0 else { return [] }
        return Set(frames.compactMap { id, frame in
            guard frame.width > 0, frame.height > 0 else { return nil }
            return frame.intersects(viewport) ? id : nil
        })
    }
}
