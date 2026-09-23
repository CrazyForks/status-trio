import CoreAudio
import SwiftUI

/// Derives stable presentation values from one input-device reading.
struct AudioInputPresentation {
    let status: AudioInputStatus
    let locale: Locale

    init(status: AudioInputStatus, locale: Locale = .current) {
        self.status = status
        self.locale = locale
    }

    static func ordered(
        _ devices: [AudioInputDevice],
        currentID: AudioDeviceID?,
        locale: Locale,
        unknownName: String
    ) -> [AudioInputDevice] {
        devices.sorted { lhs, rhs in
            let lhsIsCurrent = lhs.id == currentID
            let rhsIsCurrent = rhs.id == currentID
            if lhsIsCurrent != rhsIsCurrent {
                return lhsIsCurrent
            }

            let comparison = displayName(for: lhs, unknownName: unknownName)
                .compare(
                    displayName(for: rhs, unknownName: unknownName),
                    options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                    range: nil,
                    locale: locale
                )
            if comparison == .orderedSame {
                return lhs.id < rhs.id
            }
            return comparison == .orderedAscending
        }
    }

    static func displayName(for device: AudioInputDevice, unknownName: String) -> String {
        guard let name = device.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return unknownName
        }
        return name
    }

    static func needsDevicePosition(
        for device: AudioInputDevice,
        among devices: [AudioInputDevice],
        unknownName: String,
        locale: Locale
    ) -> Bool {
        guard let name = device.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return true
        }

        return devices.contains { candidate in
            guard candidate.id != device.id else { return false }
            return displayName(for: candidate, unknownName: unknownName)
                .compare(
                    displayName(for: device, unknownName: unknownName),
                    options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                    range: nil,
                    locale: locale
                ) == .orderedSame
        }
    }

    static func deviceAccessibilityLabel(
        name: String,
        position: String?,
        current: String?,
        combine: (String, String) -> String
    ) -> String {
        var label = name
        if let position, !position.isEmpty {
            label = combine(label, position)
        }
        if let current, !current.isEmpty {
            label = combine(label, current)
        }
        return label
    }

    static func errorLocalizationKey(for error: AudioInputError) -> LocalizationKey {
        switch error {
        case .refreshFailed:
            .audioInputRefreshFailed
        case .switchFailed:
            .audioInputSwitchFailed
        case .volumeFailed:
            .audioInputVolumeFailed
        case .muteFailed:
            .audioInputMuteFailed
        case .timedOut:
            .audioInputTimedOut
        }
    }

    var showsDeviceList: Bool {
        !status.devices.isEmpty
    }

    var volumeEnabled: Bool {
        status.defaultDeviceID != nil
            && status.canSetVolume
            && status.scalar?.isFinite == true
            && !status.isBusy
    }

    var muteEnabled: Bool {
        status.defaultDeviceID != nil
            && status.canSetMute
            && status.muteState != nil
            && !status.isBusy
    }

    var nextMuteValue: Bool {
        status.muteState != .muted
    }

    var volumeAccessibilityValue: String {
        guard let scalar = status.scalar, scalar.isFinite else { return "—" }
        return min(1, max(0, scalar)).formatted(
            .percent.precision(.fractionLength(0)).locale(locale)
        )
    }
}

struct AudioInputControlsView: View {
    @EnvironmentObject private var localization: Localization

    let status: AudioInputStatus
    let onSelect: (AudioDeviceID) -> Void
    let onScalarChange: (Double) -> Void
    let onToggleMute: () -> Void
    let onOpenSoundSettings: () -> Void

    @State private var draftVolume = 0.0
    @State private var isAdjustingVolume = false

    private var presentation: AudioInputPresentation {
        AudioInputPresentation(status: status, locale: localization.resolvedLanguage.locale)
    }

    private var orderedDevices: [AudioInputDevice] {
        AudioInputPresentation.ordered(
            status.devices,
            currentID: status.defaultDeviceID,
            locale: localization.resolvedLanguage.locale,
            unknownName: localization.string(.audioInputUnknownDevice)
        )
    }

    private var defaultDeviceName: String {
        guard let defaultDeviceID = status.defaultDeviceID else {
            return localization.string(.audioInputNoDefault)
        }
        if let name = status.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let device = status.devices.first(where: { $0.id == defaultDeviceID }) {
            return AudioInputPresentation.displayName(
                for: device,
                unknownName: localization.string(.audioInputUnknownDevice)
            )
        }
        return localization.string(.audioInputUnknownDevice)
    }

    private var muteActionLabel: String {
        localization.string(presentation.nextMuteValue ? .audioInputMute : .audioInputUnmute)
    }

    private var muteControlHint: String {
        presentation.muteEnabled
            ? muteActionLabel
            : localization.string(.audioInputMuteUnavailable)
    }

    private var volumeControlHint: String {
        presentation.volumeEnabled
            ? localization.string(.audioInputVolume)
            : localization.string(.audioInputVolumeUnavailable)
    }

