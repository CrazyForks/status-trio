import XCTest
@testable import StatusTrioCore

@MainActor
final class AppleDeviceDiscoveryControllerTests: XCTestCase {
    func testDiscoveryRequiresEnabledPickerClaimAndNeverReadsBattery() async {
        let reader = ControlledMobileBatteryReader()
        let controller = AppleDeviceDiscoveryController(reader: reader)
        controller.request("picker")
        await settle()
        let countBeforeEnable = await reader.discoveryCount
        XCTAssertEqual(countBeforeEnable, 0)

        controller.setEnabled(true)
        await settle()
        let discoveryCount = await reader.discoveryCount
        let readCount = await reader.readCount
        XCTAssertEqual(discoveryCount, 1)
        XCTAssertEqual(readCount, 0)
        await reader.completeDiscovery(0, with: [candidate(id: "phone-1", model: "iPhone18,1")])
        await waitUntil { controller.candidates.count == 1 && !controller.isDiscovering }

        controller.release("picker")
        let readsAfterRelease = await reader.readCount
        XCTAssertEqual(readsAfterRelease, 0)
        controller.stop()
    }

    func testDismissalRejectsLateDiscoveryAndKeepsSavedSelectionExternal() async {
        let reader = ControlledMobileBatteryReader()
        let controller = AppleDeviceDiscoveryController(reader: reader)
        controller.setEnabled(true)
        controller.request("picker")
        await waitUntil { await reader.discoveryCount == 1 }
        controller.release("picker")
        await reader.completeDiscovery(0, with: [candidate(id: "phone-1", model: "iPhone18,1")])
        await settle()
        XCTAssertTrue(controller.candidates.isEmpty)
        controller.stop()
    }

    private func candidate(id: String, model: String) -> AppleDeviceCandidate {
        AppleDeviceCandidate(
            id: .trustedDevice(id), name: "Device", model: model,
            transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel
        )
    }

    private func settle() async { for _ in 0..<8 { await Task.yield() } }

    private func waitUntil(_ condition: @escaping () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
        let satisfied = await condition()
        XCTAssertTrue(satisfied)
    }
}
