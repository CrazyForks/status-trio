import XCTest
@testable import StatusTrioCore

final class TelemetryLanguageTagTests: XCTestCase {
    func testNormalizesKnownSystemLanguageTags() {
        let cases: [([String], String)] = [
            (["th", "th-TH"], "th"),
            (["vi-VN"], "vi"),
            (["sr-Latn", "sr-Latn-RS"], "sr-Latn"),
            (["zh-TW", "zh-HK"], "zh-Hant"),
            (["zh-CN"], "zh-Hans"),
            (["pt-BR"], "pt-BR"),
            (["pt-PT", "pt"], "pt"),
            (["en-GB"], "en"),
            (["de-DE"], "de")
        ]

        for (preferred, expected) in cases {
            XCTAssertEqual(TelemetryLanguageTag.osLanguageTag(preferred: preferred), expected, "\(preferred)")
        }
    }

    func testRejectsMalformedAndOversizedLanguageTags() {
        let invalid = ["", "-en", "en-", "en-garbage!", "en-foo_bar", "中文", "en-\(String(repeating: "a", count: 17))"]

        for raw in invalid {
            XCTAssertNil(TelemetryLanguageTag.osLanguageTag(preferred: [raw]), "\(raw)")
        }
    }

    func testSkipsInvalidPreferenceAndUsesNextValidLanguage() {
        XCTAssertEqual(
            TelemetryLanguageTag.osLanguageTag(preferred: ["en-garbage!", "fr-FR"]),
            "fr"
        )
    }
}
