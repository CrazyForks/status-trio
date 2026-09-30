import SwiftUI

struct VolumeControlsView: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var settings: SettingsStore
    @ObservedObject var bluetoothController: BluetoothDeviceController
    @ObservedObject var listeningModes: BluetoothListeningModeController
    let scrollTargets: PopoverScrollTargets
    let volume: VolumeStatus
    let isEnabled: Bool
    let onVolumeChange: (Double) -> Void
    let onToggleMute: () -> Void
    let onSelectOutputDevice: (AudioOutputDevice) -> Void
    let onOpenSoundSettings: () -> Void

    @State private var draftVolume = 0.0
    @State private var isAdjusting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VolumeOutputSummaryView(volume: volume)

                Button(
                    localization.string(.volumeActionOpenSettings),
                    systemImage: "gearshape",
                    action: onOpenSoundSettings
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(localization.string(.volumeActionOpenSettings))
                .accessibilityLabel(localization.string(.volumeActionOpenSettings))
                .frame(width: 24, height: 24)
            }

            HStack(spacing: 10) {
                Button(action: onToggleMute) {
                    Image(systemName: volumeSymbolName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(volume.isMuted ? Color.red : Color.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .help(volume.isMuted ? localization.string(.volumeUnmuted) : localization.string(.volumeMuted))
                .accessibilityLabel(volume.isMuted ? localization.string(.volumeUnmuted) : localization.string(.volumeMuted))

                Slider(
                    value: $draftVolume,
                    in: 0...1,
                    onEditingChanged: { handleVolumeEditing($0) }
                )
                .tint(volume.isMuted ? Color.secondary : Color.accentColor)
                .disabled(!isEnabled)
                .accessibilityLabel(localization.string(.volumeAccessibilityLabel))
                .accessibilityValue(percentageText)
                .padding(.horizontal, 2)
                // Only the control row is a scroll target; the output device
                // list below stays a normal list.
                .background(VolumeControlScrollTarget(targets: scrollTargets))

                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            if showsOutputList {
                Divider()
                    .padding(.top, 2)

                OutputDeviceList(
                    settings: settings,
                    devices: volume.outputDevices,
                    onSelect: onSelectOutputDevice,
                    previewDevices: previewOutputRows,
                    previewLocalization: previewLocalization,
                    controlProvider: { device in
                        listeningModes.control(forEndpoint: device.id)?.presentation
                    },
                    onSelectListeningMode: { device, mode in
                        if let control = listeningModes.control(forEndpoint: device.id) {
                            listeningModes.setMode(mode, forAddress: control.address)
                        }
                    }
                )
            }
        }
        .onAppear(perform: { synchronizeVolume() })
        .onChange(of: draftVolume) { _, newValue in
            updateVolume(newValue)
        }
        .onChange(of: volume.scalar) { _, _ in
            guard !isAdjusting else { return }
            synchronizeVolume()
        }
        .task(id: listeningModeTaskID) {
            // The AirPods listening-mode control lives on this list, so the volume
            // section owns the controller's discovery: one pass per change of the
            // connected AirPods, the preview toggle, or the preview device set —
            // never on a timer. The preview flag is pushed immediately before
            // `refresh` so a mid-session toggle takes effect on the next publish.
            listeningModes.previewMode = previewConfig.isEnabled
            listeningModes.refresh(
                devices: bluetoothController.devices + ListeningModePreview.devices(for: previewConfig)
            )
        }
        .onDisappear {
            listeningModes.stop()
        }
    }

    private var previewConfig: ListeningModePreview.Configuration {
        ListeningModePreview.Configuration(
            isEnabled: settings.previewsBluetoothListeningMode,
            deviceName: settings.bluetoothListeningModePreviewDeviceName,
            deviceCount: settings.bluetoothListeningModePreviewDeviceCount,
            languageCode: settings.bluetoothListeningModePreviewLanguage
        )
    }

    private var previewOutputRows: [AudioOutputDevice] {
        ListeningModePreview.outputRows(for: previewConfig, volume: volume.scalar)
    }

    /// The list is worth showing when there is more than one real output device, or
    /// when the preview injects synthetic AirPods rows to exercise the control.
    private var showsOutputList: Bool {
        volume.outputDevices.count > 1 || !previewOutputRows.isEmpty
    }

    /// The language the preview rows render in, or `nil` to follow the panel. Only
    /// the synthetic rows pick this up, so a language override never restyles the
    /// real output devices above them.
    private var previewLocalization: Localization? {
        PreviewLocalization.forCode(previewConfig.languageCode)
    }

    /// The connected AirPods, by normalized address, plus the preview flag and the
    /// synthetic preview device addresses. Discovery re-runs only when this changes,
    /// so it does not repeat while the same devices sit unchanged on screen, and a
    /// preview count / name / toggle change re-runs it rather than leaving a stale
    /// capsule set.
    private var listeningModeTaskID: String {
        let connected = BluetoothDevicePresentation.grouped(bluetoothController.devices).connected
            .filter(\.isAirPods)
            .map { BluetoothBatteryReader.normalizedAddress($0.id) }
            .joined(separator: ",")
        let preview = previewConfig.isEnabled ? "|preview" : ""
        let synthetic = ListeningModePreview.devices(for: previewConfig)
            .map { BluetoothBatteryReader.normalizedAddress($0.id) }
            .joined(separator: ",")
        return connected + preview + (synthetic.isEmpty ? "" : "|\(synthetic)")
    }

    private var volumeSymbolName: String {
        if volume.isMuted {
            return "speaker.slash.fill"
        }
        guard let scalar = volume.scalar, scalar > 0 else {
            return "speaker.fill"
        }
        if scalar < 0.33 {
            return "speaker.wave.1.fill"
        } else if scalar < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    private var percentageText: String {
        guard draftVolume.isFinite else { return "—" }
        return min(1, max(0, draftVolume)).formatted(
            .percent.precision(.fractionLength(0))
                .locale(localization.resolvedLanguage.locale)
        )
    }

    private func handleVolumeEditing(_ isEditing: Bool) {
        isAdjusting = isEditing
    }

    private func updateVolume(_ newValue: Double) {
        let scalar = volume.scalar ?? -1
        guard scalar.isFinite,
              abs(newValue - min(1, max(0, scalar))) >= 0.0005 else {
            return
        }
        onVolumeChange(newValue)
    }

    private func synchronizeVolume() {
        guard let scalar = volume.scalar, scalar.isFinite else {
            draftVolume = 0
            return
        }
        draftVolume = min(1, max(0, scalar))
    }
}
