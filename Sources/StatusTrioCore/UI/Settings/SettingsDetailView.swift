import SwiftUI

struct SettingsDetailView: View {
    let tab: SettingsTab
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization

    @ViewBuilder
    var body: some View {
        switch tab {
        case .basics:
            BasicsSettingsPane(localization: localization)
        case .menuBar:
            MenuBarSettingsPane(store: store)
        case .audio:
            AudioSettingsPane(store: store, statusStore: statusStore)
        case .battery:
            BatterySettingsPane(store: store)
        case .updates:
            UpdatesSettingsPane()
        case .about:
            AboutSettingsPane()
        case .preview:
            PreviewSettingsPane(statusStore: statusStore)
        }
    }
}
