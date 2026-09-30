import CoreAudio
import Foundation

@MainActor
final class StatusPanelActions {
    private let outputDevices: () -> [AudioOutputDevice]
    private let selectOutputDevice: (AudioOutputDevice) -> Void
    private let inputDevices: () -> [AudioInputDevice]
    private let selectInputDevice: (AudioInputDevice) -> Void
    private let setVolumeCommand: (Double) -> Void
    private let finishVolumeCommand: () -> Void
    private let toggleMuteCommand: () -> Void
    private let setInputScalarCommand: (Double) -> Void
    private let toggleInputMuteCommand: () -> Void
    private let outputPreferences: () -> AudioOutputListPreferences

    var outputDeviceListPreferences: AudioOutputListPreferences {
        outputPreferences()
    }

    /// Narrow injection keeps command routing testable without introducing a
    /// second monitor abstraction around the existing store.
    init(
        outputDevices: @escaping () -> [AudioOutputDevice] = { [] },
        selectOutput: @escaping (AudioOutputDevice) -> Void = { _ in },
        inputDevices: @escaping () -> [AudioInputDevice] = { [] },
        selectInput: @escaping (AudioInputDevice) -> Void = { _ in },
        setVolume: @escaping (Double) -> Void = { _ in },
        finishVolumeAdjustment: @escaping () -> Void = {},
        toggleMute: @escaping () -> Void = {},
        setInputScalar: @escaping (Double) -> Void = { _ in },
        toggleInputMute: @escaping () -> Void = {},
        outputPreferences: @escaping () -> AudioOutputListPreferences = { .default }
    ) {
        self.outputDevices = outputDevices
        self.selectOutputDevice = selectOutput
        self.inputDevices = inputDevices
        self.selectInputDevice = selectInput
        self.setVolumeCommand = setVolume
        self.finishVolumeCommand = finishVolumeAdjustment
        self.toggleMuteCommand = toggleMute
        self.setInputScalarCommand = setInputScalar
        self.toggleInputMuteCommand = toggleInputMute
        self.outputPreferences = outputPreferences
    }

    convenience init(store: SystemStatusStore, settings: SettingsStore) {
        self.init(
            outputDevices: { store.liveVolume.outputDevices },
            selectOutput: { device in store.selectOutputDevice(device) },
            inputDevices: { store.liveInput.devices },
            selectInput: { device in store.selectInputDevice(device.id) },
            setVolume: { scalar in store.setVolume(scalar) },
            finishVolumeAdjustment: { store.finishVolumeAdjustment() },
            toggleMute: { store.toggleMute() },
            setInputScalar: { scalar in store.setInputScalar(scalar) },
            toggleInputMute: { store.toggleInputMute() },
            outputPreferences: {
                AudioOutputListPreferences(
                    order: settings.outputDeviceOrder,
                    visibleLimit: settings.visibleOutputDeviceLimit
                )
            }
        )
    }

    func setVolume(_ scalar: Double) {
        guard scalar.isFinite else { return }
        setVolumeCommand(min(1, max(0, scalar)))
    }

    func finishVolumeAdjustment() {
        finishVolumeCommand()
    }

    func toggleMute() {
        toggleMuteCommand()
    }

    func selectOutput(_ key: PanelAudioDeviceID) {
        guard let device = outputDevices().first(where: {
            $0.id == key.id && (key.uid == nil || $0.uid == key.uid)
        }) else { return }
        selectOutputDevice(device)
    }

    func setInputScalar(_ scalar: Double) {
        guard scalar.isFinite else { return }
        setInputScalarCommand(min(1, max(0, scalar)))
    }

    func toggleInputMute() {
        toggleInputMuteCommand()
    }

    func selectInput(_ key: PanelAudioDeviceID) {
        guard let device = inputDevices().first(where: {
            $0.id == key.id && (key.uid == nil || $0.uid == key.uid)
        }) else { return }
        selectInputDevice(device)
    }
}
