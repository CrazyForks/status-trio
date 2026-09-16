import Foundation

struct SystemIconAppearanceTheme: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case defaultStyle
        case dark
        case clear
        case tinted
    }

    enum Appearance: Equatable, Sendable {
        case light
        case dark
        case automatic
    }

    let style: Style
    let appearance: Appearance

    static let `default` = SystemIconAppearanceTheme(style: .defaultStyle, appearance: .light)

    static func parse(_ rawValue: String?) -> SystemIconAppearanceTheme {
        guard let rawValue, !rawValue.isEmpty else { return .default }

        let style: Style
        if rawValue.hasPrefix("Tinted") {
            style = .tinted
        } else if rawValue.hasPrefix("Clear") {
            style = .clear
        } else if rawValue.hasPrefix("Regular") {
            style = .defaultStyle
        } else {
            return .default
        }

        let appearance: Appearance
        if rawValue.hasSuffix("Automatic") {
            appearance = .automatic
        } else if rawValue.hasSuffix("Dark") {
            appearance = .dark
        } else if rawValue.hasSuffix("Light") {
            appearance = .light
        } else {
            return .default
        }

        return SystemIconAppearanceTheme(style: style, appearance: appearance)
    }
}
