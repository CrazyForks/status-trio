import XCTest
@testable import StatusTrioCore

@MainActor
final class NetworkConnectionMonitorTests: XCTestCase {
    func testWiredPathUpdatePublishesEthernet() async {
        let pathMonitor = FakeNetworkPathMonitor()
        let monitor = NetworkConnectionMonitor(pathMonitor: pathMonitor)
        let updated = expectation(description: "connection update published")
        let updateTask = Task {
            var iterator = monitor.updates.makeAsyncIterator()
            let connection = await iterator.next()
            XCTAssertEqual(connection, .ethernet)
            updated.fulfill()
        }

        monitor.start()
        pathMonitor.send(
            NetworkPathSnapshot(connected: true, wired: true, wireless: true)
        )
        await fulfillment(of: [updated], timeout: 1)

        XCTAssertEqual(pathMonitor.startCount, 1)
        updateTask.cancel()
        monitor.stop()
    }

    func testRecoverRestartsPathMonitoring() {
        let pathMonitor = FakeNetworkPathMonitor()
        let monitor = NetworkConnectionMonitor(pathMonitor: pathMonitor)

        monitor.start()
        monitor.recover()

        XCTAssertEqual(pathMonitor.startCount, 2)
        XCTAssertEqual(pathMonitor.cancelCount, 1)
        monitor.stop()
    }
}

private final class FakeNetworkPathMonitor: NetworkPathMonitoring {
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private var handler: ((NetworkPathSnapshot) -> Void)?

    func start(
        queue: DispatchQueue,
        handler: @escaping (NetworkPathSnapshot) -> Void
    ) {
        startCount += 1
        self.handler = handler
    }

    func cancel() {
        cancelCount += 1
        handler = nil
    }

    func send(_ snapshot: NetworkPathSnapshot) {
        handler?(snapshot)
    }
}
