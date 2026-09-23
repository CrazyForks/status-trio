import Foundation

enum DockIconBackgroundPreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case dark
    case light

    var id: Self { self }

    var settingsSymbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .dark: "moon.fill"
        case .light: "sun.max.fill"
        }
    }
}
