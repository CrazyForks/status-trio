import Foundation

enum AppIconPlacement: String, CaseIterable, Identifiable, Sendable {
    case menuBar
    case dock
    case both

    var id: Self { self }

    var showsMenuBarIcon: Bool {
        self != .dock
    }

    var showsDockIcon: Bool {
        self != .menuBar
    }
}
