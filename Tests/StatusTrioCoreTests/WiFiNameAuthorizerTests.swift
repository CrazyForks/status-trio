import CoreLocation
import XCTest
@testable import StatusTrioCore

@MainActor
final class WiFiNameAuthorizerTests: XCTestCase {
    func testUnansweredRequestDoesNotRepeatedlyRequestAuthorization() {
        let manager = StubWiFiLocationManager()
        let authorizer = CoreLocationWiFiNameAuthorizer(manager: manager)

        XCTAssertEqual(authorizer.requestAccess(), .requested)
        XCTAssertEqual(authorizer.requestAccess(), .openLocationSettings)

        XCTAssertEqual(manager.requestCount, 1)
    }

    func testDeniedAndRestrictedPermissionsOfferSettingsWithoutRequestingAgain() {
        for status: CLAuthorizationStatus in [.denied, .restricted] {
            let manager = StubWiFiLocationManager()
            manager.currentAuthorization = status
            let authorizer = CoreLocationWiFiNameAuthorizer(manager: manager)

            XCTAssertEqual(authorizer.requestAccess(), .openLocationSettings)
            XCTAssertEqual(manager.requestCount, 0)
        }
    }

    func testAlreadyAuthorizedPermissionDoesNotRequestOrOfferSettings() {
        let manager = StubWiFiLocationManager()
        manager.currentAuthorization = .authorizedAlways
        let authorizer = CoreLocationWiFiNameAuthorizer(manager: manager)

        XCTAssertEqual(authorizer.requestAccess(), .notNeeded)
        XCTAssertEqual(manager.requestCount, 0)
    }

    func testFreshAuthorizationTakesPrecedenceOverTheEarlierRequest() {
        let manager = StubWiFiLocationManager()
        let authorizer = CoreLocationWiFiNameAuthorizer(manager: manager)
        XCTAssertEqual(authorizer.requestAccess(), .requested)

        manager.currentAuthorization = .denied
        XCTAssertEqual(authorizer.requestAccess(), .openLocationSettings)

        manager.currentAuthorization = .authorizedAlways
        XCTAssertEqual(authorizer.requestAccess(), .notNeeded)
        XCTAssertEqual(manager.requestCount, 1)
    }
}

private final class StubWiFiLocationManager: CLLocationManager {
    var currentAuthorization: CLAuthorizationStatus = .notDetermined
    private(set) var requestCount = 0

    override var authorizationStatus: CLAuthorizationStatus {
        currentAuthorization
    }

    override func requestWhenInUseAuthorization() {
        requestCount += 1
    }
}
