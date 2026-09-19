import AppKit

extension NSWindow {
    /// Makes a status-item popover's backing window appear on every Space,
    /// including another app's full-screen Space.
    ///
    /// AppKit creates the popover's backing window with no Spaces behavior,
    /// which ties it to the single desktop Space this accessory app occupies:
    /// over a full-screen app the popover is shown on the desktop Space
    /// instead, so the status-item click looks like it did nothing. `NSPopover`
    /// has no backing window until it is first shown, so this belongs right
    /// after `show(relativeTo:of:preferredEdge:)`.
    func enableDisplayOnFullScreenSpaces() {
        // `.moveToActiveSpace` and `.canJoinAllSpaces` are mutually exclusive,
        // and AppKit raises NSInternalInconsistencyException — aborting the app
        // — when both are set, so the conflicting flag has to go first.
        // Behavior outside the Spaces pair is preserved.
        collectionBehavior.remove(.moveToActiveSpace)
        collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
    }
}
