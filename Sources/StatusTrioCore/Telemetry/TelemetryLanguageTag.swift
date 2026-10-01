import Foundation

/// Validates the server's bounded language-tag grammar before normalization.
enum TelemetryLanguageTag {
    static func osLanguageTag(preferred: [String]) -> String? {
        for value in preferred {
            if let normalized = normalize(value) { return normalized }
        }
        return nil
    }

    static func normalize(_ rawValue: String?) -> String? {
        guard let rawValue, isValid(rawValue) else { return nil }
        let parts = rawValue.split(separator: "-").map(String.init)
        let language = parts[0].lowercased()
        let subtags = parts.dropFirst().map { $0.lowercased() }
        if language == "zh" {
            if subtags.contains("hant") || subtags.contains("tw") || subtags.contains("hk") || subtags.contains("mo") { return "zh-Hant" }
            return "zh-Hans"
        }
        if language == "pt" { return subtags.contains("br") ? "pt-BR" : "pt" }
        if language == "sr", subtags.contains("latn") { return "sr-Latn" }
        return language
    }

    private static func isValid(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 16 else { return false }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard let primary = parts.first, (2...3).contains(primary.utf8.count), primary.utf8.allSatisfy(isASCIIAlpha) else { return false }
        return parts.dropFirst().allSatisfy { part in
            (2...8).contains(part.utf8.count) && part.utf8.allSatisfy(isASCIIAlphaNumeric)
        }
    }

    private static func isASCIIAlpha(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte)
    }
    private static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        isASCIIAlpha(byte) || (48...57).contains(byte)
    }
}
