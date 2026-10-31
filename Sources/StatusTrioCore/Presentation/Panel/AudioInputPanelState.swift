import Foundation

/// Opaque selected-device identity used only to detect an input switch.
/// It intentionally excludes UID, name, and presentation metadata.
struct PanelAudioInputIdentity: Equatable, Hashable, Sendable {
    private let value: UInt32

    init(rawValue: UInt32) {
        value = rawValue
    }
}

struct AudioInputListPreferences: Equatable, Sendable {
    let order: [String]
    let hiddenUIDs: Set<String>

    init(order: [String] = [], hiddenUIDs: Set<String> = []) {
        self.order = order
        self.hiddenUIDs = hiddenUIDs
    }

    static let `default` = Self()
}

struct AudioInputPanelState: Equatable, Sendable {
    let summary: PanelSummaryState
    let selectedDeviceIdentity: PanelAudioInputIdentity?
    let scalar: Double?
    let percentageText: String
    let muteSymbol: String
    let muteTint: PanelTint
    let muteHelp: String
    let muteState: AudioInputMuteState?
    let canAdjust: Bool
    let canMute: Bool
    /// A blocking command that should disable controls and show progress.
    let isBusy: Bool
    let errorText: String?
    let showsDeviceList: Bool
    let rows: [PanelAudioDeviceRow]
    let sliderLabel: String
    let usageText: String?
    let completedScalarRequestID: UUID?
}
