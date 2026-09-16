import SwiftUI

struct AudioOutputPickerView: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var settings: SettingsStore
    let devices: [AudioOutputDevice]
    let onSelect: (AudioOutputDevice) -> Void
    let onOpenSoundSettings: () -> Void
    @State private var isExpanded = false

    var body: some View {
        if settings.alwaysShowsAllOutputDevices {
            AudioOutputPickerContent(
                settings: settings, devices: devices,
                onSelect: onSelect, onOpenSoundSettings: onOpenSoundSettings
            )
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                AudioOutputPickerContent(
                    settings: settings, devices: devices,
                    onSelect: onSelect, onOpenSoundSettings: onOpenSoundSettings
                )
                .padding(.top, 4)
            } label: {
                Text(localization.string(.volumeOutputChoose))
                    .font(.callout)
                    .frame(minHeight: 24)
            }
        }
    }
}

private struct AudioOutputPickerContent: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var settings: SettingsStore
    let devices: [AudioOutputDevice]
    let onSelect: (AudioOutputDevice) -> Void
    let onOpenSoundSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OutputDeviceList(settings: settings, devices: devices, onSelect: onSelect)

            Button(localization.string(.volumeActionOpenSettings), action: onOpenSoundSettings)
                .font(.callout)
                .padding(.vertical, 4)
        }
    }
}
