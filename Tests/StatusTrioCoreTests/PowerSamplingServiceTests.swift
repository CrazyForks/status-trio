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

    func testEverySurfaceSharesOneCadenceAndOnlyTheLastDemandStopsIt() {
        let service = makeService { nil }

        XCTAssertFalse(service.isRunning)
        XCTAssertEqual(PowerSamplingService.interval, .seconds(2))

        service.begin(.icon)
        XCTAssertTrue(service.isRunning)

        service.begin(.panel)
        service.begin(.details)

        // Closing the panel and the details page must not cut the icon's sample.
        service.end(.panel)
        service.end(.details)
        XCTAssertTrue(service.isRunning)

        service.end(.icon)
        XCTAssertFalse(service.isRunning)
        XCTAssertTrue(service.demands.isEmpty)
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
