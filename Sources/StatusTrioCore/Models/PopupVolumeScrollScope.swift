import Foundation

/// Where inside the status panel a scroll gesture is allowed to change the
/// volume.
enum PopupVolumeScrollScope: String, CaseIterable, Identifiable, Sendable {
    /// Anywhere in the panel that is not already a scrollable list.
    case panel

    /// Only while the pointer is over the volume control itself.
    case volumeControl

    var id: Self { self }
}
