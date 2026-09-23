import Darwin
import XCTest
@testable import StatusTrioCore

/// The rules behind the VPN row: which interfaces count, when a proxy is
/// reported, and what the resolver makes of a reading. Every case runs on
/// synthetic input — the probe's own I/O is covered by `VPNMonitorTests`.
final class VPNStatusTests: XCTestCase {
    // MARK: - Resolver

    func testTunnelInterfaceAloneReadsAsATunnel() {
        let status = VPNStatusResolver.resolve(
            VPNProbeReading(tunnelInterfaces: ["utun4"])
        )

        XCTAssertTrue(status.isTunnelConnected)
        XCTAssertTrue(status.isActive)
        XCTAssertNil(status.serviceName)
        XCTAssertNil(status.proxy)
    }

    func testConnectedServiceSuppliesTheName() {
        let status = VPNStatusResolver.resolve(
            VPNProbeReading(
                services: [
                    VPNServiceReading(name: "Office", isConnected: false),
                    VPNServiceReading(name: "Home", isConnected: true)
                ]
            )
        )

        XCTAssertEqual(status.serviceName, "Home")
        XCTAssertTrue(status.isTunnelConnected)
    }

    func testProxyAloneIsActiveButNotATunnel() {
        let status = VPNStatusResolver.resolve(
            VPNProbeReading(
                proxy: VPNProxyStatus(kind: .http, host: "127.0.0.1", port: 10808)
            )
        )

        XCTAssertFalse(status.isTunnelConnected)
        XCTAssertTrue(status.isActive)
        XCTAssertEqual(status.proxy?.endpoint, "127.0.0.1:10808")
    }

    func testEmptyReadingIsInactive() {
        let status = VPNStatusResolver.resolve(.empty)

        XCTAssertFalse(status.isActive)
        XCTAssertFalse(status.isTunnelConnected)
        XCTAssertEqual(status, .placeholder)
    }

    /// The value feeds `VPNStatus: Equatable`, which is what drops a repeat
    /// notification, so the interface list has to come out in a stable order.
    func testTunnelInterfacesAreSorted() {
        let status = VPNStatusResolver.resolve(
            VPNProbeReading(tunnelInterfaces: ["utun7", "utun2", "utun5"])
        )

        XCTAssertEqual(status.tunnelInterfaces, ["utun2", "utun5", "utun7"])
    }

    func testSameInterfacesInADifferentOrderResolveEqual() {
        let first = VPNStatusResolver.resolve(
            VPNProbeReading(tunnelInterfaces: ["utun5", "utun2"])
        )
        let second = VPNStatusResolver.resolve(
            VPNProbeReading(tunnelInterfaces: ["utun2", "utun5"])
        )

        XCTAssertEqual(first, second)
    }

    // MARK: - Tunnel interface classification

    func testTunnelNamePrefixes() {
        for name in ["utun0", "utun4", "ppp0", "ipsec1", "tap2", "tun9"] {
            XCTAssertTrue(TunnelInterfaceClassifier.isTunnelInterface(name), name)
        }

        for name in ["en0", "en7", "lo0", "bridge0", "awdl0", "llw0"] {
            XCTAssertFalse(TunnelInterfaceClassifier.isTunnelInterface(name), name)
        }
    }

    /// The rule that keeps macOS's own tunnels out of the result. Measured on
    /// macOS 26.6.1: `utun0`–`utun3` (Back to My Mac, Continuity) are all
    /// `UP,RUNNING` with an empty IPv4 address list.
    func testUpTunnelWithoutAnAddressIsNotActive() {
        XCTAssertFalse(
            TunnelInterfaceClassifier.isActiveTunnel(
                flags: UInt32(IFF_UP),
                ipv4Addresses: []
            )
        )
    }

    func testDownTunnelWithAnAddressIsNotActive() {
        XCTAssertFalse(
            TunnelInterfaceClassifier.isActiveTunnel(
                flags: 0,
                ipv4Addresses: ["10.8.0.2"]
            )
        )
    }

