import Foundation

struct PanelBluetoothDeviceRow: Equatable, Sendable {
    let address: String
    let title: String
    let subtitle: String?
    let icon: IconSymbolSource
    let batteryText: String?
    let actionTitle: String
    let actionEnabled: Bool
    let isBusy: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
}

struct BluetoothPanelState: Equatable, Sendable {
    let summary: PanelSummaryState
    let pairedRows: [PanelBluetoothDeviceRow]
    let nearbyRows: [PanelBluetoothDeviceRow]
    let errorText: String?
    let showsPairedHeading: Bool
    let canExpand: Bool
    let confirmationAddress: String?
}
