enum DockActivationAction: Equatable {
    case showPopover
    case openSettings
    case none

    /// Decides what a Dock activation should do.
    ///
    /// Clicking the Dock icon of a running app delivers a reopen event, so that
    /// is what opens the status popover. A cold launch also arrives here on some
    /// launch paths (and at login), and must not pop anything open.
    static func resolve(isReopenEvent: Bool, hasDockTile: Bool) -> DockActivationAction {
        guard isReopenEvent else { return .none }
        return hasDockTile ? .showPopover : .openSettings
    }
}
