import Foundation

/// Pure authorization snapshots used by the Bluetooth summary.
///
/// macOS 13's single-parameter `onChange` closure can run with the previous
/// render's captured values. Passing the changed snapshot explicitly keeps the
/// authorization decision on the value that triggered the callback.
enum BluetoothVisibilityAuthorization {
    static func trustedIDs(
        visibleIDs: Set<AppleDeviceID>,
        currentCandidates: [AppleDeviceCandidate]
    ) -> Set<AppleDeviceID> {
        AppleDeviceCatalog.readAuthorizedIDs(
            visibleIDs: visibleIDs,
            currentCandidates: currentCandidates
        )
    }

    static func nearbyIDs(
        visibleIDs: Set<UUID>,
        showsBatteryLevels: Bool,
        showsAppleDevicesAndBattery: Bool,
        showsList: Bool
    ) -> Set<UUID> {
        guard showsBatteryLevels, showsAppleDevicesAndBattery, showsList else { return [] }
        return visibleIDs
    }
}

struct BluetoothSummaryReadAuthorizationSnapshot: Equatable {
    let showsBatteryLevels: Bool
    let showsAppleDevicesAndBattery: Bool
    let showsList: Bool
    let currentTrustedAppleCandidates: [AppleDeviceCandidate]

    var showsMobileBatteryFeature: Bool {
        showsBatteryLevels && showsAppleDevicesAndBattery && showsList
    }
}
