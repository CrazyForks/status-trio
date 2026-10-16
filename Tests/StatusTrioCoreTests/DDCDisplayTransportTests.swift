import XCTest
@testable import StatusTrioCore

final class DDCDisplayTransportTests: XCTestCase {
    func testBranchTokenComesFromTheNumberedDispextPrefix() {
        XCTAssertEqual(DDCDisplayTransport.branchToken(fromIONameMatched: "dispext0,t603x"), "dispext0")
        XCTAssertEqual(DDCDisplayTransport.branchToken(fromIONameMatched: "dispext12,t603x"), "dispext12")
        XCTAssertEqual(DDCDisplayTransport.branchToken(fromIONameMatched: "dispext3"), "dispext3")
        XCTAssertNil(DDCDisplayTransport.branchToken(fromIONameMatched: "disp0,t603x"))
        XCTAssertNil(DDCDisplayTransport.branchToken(fromIONameMatched: "dispext,t603x"))
        XCTAssertNil(DDCDisplayTransport.branchToken(fromIONameMatched: "dispextX,t603x"))
        XCTAssertNil(DDCDisplayTransport.branchToken(fromIONameMatched: nil))
    }

    func testServiceBranchTokenComesFromTheDcpavServiceEpicAncestor() {
        // Real macOS 27 sample: the external proxy sits under
        // `dispext0:dcpav-service-epic:0` inside the `dcpext0` branch.
        let realSample = [
            "dispext0:dcpav-service-epic:0",
            "AFKEPInterfaceServiceKextV2",
            "AFKDCPEXT0Endpoint9",
            "DCPEXT0Endpoint9",
            "RTBuddy(DCPEXT0)",
            "AppleH15IO"
        ]
        XCTAssertEqual(DDCDisplayTransport.branchToken(fromServiceAncestorNames: realSample), "dispext0")

        let secondBranch = ["dispext2:dcpav-service-epic:0", "RTBuddy(DCPEXT2)", "AppleH15IO"]
        XCTAssertEqual(DDCDisplayTransport.branchToken(fromServiceAncestorNames: secondBranch), "dispext2")

        // A controller endpoint is not the DDC service endpoint.
        XCTAssertNil(DDCDisplayTransport.branchToken(fromServiceAncestorNames: ["dispext0:dcpav-controller-epic:0"]))
        // The internal display's audio service must never yield an external token.
        XCTAssertNil(DDCDisplayTransport.branchToken(fromServiceAncestorNames: ["disp0:dcpav-service-epic:0"]))
        XCTAssertNil(DDCDisplayTransport.branchToken(fromServiceAncestorNames: ["AFKDCPEXT0Endpoint9", "AppleH15IO"]))
        XCTAssertNil(DDCDisplayTransport.branchToken(fromServiceAncestorNames: []))
    }

    func testResolvedTargetOpensOnlyTheMatchedService() {
        var opened: [Int] = []
        let resolution = DDCTargetResolver.resolve(
            outputUID: "XV272U-UUID",
            framebuffers: [DDCFramebufferSnapshot(entryID: 1, branchName: "dispext0", edidUUID: "XV272U-UUID")],
            services: [DDCServiceSnapshot(entryID: 20, branchName: "dispext0", location: "External")]
        )
        let result = DDCTargetResolver.openResolvedTarget(
            resolution,
            services: [(entryID: 20, handle: "service-20")]
        ) { handle in
            opened.append(20)
            return handle
        }

        XCTAssertEqual(result?.serviceEntryID, 20)
        XCTAssertEqual(result?.opened, "service-20")
        XCTAssertEqual(opened, [20])
    }

    func testNoServiceIsOpenedWhenTheTopologyIsAmbiguous() {
        var openAttempts = 0
        let open: (Int) -> Int? = { _ in openAttempts += 1; return 0 }
        let ambiguous = DDCTargetResolver.resolve(
            outputUID: "XV272U-UUID",
            framebuffers: [
                DDCFramebufferSnapshot(entryID: 1, branchName: "dispext0", edidUUID: "XV272U-UUID"),
                DDCFramebufferSnapshot(entryID: 2, branchName: "dispext1", edidUUID: "XV272U-UUID")
            ],
            services: [
                DDCServiceSnapshot(entryID: 20, branchName: "dispext0", location: "External"),
                DDCServiceSnapshot(entryID: 21, branchName: "dispext1", location: "External")
            ]
        )
        XCTAssertNil(DDCTargetResolver.openResolvedTarget(
            ambiguous,
            services: [(entryID: 20, handle: 20), (entryID: 21, handle: 21)],
            open: open
        ))

        let unavailable = DDCTargetResolver.resolve(
            outputUID: "OTHER",
            framebuffers: [DDCFramebufferSnapshot(entryID: 1, branchName: "dispext0", edidUUID: "XV272U-UUID")],
            services: [DDCServiceSnapshot(entryID: 20, branchName: "dispext0", location: "External")]
        )
        XCTAssertNil(DDCTargetResolver.openResolvedTarget(
            unavailable,
            services: [(entryID: 20, handle: 20)],
            open: open
        ))

        let failedOpen = DDCTargetResolver.resolve(
            outputUID: "XV272U-UUID",
            framebuffers: [DDCFramebufferSnapshot(entryID: 1, branchName: "dispext0", edidUUID: "XV272U-UUID")],
            services: [DDCServiceSnapshot(entryID: 20, branchName: "dispext0", location: "External")]
        )
        XCTAssertNil(DDCTargetResolver.openResolvedTarget(
            failedOpen,
            services: [(entryID: 20, handle: 20)],
            open: { (_: Int) -> Int? in nil }
        ))

        XCTAssertEqual(openAttempts, 0)
    }

    func testOnlyConnectedExternalFramebufferEntriesAreRelevant() {
        XCTAssertTrue(DDCDisplayTransport.isConnectedExternalFramebuffer(
            ioNameMatched: "dispext0,t603x",
            displayWidth: 2560,
            displayHeight: 1440
        ))
        XCTAssertFalse(DDCDisplayTransport.isConnectedExternalFramebuffer(
            ioNameMatched: "dispext1,t603x",
            displayWidth: nil,
            displayHeight: nil
        ))
        XCTAssertFalse(DDCDisplayTransport.isConnectedExternalFramebuffer(
            ioNameMatched: "disp0,t603x",
            displayWidth: 3456,
            displayHeight: 2234
        ))
        XCTAssertFalse(DDCDisplayTransport.isConnectedExternalFramebuffer(
            ioNameMatched: "dispext2,t603x",
            displayWidth: 0,
            displayHeight: 1440
        ))
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
