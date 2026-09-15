import Testing
@testable import StatusTrioCore

struct DockIconBackgroundStyleTests {
    @Test func exposesDarkAndLightStyles() {
        #expect(DockIconBackgroundStyle.allCases == [.dark, .light])
    }
}
