import Foundation

/// Which scroll direction raises the volume.
enum PopupVolumeScrollDirection: String, CaseIterable, Identifiable, Sendable {
    /// A two-finger swipe up (or a wheel rolled away from the user) is louder.
    case up

    /// A two-finger swipe down (or a wheel rolled towards the user) is louder.
    case down

    var id: Self { self }

    /// `true` when a scroll-up gesture raises the volume.
    var increasesWithScrollUp: Bool {
        switch self {
        case .up: true
        case .down: false
        }
    }
}
