import XCTest
@testable import StatusTrioCore

@MainActor
final class WiFiConnectionFeedbackTests: XCTestCase {
    func testRefreshIsUnavailableWhileScanningOrJoiningAndReturnsAfterCompletion() {
        let network = WiFiNetworkIdentity(ssid: "Cafe", security: .wpa2Personal)
        let cases: [(WiFiListState, Bool)] = [
            (.idle, true), (.scanning, false), (.ready, true),
            (.resolvingCredentials, false), (.needsPassword, false),
            (.connecting(network), false), (.connectionFailed, true),
            (.connectionTimedOut, true), (.networkUnavailable, true),
            (.credentialAccessCancelled, true), (.credentialAccessDenied, true),
            (.credentialStoreLocked, true), (.credentialReadFailed, true),
            (.poweredOff, true), (.noInterface, true), (.permissionDenied, true),
            (.failed, true), (.enterpriseNetwork, true)
        ]

        for (state, allowsRefresh) in cases {
            XCTAssertEqual(state.allowsRefresh, allowsRefresh, "\(state)")
        }
    }

    func testJoiningFeedbackPreservesSSIDAndUsesLocalizedHiddenNetworkFallback() {
        let localization = makeLocalization()
        let named = WiFiNetworkIdentity(ssid: " Studio 100% ", security: .wpa2Personal)
        let hidden = WiFiNetworkIdentity(ssid: "", security: .open)

        XCTAssertEqual(
            WiFiNetworkPresentation.connectingMessage(for: named, localization: localization),
            "Joining  Studio 100% …"
        )
        XCTAssertEqual(
            WiFiNetworkPresentation.connectingMessage(for: hidden, localization: localization),
            "Joining Hidden Network…"
        )

        localization.setPreference(.language(.simplifiedChinese))
        XCTAssertEqual(
            WiFiNetworkPresentation.connectingMessage(for: named, localization: localization),
            "正在加入  Studio 100% …"
        )
        XCTAssertEqual(
            WiFiNetworkPresentation.connectingMessage(for: hidden, localization: localization),
            "正在加入 隐藏网络…"
        )
    }

    func testEveryLanguageNamesTheJoiningNetworkWithoutLeakingAFormatPlaceholder() {
        let localization = makeLocalization()
        let network = WiFiNetworkIdentity(ssid: "Cafe 100%", security: .wpa3Personal)
        for language in AppLanguage.allCases {
            localization.setPreference(.language(language))
            let message = WiFiNetworkPresentation.connectingMessage(for: network, localization: localization)
            XCTAssertTrue(message.contains("Cafe 100%"), language.rawValue)
            XCTAssertFalse(message.contains("%@"), language.rawValue)
            XCTAssertFalse(message.contains("wifi.connecting"), language.rawValue)
        }
    }

    private func makeLocalization() -> Localization {
        let suite = "StatusTrioCoreTests.WiFiConnectionFeedback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removeTestSuite(named: suite)
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }
}
