import Foundation

enum DockIconBackgroundResolver {
    static func style(
        for preference: DockIconBackgroundPreference,
        theme: SystemIconAppearanceTheme,
        isDarkAppearance: Bool
    ) -> DockIconBackgroundStyle {
        switch preference {
        case .dark:
            return .dark
        case .light:
            return .light
        case .system:
            return systemStyle(theme: theme, isDarkAppearance: isDarkAppearance)
        }
    }

    private static func systemStyle(
        theme: SystemIconAppearanceTheme,
        isDarkAppearance: Bool
    ) -> DockIconBackgroundStyle {
        switch theme.style {
        case .dark:
            return .dark
        case .clear:
            return .clear
        case .tinted:
            // Tinted artwork needs the resolved system tint colour, which is not
            // available without private API, so tinted keeps the light tile.
            return .light
        case .defaultStyle:
            switch theme.appearance {
            case .light:
                return .light
            case .dark:
                return .dark
            case .automatic:
                return isDarkAppearance ? .dark : .light
            }
        }
    }
}
