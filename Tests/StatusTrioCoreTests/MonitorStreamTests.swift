import XCTest
@testable import StatusTrioCore

final class MonitorStreamTests: XCTestCase {
    func testMonitorStreamKeepsOnlyNewestUnconsumedValue() async {
        let (stream, continuation) = MonitorStream.make(of: Int.self)

        continuation.yield(1)
        continuation.yield(2)
        continuation.yield(3)

        var iterator = stream.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertEqual(value, 3)
        continuation.finish()
    }
}
