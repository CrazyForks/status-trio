import Foundation

enum DockIconBackgroundStyle: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light
    case clear

    var id: Self { self }
}
