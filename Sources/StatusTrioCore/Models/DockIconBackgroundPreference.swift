import Foundation

enum DockIconBackgroundPreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case dark
    case light

    var id: Self { self }
}
