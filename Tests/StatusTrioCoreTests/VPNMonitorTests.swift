import XCTest
@testable import StatusTrioCore

@MainActor
final class VPNMonitorTests: XCTestCase {
    func testStartPublishesTheCurrentReading() async {
        let reader = FakeVPNReader(reading: VPNProbeReading(tunnelInterfaces: ["utun4"]))
        let monitor = VPNMonitor(reader: reader, observer: FakeNetworkChangeObserver())

        let updated = expectation(description: "vpn status published")
        let task = Task {
            var iterator = monitor.updates.makeAsyncIterator()
            let status = await iterator.next()
            XCTAssertEqual(status?.tunnelInterfaces, ["utun4"])
            XCTAssertTrue(status?.isTunnelConnected == true)
            updated.fulfill()
        }

        monitor.start()
        await fulfillment(of: [updated], timeout: 1)

        task.cancel()
        monitor.stop()
    }

    func testObserverChangePublishesTheNewReading() async {
        let reader = FakeVPNReader(reading: .empty)
        let observer = FakeNetworkChangeObserver()
        let monitor = VPNMonitor(reader: reader, observer: observer)

        let updated = expectation(description: "proxy reading published")
        let task = Task {
            var iterator = monitor.updates.makeAsyncIterator()
            while let status = await iterator.next() {
                if status.proxy?.endpoint == "127.0.0.1:10808" {
                    updated.fulfill()
                    return
                }
            }
        }

        monitor.start()
        reader.reading = VPNProbeReading(
            proxy: VPNProxyStatus(kind: .http, host: "127.0.0.1", port: 10808)
        )
        observer.send()
        await fulfillment(of: [updated], timeout: 1)

        XCTAssertEqual(observer.startCount, 1)
        task.cancel()
        monitor.stop()
    }

    func testRecoverResubscribesAndReadsAgain() {
        let reader = FakeVPNReader(reading: .empty)
        let observer = FakeNetworkChangeObserver()
        let monitor = VPNMonitor(reader: reader, observer: observer)

        monitor.start()
        XCTAssertEqual(reader.readCount, 1)

        monitor.recover()
        XCTAssertEqual(observer.startCount, 2)
        XCTAssertEqual(observer.cancelCount, 1)
        XCTAssertEqual(reader.readCount, 2)

        monitor.stop()
    }

    func testRefreshBeforeStartDoesNothing() {
        let reader = FakeVPNReader(reading: .empty)
        let monitor = VPNMonitor(reader: reader, observer: FakeNetworkChangeObserver())

        monitor.refresh()

        XCTAssertEqual(reader.readCount, 0)
        monitor.stop()
    }

    func testStopFinishesTheStream() async {
        let monitor = VPNMonitor(
            reader: FakeVPNReader(reading: .empty),
            observer: FakeNetworkChangeObserver()
        )

        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        monitor.stop()

        let next = await iterator.next()
        XCTAssertNil(next)
    }

    /// A second `start()` must not subscribe twice: the store calls it once, but
    /// the guard is what keeps a future double call from doubling the reads.
    func testStartIsIdempotent() {
        let observer = FakeNetworkChangeObserver()
        let monitor = VPNMonitor(reader: FakeVPNReader(reading: .empty), observer: observer)

        monitor.start()
        monitor.start()

        XCTAssertEqual(observer.startCount, 1)
        monitor.stop()
    }
}

private final class FakeVPNReader: VPNReading {
    var reading: VPNProbeReading
    private(set) var readCount = 0

    init(reading: VPNProbeReading) {
        self.reading = reading
    }

    func read() -> VPNProbeReading {
        readCount += 1
        return reading
    }
}

private final class FakeNetworkChangeObserver: NetworkChangeObserving {
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private var handler: (@Sendable () -> Void)?

    func start(queue: DispatchQueue, handler: @escaping @Sendable () -> Void) {
        startCount += 1
        self.handler = handler
    }

    func cancel() {
        cancelCount += 1
        handler = nil
    }

    func send() {
        handler?()
    }
}
