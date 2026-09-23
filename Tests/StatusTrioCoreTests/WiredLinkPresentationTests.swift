import XCTest
@testable import StatusTrioCore

@MainActor
final class WiredLinkPresentationTests: XCTestCase {
    func testThePortNameHeadsTheRowAndTheBsdNameFollows() {
        let details = PrimaryLinkDetails(
            interfaceName: "en9",
            interfaceDisplayName: "iPhone USB",
            ipv4Addresses: ["172.20.10.8"],
            ipv6Addresses: [],
            router: "172.20.10.1",
            dnsServers: ["172.20.10.1"]
        )
        let localization = makeLocalization()

        XCTAssertEqual(
            WiredLinkPresentation.title(details, localization: localization),
            "iPhone USB"
        )
        XCTAssertEqual(
            WiredLinkPresentation.subtitle(details, localization: localization),
            "en9"
        )
    }

    func testTheAddressNeverReachesTheRow() {
        // The row is drawn in a popover anyone standing behind the reader can
        // see. The address is the one value on this link that is nobody else's
        // business, so it is in the panel or nowhere.
        let details = PrimaryLinkDetails(
            interfaceName: "en9",
            interfaceDisplayName: "iPhone USB",
            ipv4Addresses: ["172.20.10.8"],
            ipv6Addresses: ["fe80::1851:778a:befb:b7ed"],
            router: "172.20.10.1",
            dnsServers: ["172.20.10.1"]
        )
        let localization = makeLocalization()

        let title = WiredLinkPresentation.title(details, localization: localization)
        let subtitle = WiredLinkPresentation.subtitle(details, localization: localization)

        var privateValues = details.ipv4Addresses + details.ipv6Addresses
        privateValues.append(contentsOf: details.dnsServers)
        if let router = details.router { privateValues.append(router) }
        XCTAssertFalse(privateValues.isEmpty)
        for value in privateValues {
            XCTAssertFalse(title.contains(value), "\(title) leaks \(value)")
            XCTAssertFalse(subtitle.contains(value), "\(subtitle) leaks \(value)")
        }
    }

    func testAnUnnamedPortFallsBackToTheGenericWiredLabel() {
        let details = PrimaryLinkDetails(
            interfaceName: "en0",
            ipv4Addresses: ["192.168.1.20"],
            ipv6Addresses: [],
            router: nil,
            dnsServers: []
        )
        let localization = makeLocalization()

        XCTAssertEqual(
            WiredLinkPresentation.title(details, localization: localization),
            localization.string(.ethernetTitle)
        )
        XCTAssertEqual(
            WiredLinkPresentation.subtitle(details, localization: localization),
            "en0"
        )
    }

    func testAnEmptyNameIsTreatedAsAbsent() {
        // An empty string is what a name-less interface looks like once it has
        // been through a dictionary. It must not become an empty heading.
        let details = PrimaryLinkDetails(
            interfaceName: "",
            interfaceDisplayName: "",
            ipv4Addresses: [],
            ipv6Addresses: [],
            router: nil,
            dnsServers: []
        )
        let localization = makeLocalization()

        XCTAssertEqual(
            WiredLinkPresentation.title(details, localization: localization),
            localization.string(.ethernetTitle)
        )
        XCTAssertEqual(
            WiredLinkPresentation.subtitle(details, localization: localization),
            localization.string(.ethernetSubtitleConnected)
        )
    }

    func testNothingReadYetShowsTheStateRatherThanBlankLines() {
        let localization = makeLocalization()

        for details in [nil, PrimaryLinkDetails.unavailable] {
            XCTAssertEqual(
                WiredLinkPresentation.title(details, localization: localization),
                localization.string(.ethernetTitle)
            )
            XCTAssertEqual(
                WiredLinkPresentation.subtitle(details, localization: localization),
                localization.string(.ethernetSubtitleConnected)
            )
        }
    }

    private func makeLocalization() -> Localization {
        let name = "StatusTrioCoreTests.WiredLinkPresentation.\(UUID().uuidString)"
        addTeardownBlock { TestUserDefaults.removeSuite(named: name) }
        let defaults = UserDefaults(suiteName: name) ?? .standard
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }
}
