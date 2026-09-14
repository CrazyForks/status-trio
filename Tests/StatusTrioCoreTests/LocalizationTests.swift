import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class LocalizationTests: XCTestCase {
    func testLanguageChangeRefreshesAfterResolvedLanguageIsUpdated() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        var observedLanguages: [AppLanguage] = []
        let cancellable = localization.objectWillChange.sink {
            observedLanguages.append(localization.resolvedLanguage)
        }
        defer { cancellable.cancel() }

        localization.setPreference(.language(.german))

        XCTAssertEqual(observedLanguages.last, .german)
    }

    func testManualLanguagePersistsAndResolves() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.german))

        XCTAssertEqual(localization.resolvedLanguage, .german)
        XCTAssertEqual(
            Localization(defaults: suite.defaults, preferredLanguages: ["en"]).resolvedLanguage,
            .german
        )
    }

    func testSystemLanguageFollowsInjectedPreferences() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(
            defaults: suite.defaults,
            preferredLanguages: ["zh-TW", "en-US"]
        )

        XCTAssertEqual(localization.preference, .system)
        XCTAssertEqual(localization.resolvedLanguage, .traditionalChinese)
    }

    func testInvalidStoredLanguageFallsBackToSystem() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set("not-a-language", forKey: Localization.defaultsKey)

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["ja-JP"])

        XCTAssertEqual(localization.preference, .system)
        XCTAssertEqual(localization.resolvedLanguage, .japanese)
    }

    func testEveryLanguageHasEveryNonEmptyKey() throws {
        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))

            for key in LocalizationKey.allCases {
                let value = bundle.localizedString(forKey: key.rawValue, value: nil, table: nil)
                XCTAssertFalse(value.isEmpty, "\(language.rawValue) missing \(key.rawValue)")
                XCTAssertNotEqual(value, key.rawValue, "\(language.rawValue) missing \(key.rawValue)")
            }
        }
    }

    func testEveryParameterizedKeyUsesMatchingPlaceholders() throws {
        let expectedPlaceholderCounts: [LocalizationKey: Int] = [
            .menuVersion: 1,
            .settingsIconSizeAccessibilityValue: 1,
            .settingsAboutVersion: 1,
            .batteryTitle: 1,
            .batteryTimeToFullMinutes: 1,
            .batteryTimeToFullHours: 1,
            .batteryTimeToFullHoursMinutes: 2,
            .batteryAccessibilityValue: 1,
            .commonParenthetical: 2,
            .commonLabelValue: 2,
            .wifiValueBars: 1,
            .wifiAccessibilityWithSSID: 2,
            .volumeTitle: 1,
            .volumeValue: 2,
            .volumeOutputSwitchTo: 1,
            .accessibilityStatus: 3,
            .accessibilityBattery: 1,
            .accessibilityVolume: 1
        ]

        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))

            for (key, expectedCount) in expectedPlaceholderCounts {
                let value = bundle.localizedString(forKey: key.rawValue, value: nil, table: nil)
                XCTAssertEqual(
                    placeholderCount(in: value),
                    expectedCount,
                    "\(language.rawValue) has wrong placeholders for \(key.rawValue)"
                )
            }
        }
    }

    func testFormattedStringUsesSelectedLanguageLocale() {
        let suite = makeSuite()
        defer { clear(suite) }
        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.simplifiedChinese))

        XCTAssertEqual(
            localization.format(.batteryTitle, 68),
            String(format: "电池 · %d%%", locale: Locale(identifier: "zh-Hans"), 68)
        )
    }

    func testGermanResourceOverridesEnglish() {
        let suite = makeSuite()
        defer { clear(suite) }
        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.german))

        XCTAssertEqual(localization.string(.menuSettings), "Einstellungen…")
    }

    func testOnlyChineseLanguagesUseTheExtendedAboutLinks() {
        let detected = Set(AppLanguage.allCases.filter(\.isChinese))

        XCTAssertEqual(detected, [.simplifiedChinese, .traditionalChinese])
    }

    func testAboutLinkLabelsStayCompact() throws {
        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))

            let repository = bundle.localizedString(
                forKey: LocalizationKey.settingsAboutRepository.rawValue,
                value: nil,
                table: nil
            )
            XCTAssertEqual(
                repository,
                "GitHub",
                "\(language.rawValue) repository label should stay short"
            )

            let project = bundle.localizedString(
                forKey: LocalizationKey.settingsAboutProject.rawValue,
                value: nil,
                table: nil
            )
            XCTAssertLessThanOrEqual(
                project.count,
                10,
                "\(language.rawValue) project label is too long: \(project)"
            )
        }
    }

    private func placeholderCount(in value: String) -> Int {
        let pattern = #"%(?:\d+\$)?[-+#0 ]*\d*(?:\.\d+)?[d@%]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.numberOfMatches(in: value, range: range)
            - value.components(separatedBy: "%%").count + 1
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.Localization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removePersistentDomain(forName: suite.name)
    }
}
