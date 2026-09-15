import Testing
@testable import StatusTrioCore

struct DockIconBackgroundStyleTests {
    @Test func exposesDarkAndLightStyles() {
        #expect(DockIconBackgroundStyle.allCases == [.dark, .light, .clear])
    }

    @Test func exposesSystemDarkAndLightPreferences() {
        #expect(DockIconBackgroundPreference.allCases == [.system, .dark, .light])
    }
}
