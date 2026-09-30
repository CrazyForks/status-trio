import Foundation

/// The synthetic preview that lets the AirPods listening-mode control be exercised
/// on a Mac with no controllable AirPods.
///
/// The control now lives on the audio output list (only the current AirPods output
/// can switch its mode), so a preview has to fake an *output* row, not just a
/// Bluetooth row. This type is the single source of truth that keeps the two ends
/// of a preview row in step: it mints the paired `BluetoothDevice`s the listening-
/// mode controller publishes a preview presentation for, and the matching
/// `AudioOutputDevice` rows the output list renders — tied together by the
/// controller's synthetic endpoint (`BluetoothListeningModeController
/// .syntheticEndpoint(for:)`), so the row looks up its capsule exactly as a real
/// AirPods output does.
///
/// Nothing here reaches CoreAudio or a device: it is display scaffolding driven by
/// the Settings preview toggle, and switching the toggle off makes it vanish.
@MainActor
enum ListeningModePreview {
    /// The name a preview row falls back to when no override is typed in. It
    /// contains "AirPods" so the block reads as recognisable hardware even blank.
    static let defaultDeviceName = "AirPods Pro"

    struct Configuration: Equatable {
        var isEnabled: Bool
        var deviceName: String
        var deviceCount: Int
        var languageCode: String

        static let disabled = Configuration(
            isEnabled: false,
            deviceName: "",
            deviceCount: 0,
            languageCode: ""
        )
    }

    /// The requested count, clamped to the Settings range so a stale larger value in
    /// `UserDefaults` cannot mint a runaway list.
    static func clampedDeviceCount(_ count: Int) -> Int {
        min(max(count, 0), SettingsStore.bluetoothListeningModePreviewDeviceCountRange.upperBound)
    }

    /// The display name, falling back to the built-in default when the override is
    /// empty. Any non-empty string is used verbatim, so a long truncation stress
    /// test still renders.
    static func resolvedDeviceName(_ config: Configuration) -> String {
        config.deviceName.isEmpty ? defaultDeviceName : config.deviceName
    }

    /// The synthetic paired devices, fed to `BluetoothListeningModeController.refresh`
    /// so it publishes a three-capsule preview presentation for each. Each carries a
    /// preview-prefixed address, so the controller's `isAirPods` name heuristic no
    /// longer gates eligibility and a renamed preview row still renders.
    static func devices(for config: Configuration) -> [BluetoothDevice] {
        guard config.isEnabled, clampedDeviceCount(config.deviceCount) > 0 else { return [] }
        let name = resolvedDeviceName(config)
        return (1...clampedDeviceCount(config.deviceCount)).map { index in
            BluetoothDevice(
                id: "\(BluetoothListeningModeController.previewAddressPrefix)\(index)",
                name: name,
                kind: .audio,
                isConnected: true
            )
        }
    }

    /// The synthetic output rows, appended to the real output list for display. Each
    /// carries the same synthetic endpoint the controller minted for its paired
    /// device, is marked the current output, and is tagged Bluetooth so the row
    /// lights up its capsules the way a real AirPods output does. `volume` is the
    /// current output level the caller passes through so the row also draws its
    /// trailing percentage exactly like the real output row it stands in for.
    static func outputRows(for config: Configuration, volume: Double? = nil) -> [AudioOutputDevice] {
        guard config.isEnabled, clampedDeviceCount(config.deviceCount) > 0 else { return [] }
        let name = resolvedDeviceName(config)
        return (1...clampedDeviceCount(config.deviceCount)).compactMap { index in
            let id = "\(BluetoothListeningModeController.previewAddressPrefix)\(index)"
            guard let endpoint = BluetoothListeningModeController.syntheticEndpoint(for: id) else {
                return nil
            }
            return AudioOutputDevice(
                id: endpoint,
                name: name,
                isCurrent: true,
                volume: volume,
                transport: .bluetooth
            )
        }
    }
}
