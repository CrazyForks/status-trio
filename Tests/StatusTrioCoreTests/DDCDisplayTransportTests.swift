import XCTest
@testable import StatusTrioCore

final class DDCDisplayTransportTests: XCTestCase {
    func testUniqueMatchRequiresOneExactUID() {
        XCTAssertNil(DDCDisplayTransport.uniqueMatch(uid: "", services: [(edidUUID: "A", handle: 1)]))
        XCTAssertNil(DDCDisplayTransport.uniqueMatch(uid: "missing", services: [(edidUUID: "A", handle: 1)]))
        XCTAssertNil(DDCDisplayTransport.uniqueMatch(uid: "A", services: [(edidUUID: "A", handle: 1), (edidUUID: "A", handle: 2)]))
        XCTAssertEqual(DDCDisplayTransport.uniqueMatch(uid: "A", services: [(edidUUID: "B", handle: 1), (edidUUID: "A", handle: 2)])?.handle, 2)
        XCTAssertNil(DDCDisplayTransport.uniqueMatch(uid: "Monitor A", services: [(edidUUID: "Monitor A renamed", handle: 1)]))
    }

    func testDuplicateIdentityIsRejectedBeforeOpeningAnyService() {
        var openAttempts: [Int] = []

        let result = DDCDisplayTransport.uniqueOpenedMatch(
            uid: "A",
            services: [(edidUUID: "A", handle: 1), (edidUUID: "A", handle: 2)]
        ) { handle in
            openAttempts.append(handle)
            return handle == 1 ? "opened" : nil
        }

        XCTAssertNil(result)
        XCTAssertTrue(openAttempts.isEmpty)
    }

    func testFramebufferUIDAssociatesOnlyWithOneExternalService() {
        var opened: [Int] = []
        let matched = DDCDisplayTransport.uniqueFramebufferServiceMatch(
            uid: "XV272U-UUID",
            framebufferUUIDs: ["XV272U-UUID"],
            externalServices: [20]
        ) { service in
            opened.append(service)
            return "service-\(service)"
        }
        XCTAssertEqual(matched?.edidUUID, "XV272U-UUID")
        XCTAssertEqual(matched?.handle, "service-20")
        XCTAssertEqual(opened, [20])
    }

    func testFramebufferServiceAssociationFailsClosedWhenAmbiguous() {
        var openAttempts = 0
        let open: (Int) -> String? = { _ in openAttempts += 1; return "opened" }

        XCTAssertNil(DDCDisplayTransport.uniqueFramebufferServiceMatch(
            uid: "XV272U-UUID",
            framebufferUUIDs: ["XV272U-UUID", "OTHER"],
            externalServices: [20],
            open: open
        ))
        XCTAssertNil(DDCDisplayTransport.uniqueFramebufferServiceMatch(
            uid: "XV272U-UUID",
            framebufferUUIDs: ["XV272U-UUID", "XV272U-UUID"],
            externalServices: [20],
            open: open
        ))
        XCTAssertNil(DDCDisplayTransport.uniqueFramebufferServiceMatch(
            uid: "XV272U-UUID",
            framebufferUUIDs: ["XV272U-UUID"],
            externalServices: [20, 21],
            open: open
        ))
        XCTAssertNil(DDCDisplayTransport.uniqueFramebufferServiceMatch(
            uid: "OTHER",
            framebufferUUIDs: ["XV272U-UUID"],
            externalServices: [20],
            open: open
        ))
        XCTAssertEqual(openAttempts, 0)
    }

    func testInvalidReplyIsRejectedByDecoder() {
        let transport = InvalidReplyTransport()
        XCTAssertNil(transport.read(DDCDisplayTarget(uid: "display", service: nil)))
    }
}

private final class InvalidReplyTransport: DDCVolumeTransport {
    func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReply? { DDCVolumeReply.decode([0x62]) }
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool { false }
}
