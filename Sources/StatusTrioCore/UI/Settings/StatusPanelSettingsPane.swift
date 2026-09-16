import AppKit
import SwiftUI

struct StatusPanelSettingsPane: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        PreferencesPane {
            PreferenceRow(
                label: .settingsPopupOrder,
                description: .settingsPopupOrderDescription
            ) {
                List {
                    ForEach(store.popupSectionOrder) { section in
                        HStack(spacing: 8) {
                            Toggle("", isOn: visibilityBinding(for: section))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .accessibilityLabel(localization.string(section.titleKey))

                            popupSectionIcon(section)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            Text(localization.string(section.titleKey))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { source, destination in
                        store.movePopupSections(
                            fromOffsets: source,
                            toOffset: destination
                        )
                    }
                }
                .listStyle(.inset)
                .frame(height: popupListHeight)
            }
        }
    }

    private func visibilityBinding(for section: PopupSection) -> Binding<Bool> {
        Binding(
            get: { store.enabledPopupSections.contains(section) },
            set: { enabled in
                let wasEnabled = store.enabledPopupSections.contains(section)
                store.setPopupSection(section, enabled: enabled)

                guard section == .bluetooth, enabled != wasEnabled else { return }
                if enabled {
                    NSApp.activate()
                }
                statusStore.setBluetoothEnabled(enabled)
            }
        )
    }

    @ViewBuilder
    private func popupSectionIcon(_ section: PopupSection) -> some View {
        if section == .bluetooth {
            BluetoothIcon(size: 18)
        } else {
            Image(systemName: section.systemImage)
        }
    }

    private var popupListHeight: CGFloat {
        min(max(CGFloat(store.popupSectionOrder.count) * 28 + 8, 44), 168)
    }
}
