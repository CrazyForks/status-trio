import Foundation

enum DockIconBackgroundStyle: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light

    var id: Self { self }
}
