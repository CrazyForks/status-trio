import Testing
@testable import StatusTrioCore

struct DockActivationActionTests {
    @Test func dockClickShowsThePopoverWhenTheAppOwnsADockTile() {
        #expect(
            DockActivationAction.resolve(
                isReopenEvent: true,
                hasDockTile: true,
                isPointerInDockArea: true
            ) == .showPopover
        )
    }

    @Test func dockClickOpensSettingsWhenThereIsNoDockTile() {
        #expect(
            DockActivationAction.resolve(
                isReopenEvent: true,
                hasDockTile: false,
                isPointerInDockArea: true
            ) == .openSettings
        )
    }

    @Test func openingTheAppFromLaunchpadOpensSettings() {
        // Launchpad, Finder and Spotlight deliver the same reopen event as a Dock
        // click, so the pointer position is what tells them apart.
        #expect(
            DockActivationAction.resolve(
                isReopenEvent: true,
                hasDockTile: true,
                isPointerInDockArea: false
            ) == .openSettings
        )
    }

    @Test func coldLaunchDoesNothing() {
        #expect(
            DockActivationAction.resolve(
                isReopenEvent: false,
                hasDockTile: true,
                isPointerInDockArea: true
            ) == .none
        )
        #expect(
            DockActivationAction.resolve(
                isReopenEvent: false,
                hasDockTile: false,
                isPointerInDockArea: true
            ) == .none
        )
    }
}