    private var sliderAccessibilityValue: String {
        guard isAdjustingVolume, draftVolume.isFinite else {
            return presentation.volumeAccessibilityValue
        }
        return min(1, max(0, draftVolume)).formatted(
            .percent.precision(.fractionLength(0)).locale(localization.resolvedLanguage.locale)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            controls
            deviceList

            if let error = status.error {
                Label(
                    localization.string(AudioInputPresentation.errorLocalizationKey(for: error)),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityElement(children: .combine)
            } else if status.isRefreshing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    Text(localization.string(.audioInputRefreshing))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: { synchronizeVolume() })
        .onChange(of: status.defaultDeviceID) { _, _ in
            isAdjustingVolume = false
            synchronizeVolume()
        }
        .onChange(of: status.scalar) { _, _ in
            guard !isAdjustingVolume else { return }
            synchronizeVolume()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(localization.string(.audioInputTitle))
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(defaultDeviceName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(defaultDeviceName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onOpenSoundSettings) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localization.string(.audioInputOpenSettings))
            .accessibilityLabel(localization.string(.audioInputOpenSettings))
            .frame(width: 24, height: 24)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: onToggleMute) {
                HStack(spacing: 6) {
                    muteIcon
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(status.muteState == .muted ? Color.red : Color.secondary)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)

                    if status.muteState == .partial {
                        Text(localization.string(.audioInputPartial))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!presentation.muteEnabled)
            .help(muteControlHint)
            .accessibilityLabel(muteActionLabel)
            .accessibilityValue(
                status.muteState == .partial ? localization.string(.audioInputPartial) : ""
            )
            .accessibilityHint(
                presentation.muteEnabled ? "" : localization.string(.audioInputMuteUnavailable)
            )

            Slider(
                value: $draftVolume,
                in: 0...1,
                onEditingChanged: { isAdjustingVolume = $0 }
            )
            .tint(status.muteState == .muted ? Color.secondary : Color.accentColor)
            .disabled(!presentation.volumeEnabled)
            .help(volumeControlHint)
            .accessibilityLabel(localization.string(.audioInputVolume))
            .accessibilityValue(sliderAccessibilityValue)
            .accessibilityHint(
                presentation.volumeEnabled ? "" : localization.string(.audioInputVolumeUnavailable)
            )

            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .onChange(of: draftVolume) { _, newValue in
            updateVolume(newValue)
        }
    }

    @ViewBuilder
    private var muteIcon: some View {
        switch status.muteState {
        case .muted:
            Image(systemName: "mic.slash.fill")
        case .partial:
            Image(systemName: "mic.fill")
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                }
        case .unmuted, .none:
            Image(systemName: "mic.fill")
        }
    }

    @ViewBuilder
    private var deviceList: some View {
        if presentation.showsDeviceList {
            Divider()
                .padding(.top, 2)

            VStack(spacing: 2) {
                ForEach(orderedDevices.indices, id: \.self) { index in
                    let device = orderedDevices[index]
                    deviceRow(device, position: index + 1)
                }
            }
        } else {
            Label(localization.string(.audioInputNoDevices), systemImage: "mic.slash")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    private func deviceRow(_ device: AudioInputDevice, position: Int) -> some View {
        let displayName = AudioInputPresentation.displayName(
            for: device,
            unknownName: localization.string(.audioInputUnknownDevice)
        )
        let isCurrent = device.id == status.defaultDeviceID
        let needsPosition = AudioInputPresentation.needsDevicePosition(
            for: device,
            among: orderedDevices,
            unknownName: localization.string(.audioInputUnknownDevice),
            locale: localization.resolvedLanguage.locale
        )
        let positionLabel = needsPosition
            ? localization.format(.audioInputDevicePosition, position)
            : nil
        let currentLabel = isCurrent ? localization.string(.audioInputCurrent) : nil
        let accessibilityLabel = AudioInputPresentation.deviceAccessibilityLabel(
            name: displayName,
            position: positionLabel,
            current: currentLabel
        ) { first, second in
            localization.format(.commonParenthetical, first, second)
        }
        let help = isCurrent
            ? localization.format(
                .commonLabelValue,
                displayName,
                localization.string(.audioInputCurrent)
            )
            : localization.format(.audioInputSwitchTo, displayName)

        return Button {
            guard !isCurrent else { return }
            onSelect(device.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCurrent ? "mic.fill" : "mic")
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                Text(displayName)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(status.isBusy)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isCurrent ? "" : help)
    }

    private func synchronizeVolume() {
        guard let scalar = status.scalar, scalar.isFinite else {
            draftVolume = 0
            return
        }
        draftVolume = min(1, max(0, scalar))
    }

    private func updateVolume(_ newValue: Double) {
        guard newValue.isFinite,
              let scalar = status.scalar,
              scalar.isFinite,
              abs(newValue - min(1, max(0, scalar))) >= 0.0005 else {
            return
        }
        onScalarChange(min(1, max(0, newValue)))
    }
}
