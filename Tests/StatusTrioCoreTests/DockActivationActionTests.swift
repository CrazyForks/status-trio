import Testing
@testable import StatusTrioCore

struct DockActivationActionTests {
    @Test func dockClickShowsThePopoverWhenTheAppOwnsADockTile() {
        #expect(
            DockActivationAction.resolve(isReopenEvent: true, hasDockTile: true) == .showPopover
        )
    }

    @Test func dockClickOpensSettingsWhenThereIsNoDockTile() {
        #expect(
            DockActivationAction.resolve(isReopenEvent: true, hasDockTile: false) == .openSettings
        )
    }

    @Test func coldLaunchDoesNothing() {
        #expect(
            DockActivationAction.resolve(isReopenEvent: false, hasDockTile: true) == .none
        )
        #expect(
            DockActivationAction.resolve(isReopenEvent: false, hasDockTile: false) == .none
        )
    }
}
