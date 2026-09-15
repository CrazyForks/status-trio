import SwiftUI

struct PopoverSectionView: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage {
            refreshIntervalGroup
            popupOrderGroup
        }
    }

    private var refreshIntervalGroup: some View {
        SettingsGroup(localization.string(.settingsRefreshInterval)) {
            SettingsRow(
                "arrow.clockwise",
                tint: .orange,
                title: localization.string(.settingsRefreshInterval),
                subtitle: localization.string(.settingsRefreshIntervalDescription)
            ) {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { store.refreshIntervalSeconds },
                            set: { store.refreshIntervalSeconds = ($0 / 5).rounded() * 5 }
                        ),
                        in: SettingsStore.refreshIntervalRange
                    )
                    .frame(width: 130)
                    .controlSize(.small)
                    .accessibilityLabel(localization.string(.settingsRefreshInterval))
                    .accessibilityValue(
                        localization.format(
                            .settingsRefreshIntervalValue,
                            Int(store.refreshIntervalSeconds)
                        )
                    )

                    Text(
                        localization.format(
                            .settingsRefreshIntervalValue,
                            Int(store.refreshIntervalSeconds)
                        )
                    )
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }

    private var popupOrderGroup: some View {
        SettingsGroup(
            localization.string(.settingsPopupOrder),
            footnote: localization.string(.settingsPopupOrderDescription)
        ) {
            SettingsCustomRow(
                "list.number",
                tint: .indigo,
                title: localization.string(.settingsPopupOrder)
            ) {
                List {
                    ForEach(store.popupSectionOrder) { section in
                        HStack(spacing: 10) {
                            popupSectionIcon(section)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

                            Text(localization.string(section.titleKey))
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { source, destination in
                        store.movePopupSections(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.inset)
                .frame(height: popupOrderListHeight)
            }
        }
    }

    @ViewBuilder
    private func popupSectionIcon(_ section: PopupSection) -> some View {
        if section == .bluetooth {
            BluetoothIcon(size: 16)
        } else {
            Image(systemName: section.systemImage)
                .font(.system(size: 13))
        }
    }

    private var popupOrderListHeight: CGFloat {
        min(max(CGFloat(store.popupSectionOrder.count) * 32 + 12, 48), 180)
    }
}
