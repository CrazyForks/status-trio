enum DockActivationAction: Equatable {
    case showPopover
    case openSettings
    case none

    /// Decides what a Dock activation should do.
    ///
    /// Clicking the Dock icon of a running app delivers a reopen event, so that
    /// is what opens the status popover. A cold launch also arrives here on some
    /// launch paths (and at login), and must not pop anything open.
    ///
    /// Launchpad, Finder and Spotlight send the same reopen event, so the pointer
    /// position decides between "clicked the Dock icon" and "opened the app".
    static func resolve(
        isReopenEvent: Bool,
        hasDockTile: Bool,
        isPointerInDockArea: Bool
    ) -> DockActivationAction {
        guard isReopenEvent else { return .none }
        guard hasDockTile else { return .openSettings }
        return isPointerInDockArea ? .showPopover : .openSettings
    }
}
