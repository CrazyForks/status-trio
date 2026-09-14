import SwiftUI

struct OutputDeviceList: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var settings: SettingsStore
    let devices: [AudioOutputDevice]
    let onSelect: (AudioOutputDevice) -> Void

    @State private var isExpanded = false

    var body: some View {
        if devices.isEmpty {
            Label(localization.string(.volumeOutputEmpty), systemImage: "questionmark.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else {
            VStack(spacing: 2) {
                deviceRows

                if canToggleExpansion {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))

                            Text(
                                localization.string(
                                    isExpanded
                                        ? .volumeOutputCollapse
                                        : .volumeOutputExpand
                                )
                            )
                            .font(.callout)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var orderedDevices: [AudioOutputDevice] {
        settings.orderedOutputDevices(devices)
    }

    private var visibleDevices: [AudioOutputDevice] {
        OutputDeviceListPresentation.visibleDevices(
            from: orderedDevices,
            limit: settings.visibleOutputDeviceLimit,
            isExpanded: isExpanded
        )
    }

    private var canToggleExpansion: Bool {
        OutputDeviceListPresentation.canToggleExpansion(
            for: orderedDevices,
            limit: settings.visibleOutputDeviceLimit
        )
    }

    private var deviceRows: some View {
        LazyVStack(spacing: 2) {
            ForEach(visibleDevices) { device in
                OutputDeviceRow(device: device, onSelect: onSelect)
            }
        }
    }
}
