import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case basics
    case panel
    case menuBar
    case audio
    case battery
    case updates
    case about

    var id: Self { self }

    var titleKey: LocalizationKey {
        switch self {
        case .basics: .settingsTabBasics
        case .panel: .settingsTabPanel
        case .menuBar: .settingsTabMenuBar
        case .audio: .settingsTabAudio
        case .battery: .settingsTabBattery
        case .updates: .settingsUpdatesTitle
        case .about: .settingsTabAbout
        }
    }

    var systemImage: String {
        switch self {
        case .basics: "gearshape"
        case .panel: "rectangle.on.rectangle"
        case .menuBar: "menubar.rectangle"
        case .audio: "hifispeaker"
        case .battery: "battery.100percent"
        case .updates: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .basics: .blue
        case .panel: .purple
        case .menuBar: .indigo
        case .audio: .cyan
        case .battery: .green
        case .updates: .orange
        case .about: .gray
        }
    }
}
