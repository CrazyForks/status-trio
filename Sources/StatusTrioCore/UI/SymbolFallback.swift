import AppKit

/// Resolves SF Symbols against the running macOS release.
///
/// Several symbols used by the app were introduced after Ventura. A missing
/// symbol is not a rendering failure on a newer host, so every call site that
/// can draw a dynamic or versioned glyph goes through this resolver.
enum SymbolFallback {
    static func name(_ preferred: String, _ fallbacks: String...) -> String {
        name(preferred, fallbacks)
    }

    static func name(_ preferred: String, _ fallbacks: [String]) -> String {
        name(preferred, fallbacks, isAvailable: isAvailable)
    }

    static func name(
        _ preferred: String,
        _ fallbacks: [String],
        isAvailable: (String) -> Bool
    ) -> String {
        let candidates = [preferred] + fallbacks
        return candidates.first(where: isAvailable) ?? candidates.last ?? "questionmark.circle"
    }

    static func isAvailable(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
