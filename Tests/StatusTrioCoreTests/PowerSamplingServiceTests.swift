import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class PowerSamplingServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_555_974)

    private func makeService(
        reader: @escaping @Sendable () -> SystemPowerSample?
    ) -> PowerSamplingService {
        PowerSamplingService(reader: reader)
    }

    func testDemandSelectsTheCadenceAndOnlyTheLastDemandStopsIt() {
        let service = makeService { nil }

        XCTAssertFalse(service.isRunning)

        service.begin(.icon)
        XCTAssertTrue(service.isRunning)
        XCTAssertEqual(service.currentInterval, .seconds(5))
        XCTAssertFalse(service.wantsDetailedCadence)

        service.begin(.panel)
        XCTAssertEqual(service.currentInterval, .seconds(2))
        XCTAssertTrue(service.wantsDetailedCadence)

        // Closing the panel must not cut the icon's sample.
        service.end(.panel)
        XCTAssertTrue(service.isRunning)
        XCTAssertEqual(service.currentInterval, .seconds(5))

        service.end(.icon)
        XCTAssertFalse(service.isRunning)
        XCTAssertTrue(service.demands.isEmpty)
    }

    func testDetailsDemandAlsoUsesTheDetailedCadence() {
        let service = makeService { nil }
        service.begin(.icon)
        service.begin(.details)
        XCTAssertEqual(service.currentInterval, .seconds(2))
        service.end(.details)
        service.end(.icon)
    }

    func testRepeatedBeginIsIdempotent() {
        let service = makeService { nil }
        service.begin(.icon)
        service.begin(.icon)
        XCTAssertEqual(service.demands, [.icon])
        service.end(.icon)
        XCTAssertFalse(service.isRunning, "One end must release a demand registered twice")
    }

    func testASuccessfulReadPublishesTheSample() async {
        let sample = SystemPowerSample(watts: 17.5, readAt: now)
        let service = makeService { sample }

        service.begin(.icon)
        await waitForSample(service)
        XCTAssertEqual(service.systemPower, sample)

        service.end(.icon)
        XCTAssertNil(service.systemPower, "A stopped sampler must not leave a stale value behind")
    }

    func testAnUnreadableSampleIsNeverPublishedAsZero() async {
        let service = makeService { nil }
        service.begin(.icon)
        // Give the background read a chance to land before asserting.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(service.systemPower)
        service.end(.icon)
    }

    func testStopAllReleasesEveryDemand() {
        let service = makeService { nil }
        service.begin(.icon)
        service.begin(.panel)
        service.begin(.details)
        service.stopAll()
        XCTAssertFalse(service.isRunning)
        XCTAssertTrue(service.demands.isEmpty)
    }

    private func waitForSample(_ service: PowerSamplingService) async {
        for _ in 0..<100 {
            if service.systemPower != nil { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}
