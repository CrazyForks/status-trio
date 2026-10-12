import XCTest
@testable import StatusTrioCore

@MainActor
final class LowPowerModeControllerTests: XCTestCase {
    func testDoesNotContactTheHelperWhileDisabled() async {
        let client = FakeLowPowerModeClient(reads: true)
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)

        controller.refresh()
        controller.setLowPowerMode(true)
        await settle()

        XCTAssertEqual(client.readCallCount, 0)
        XCTAssertEqual(client.setCallCount, 0)
        XCTAssertFalse(controller.isLowPowerMode)
    }

    func testEnablingAllowsRefreshToReadThroughTheHelper() async {
        let client = FakeLowPowerModeClient(reads: true)
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)

        controller.setEnabled(true)
        controller.refresh()
        await settle()

        XCTAssertEqual(client.readCallCount, 1)
        XCTAssertTrue(controller.isLowPowerMode)
    }

    func testSetPublishesTheObservedValue() async {
        let client = FakeLowPowerModeClient(reads: false)
        client.setResult = true
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)
        controller.setEnabled(true)

        controller.setLowPowerMode(true)
        await settle()

        XCTAssertEqual(client.setCallCount, 1)
        XCTAssertEqual(client.lastSetValue, true)
        XCTAssertTrue(controller.isLowPowerMode)
        XCTAssertFalse(controller.isApplying)
        XCTAssertNil(controller.lastError)
    }

    func testSetRevertsOptimisticValueOnFailure() async {
        let client = FakeLowPowerModeClient(reads: false)
        client.setError = FakeError.denied
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)
        controller.setEnabled(true)

        controller.setLowPowerMode(true)
        await settle()

        XCTAssertFalse(controller.isLowPowerMode)
        XCTAssertNotNil(controller.lastError)
        XCTAssertFalse(controller.isApplying)
    }

    func testSystemReadSeedsTheDisplayedValueWhenIdle() {
        let controller = LowPowerModeController(
            client: FakeLowPowerModeClient(reads: false),
            initialIsLowPowerMode: false
        )

        controller.updateFromSystemRead(true)

        XCTAssertTrue(controller.isLowPowerMode)
    }

    func testHelperReadingWinsOverTheLaggingProcessInfoSeed() async {
        // `ProcessInfo.isLowPowerModeEnabled` is cached per process and can lag
        // the real state; once the helper has answered, its value must stand or
        // the toggle would send the wrong direction.
        let client = FakeLowPowerModeClient(reads: true)
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)
        controller.setEnabled(true)
        controller.refresh()
        await settle()
        XCTAssertTrue(controller.isLowPowerMode)

        controller.updateFromSystemRead(false)

        XCTAssertTrue(controller.isLowPowerMode)
    }

    func testDisablingClearsErrorAndStopsContact() async {
        let client = FakeLowPowerModeClient(reads: false)
        client.setError = FakeError.denied
        let controller = LowPowerModeController(client: client, initialIsLowPowerMode: false)
        controller.setEnabled(true)
        controller.setLowPowerMode(true)
        await settle()
        XCTAssertNotNil(controller.lastError)

        controller.setEnabled(false)
        controller.refresh()
        await settle()

        XCTAssertNil(controller.lastError)
        XCTAssertEqual(client.readCallCount, 0)
    }

    private func settle() async {
        // Let the controller's detached Task run to completion.
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    private enum FakeError: Error {
        case denied
    }
}

private final class FakeLowPowerModeClient: LowPowerModeClienting, @unchecked Sendable {
    var reads: Bool
    var setResult: Bool?
    var setError: Error?
    private(set) var readCallCount = 0
    private(set) var setCallCount = 0
    private(set) var lastSetValue: Bool?

    init(reads: Bool) {
        self.reads = reads
    }

    func readLowPowerMode() async throws -> Bool {
        readCallCount += 1
        return reads
    }

    func setLowPowerMode(_ enabled: Bool) async throws -> Bool {
        setCallCount += 1
        lastSetValue = enabled
        if let setError {
            throw setError
        }
        return setResult ?? enabled
    }
}
