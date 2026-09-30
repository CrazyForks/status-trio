import Foundation

struct AudioInputPanelState: Equatable, Sendable {
    let summary: PanelSummaryState
    let scalar: Double?
    let percentageText: String
    let muteSymbol: String
    let muteTint: PanelTint
    let muteHelp: String
    let muteState: AudioInputMuteState?
    let canAdjust: Bool
    let canMute: Bool
    let isBusy: Bool
    let errorText: String?
    let showsDeviceList: Bool
    let rows: [PanelAudioDeviceRow]
    let sliderLabel: String
    let usageText: String?
}
