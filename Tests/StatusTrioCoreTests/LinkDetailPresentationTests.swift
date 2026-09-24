import XCTest
@testable import StatusTrioCore

@MainActor
final class LinkDetailPresentationTests: XCTestCase {
    func testWiredRowsAreTheSharedRowsAndNothingElse() {
        let details = PrimaryLinkDetails(
            interfaceName: "en5",
            ipv4Addresses: ["192.168.1.20"],
            ipv6Addresses: ["fe80::1"],
            router: "192.168.1.1",
            dnsServers: ["192.168.1.1", "1.1.1.1"]
        )

        let rows = LinkDetailPresentation.wiredRows(details)

        XCTAssertEqual(
            rows.map(\.label),
            [
                .networkDetailInterface,
                .networkDetailIPv4,
                .networkDetailIPv6,
                .networkDetailRouter,
                .networkDetailDNS
            ]
        )
        XCTAssertEqual(
            rows.map(\.value),
            ["en5", "192.168.1.20", "fe80::1", "192.168.1.1", "192.168.1.1, 1.1.1.1"]
        )
        // A cable has no radio, no association, and no negotiated rate, so none
        // of the Wi-Fi-only rows may appear here.
        XCTAssertFalse(rows.contains { row in
            row.label == .wifiDetailSSID
                || row.label == .wifiDetailRSSI
                || row.label == .wifiDetailSecurity
        })
    }

    func testEveryAddressRowOffersItselfToThePasteboard() {
        let rows = LinkDetailPresentation.wiredRows(
            PrimaryLinkDetails(
                interfaceName: "en5",
                ipv4Addresses: ["192.168.1.20"],
                ipv6Addresses: ["fe80::1"],
                router: "192.168.1.1",
                dnsServers: ["192.168.1.1"]
            )
        )

        let copyable = rows.filter(\.isCopyable).map(\.label)
        XCTAssertEqual(
            copyable,
            [.networkDetailIPv4, .networkDetailIPv6, .networkDetailRouter, .networkDetailDNS]
        )
        // The interface name is a label the user reads, not an address they paste.
        XCTAssertFalse(rows.first { $0.label == .networkDetailInterface }?.isCopyable ?? true)
    }

    func testAWiredLinkWithNoAddressStillReportsEveryRow() {
        let rows = LinkDetailPresentation.wiredRows(.unavailable)

        XCTAssertEqual(rows.count, 5)
        // Empty rather than absent, so the list draws its Unavailable placeholder
        // instead of dropping the row.
        XCTAssertTrue(rows.allSatisfy { $0.value == "" || $0.value == nil })
    }

    func testWirelessRowsAddTheSharedRowsOnlyWhenExpanded() {
        let localization = makeLocalization()
        let collapsed = LinkDetailPresentation.wirelessRows(
            .unavailable,
            expanded: false,
            localization: localization
        )
        let expanded = LinkDetailPresentation.wirelessRows(
            .unavailable,
            expanded: true,
            localization: localization
        )

        XCTAssertEqual(collapsed.count, 9)
        // Three more radio rows (noise, signal-to-noise, country code) and the
        // five shared rows.
        XCTAssertEqual(expanded.count, 17)
        XCTAssertEqual(
            Array(expanded.prefix(collapsed.count)).map(\.label),
            collapsed.map(\.label),
            "Expanding must append, never reorder the rows already on screen"
        )
        XCTAssertEqual(
            Array(expanded.suffix(5)).map(\.label),
            [
                .networkDetailInterface,
                .networkDetailIPv4,
                .networkDetailIPv6,
                .networkDetailRouter,
                .networkDetailDNS
            ]
        )
        XCTAssertFalse(collapsed.contains { $0.label == .networkDetailIPv4 })
    }

    private func makeLocalization() -> Localization {
        let name = "StatusTrioCoreTests.LinkDetailPresentation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }
}
