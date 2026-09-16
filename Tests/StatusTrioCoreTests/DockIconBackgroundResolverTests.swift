import Testing
@testable import StatusTrioCore

struct DockIconBackgroundResolverTests {
    @Test func explicitPreferencesIgnoreTheSystemStyle() {
        #expect(
            resolve(.dark, theme: .default, isDarkAppearance: false) == .dark
        )
        #expect(
            resolve(.light, theme: darkTheme, isDarkAppearance: true) == .light
        )
    }

    @Test func systemDefaultStyleFollowsTheAppearance() {
        #expect(resolve(.system, theme: .default, isDarkAppearance: false) == .light)
        #expect(
            resolve(
                .system,
                theme: SystemIconAppearanceTheme(style: .defaultStyle, appearance: .dark),
                isDarkAppearance: false
            ) == .dark
        )
    }

    @Test func systemClearStyleUsesTheClearBackground() {
        #expect(
            resolve(
                .system,
                theme: SystemIconAppearanceTheme(style: .clear, appearance: .dark),
                isDarkAppearance: false
            ) == .clear
        )
    }

    @Test func systemTintedStyleUsesTheLightBackgroundForNow() {
        #expect(
            resolve(
                .system,
                theme: SystemIconAppearanceTheme(style: .tinted, appearance: .dark),
                isDarkAppearance: true
            ) == .light
        )
    }

    @Test func systemAutomaticStyleFollowsTheCurrentAppearance() {
        let automatic = SystemIconAppearanceTheme(
            style: .defaultStyle,
            appearance: .automatic
        )

        #expect(resolve(.system, theme: automatic, isDarkAppearance: false) == .light)
        #expect(resolve(.system, theme: automatic, isDarkAppearance: true) == .dark)
    }

    private func resolve(
        _ preference: DockIconBackgroundPreference,
        theme: SystemIconAppearanceTheme,
        isDarkAppearance: Bool
    ) -> DockIconBackgroundStyle {
        DockIconBackgroundResolver.style(
            for: preference,
            theme: theme,
            isDarkAppearance: isDarkAppearance
        )
    }

    private var darkTheme: SystemIconAppearanceTheme {
        SystemIconAppearanceTheme(style: .defaultStyle, appearance: .dark)
    }
}
