import CoreAudio
import SwiftUI

/// Holds only the slider's temporary drag value; system readback remains authoritative.
struct AudioInputVolumeDraft {
    private(set) var value = 0.0
    private(set) var isEditing = false
    private var latestSystemScalar: Double?

    mutating func receiveSystemScalar(_ scalar: Double?) {
        latestSystemScalar = scalar
        guard !isEditing else { return }
        value = Self.displayValue(for: scalar)
    }

    mutating func setEditing(_ editing: Bool) {
        isEditing = editing
        if !editing {
            value = Self.displayValue(for: latestSystemScalar)
        }
    }

    mutating func setSliderValue(
        _ newValue: Double,
        systemScalar: Double?,
        onScalarChange: (Double) -> Void
    ) {
        guard isEditing, newValue.isFinite,
              let systemScalar, systemScalar.isFinite,
              (0...1).contains(systemScalar) else { return }
        value = min(1, max(0, newValue))
        guard abs(value - Self.displayValue(for: systemScalar)) >= 0.0005 else { return }
        onScalarChange(value)
    }

    mutating func resetForDevice(_ scalar: Double?) {
        isEditing = false
        receiveSystemScalar(scalar)
    }

    func accessibilityValue(systemScalar: Double?, locale: Locale) -> String {
        guard let systemScalar, systemScalar.isFinite, (0...1).contains(systemScalar) else {
            return "—"
        }
        let displayedValue = isEditing ? value : systemScalar
        return displayedValue.formatted(
            .percent.precision(.fractionLength(0)).locale(locale)
        )
    }

    private static func displayValue(for scalar: Double?) -> Double {
        guard let scalar, scalar.isFinite, (0...1).contains(scalar) else { return 0 }
        return scalar
    }
}

struct AudioInputControlsView: View {
    @EnvironmentObject private var localization: Localization

    let status: AudioInputStatus
    let onSelect: (AudioDeviceID) -> Void
    let onScalarChange: (Double) -> Void
    let onToggleMute: () -> Void
    let onOpenSoundSettings: () -> Void

    @State private var volumeDraft = AudioInputVolumeDraft()

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
        volumeDraft.accessibilityValue(
            systemScalar: status.scalar,
            locale: localization.resolvedLanguage.locale
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
        .onAppear(perform: { volumeDraft.receiveSystemScalar(status.scalar) })
        .onChange(of: status.defaultDeviceID) { _, _ in
            volumeDraft.resetForDevice(status.scalar)
        }
        .onChange(of: status.scalar) { _, newScalar in
            volumeDraft.receiveSystemScalar(newScalar)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(presentation.isDefaultInputInUse ? Color.white : Color.secondary)
                .frame(width: 24, height: 24)
                .background {
                    Capsule()
                        .fill(presentation.isDefaultInputInUse ? Color.orange : Color.clear)
                        .frame(width: 32, height: 26)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(localization.string(.audioInputTitle))
                        .font(.headline)
                        .foregroundStyle(presentation.isDefaultInputInUse ? Color.yellow : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

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

            ZStack {
                Slider(
                    value: sliderValue,
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing {
                            volumeDraft.receiveSystemScalar(status.scalar)
                        }
                        volumeDraft.setEditing(editing)
                    }
                )
                .tint(status.muteState == .muted ? Color.secondary : Color.accentColor)
                .disabled(!presentation.volumeEnabled)
                .help(volumeControlHint)
                .accessibilityLabel(localization.string(.audioInputVolume))
                .accessibilityValue(sliderAccessibilityValue)
                .accessibilityHint(
                    presentation.volumeEnabled ? "" : localization.string(.audioInputVolumeUnavailable)
                )

                if !presentation.hasReadableVolume {
                    Text("—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .background(.background)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)

            Text(presentation.visibleVolumeValue)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, alignment: .trailing)
                .accessibilityHidden(true)

            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
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
                ZStack {
                    Circle()
                        .fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.14))

                    Image(systemName: isCurrent ? "mic.fill" : "mic")
                        .foregroundStyle(isCurrent ? Color.white : Color.secondary)
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

                Text(displayName)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    private var sliderValue: Binding<Double> {
        Binding(
            get: { presentation.hasReadableVolume ? volumeDraft.value : 0.5 },
            set: { newValue in
                volumeDraft.setSliderValue(newValue, systemScalar: status.scalar) {
                    onScalarChange($0)
                }
            }
        )
    }
}