    func testLinkLocalAddressDoesNotCountAsRoutable() {
        XCTAssertFalse(
            TunnelInterfaceClassifier.isActiveTunnel(
                flags: UInt32(IFF_UP),
                ipv4Addresses: ["169.254.10.1"]
            )
        )
    }

    func testUpTunnelWithARoutableAddressIsActive() {
        XCTAssertTrue(
            TunnelInterfaceClassifier.isActiveTunnel(
                flags: UInt32(IFF_UP),
                ipv4Addresses: ["10.8.0.2"]
            )
        )
    }

    // MARK: - Proxy parsing

    func testFixedEndpointWinsOverAnAutomaticConfiguration() {
        let proxy = SystemVPNProxyReader.proxy(from: [
            "HTTPEnable": 1,
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": 10808,
            "ProxyAutoConfigEnable": 1,
            "ProxyAutoConfigURLString": "http://example.invalid/proxy.pac"
        ])

        XCTAssertEqual(proxy?.kind, .http)
        XCTAssertEqual(proxy?.endpoint, "127.0.0.1:10808")
    }

    func testHTTPIsPreferredOverHTTPSAndSOCKS() {
        let proxy = SystemVPNProxyReader.proxy(from: [
            "SOCKSEnable": 1,
            "SOCKSProxy": "10.0.0.3",
            "SOCKSPort": 3,
            "HTTPSEnable": 1,
            "HTTPSProxy": "10.0.0.2",
            "HTTPSPort": 2,
            "HTTPEnable": 1,
            "HTTPProxy": "10.0.0.1",
            "HTTPPort": 1
        ])

        XCTAssertEqual(proxy?.kind, .http)
        XCTAssertEqual(proxy?.endpoint, "10.0.0.1:1")
    }

    func testSOCKSIsReportedWhenItIsTheOnlyOneEnabled() {
        let proxy = SystemVPNProxyReader.proxy(from: [
            "SOCKSEnable": 1,
            "SOCKSProxy": "127.0.0.1",
            "SOCKSPort": 7891
        ])

        XCTAssertEqual(proxy?.kind, .socks)
        XCTAssertEqual(proxy?.endpoint, "127.0.0.1:7891")
    }

    /// A PAC script is not an endpoint the row can print, so it keeps a `nil`
    /// endpoint and the presentation names its kind instead.
    func testPACOnlyReadsAsAutomaticConfiguration() {
        let proxy = SystemVPNProxyReader.proxy(from: [
            "ProxyAutoConfigEnable": 1,
            "ProxyAutoConfigURLString": "http://example.invalid/proxy.pac"
        ])

        XCTAssertEqual(proxy?.kind, .automaticConfiguration)
        XCTAssertNil(proxy?.endpoint)
    }

    func testDisabledProxyIsNotReported() {
        XCTAssertNil(
            SystemVPNProxyReader.proxy(from: [
                "HTTPEnable": 0,
                "HTTPProxy": "127.0.0.1",
                "HTTPPort": 10808
            ])
        )
    }

    func testEmptyDictionaryIsNotReported() {
        XCTAssertNil(SystemVPNProxyReader.proxy(from: [:]))
    }

    func testHostWithoutAPortKeepsTheHost() {
        let proxy = SystemVPNProxyReader.proxy(from: [
            "SOCKSEnable": 1,
            "SOCKSProxy": "10.0.0.1"
        ])

        XCTAssertEqual(proxy?.endpoint, "10.0.0.1")
    }

    func testEmptyHostHasNoEndpoint() {
        let proxy = SystemVPNProxyReader.proxy(from: [
            "HTTPEnable": 1,
            "HTTPProxy": "",
            "HTTPPort": 8080
        ])

        XCTAssertEqual(proxy?.kind, .http)
        XCTAssertNil(proxy?.endpoint)
    }
}
