import Foundation

/// A small cache of out-of-band `Localization` instances used only by the
/// listening-mode interface preview.
///
/// The preview block can be shown in a language different from the rest of the
/// panel, so the synthetic rows are rendered through their own `Localization`
/// bound to the chosen code while everything around them keeps the user's real
/// language. Building one is cheap but not free — it registers a locale-change
/// observer and caches per-language bundles — so the instances are memoized per
/// code here and reused across refreshes instead of rebuilt on every render.
///
/// Each instance is given its own `UserDefaults` suite so that setting its
/// preference never writes the real `appLanguage` key the app reads: the override
/// is display-only and cannot leak into the user's actual language setting.
@MainActor
enum PreviewLocalization {
    private static var cache: [String: Localization] = [:]

    /// The `Localization` for `code`, or `nil` when the code is empty or not a
    /// language the app ships. `nil` means "no override" and the caller falls back
    /// to the panel's real localization.
    static func forCode(_ code: String) -> Localization? {
        guard !code.isEmpty, let language = AppLanguage(rawValue: code) else {
            return nil
        }
        if let cached = cache[code] {
            return cached
        }
        let suiteName = "StatusTrio.PreviewLoc.\(code)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return nil
        }
        let localization = Localization(
            defaults: defaults,
            preferredLanguages: [language.rawValue]
        )
        localization.setPreference(.language(language))
        cache[code] = localization
        return localization
    }
}
