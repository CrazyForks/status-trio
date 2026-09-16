import SwiftUI

struct OutputDeviceList: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var settings: SettingsStore
    let devices: [AudioOutputDevice]
    let onSelect: (AudioOutputDevice) -> Void

    @State private var isExpanded = false

    var body: some View {
        let model = OutputDeviceListModel.make(
            devices: devices,
            order: settings.outputDeviceOrder,
            limit: settings.visibleOutputDeviceLimit,
            isExpanded: isExpanded
        )

        if devices.isEmpty {
            Label(localization.string(.volumeOutputEmpty), systemImage: "questionmark.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else {
            VStack(spacing: 2) {
                deviceRows(model.visibleDevices)

                if model.canToggleExpansion {
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

    private func deviceRows(_ devices: [AudioOutputDevice]) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(devices) { device in
                OutputDeviceRow(device: device, onSelect: onSelect)
            }
        }
    }
}
