import XCTest
@testable import StatusTrioCore

final class DDCVolumeReplyTests: XCTestCase {
    private let valid: [UInt8] = [110, 136, 2, 0, 98, 0, 0, 100, 0, 100, 214]

    func testDecodesMeasuredXV272UReplyAsFullVolume() {
        let reply = DDCVolumeReply.decode(valid)

        XCTAssertEqual(reply?.current, 100)
        XCTAssertEqual(reply?.maximum, 100)
        XCTAssertEqual(reply?.scalar, 1)
    }

    func testRejectsInvalidResultCode() {
        XCTAssertNil(DDCVolumeReply.decode(reply(changing: 3, to: 1)))
    }

    func testRejectsUnexpectedEchoedCode() {
        XCTAssertNil(DDCVolumeReply.decode(reply(changing: 4, to: 0x8D)))
    }

    func testRejectsWrongLength() {
        XCTAssertNil(DDCVolumeReply.decode(Array(valid.dropLast())))
    }

    func testRejectsBadChecksum() {
        var malformed = valid
        malformed[10] ^= 1

        XCTAssertNil(DDCVolumeReply.decode(malformed))
    }

    func testRejectsZeroMaximum() {
        XCTAssertNil(DDCVolumeReply.decode(reply(changing: 6, to: 0, and: 7, to: 0)))
    }

    func testRejectsCurrentAboveMaximum() {
        XCTAssertNil(DDCVolumeReply.decode(reply(changing: 9, to: 101)))
    }

    func testRoundsAndClampsTargetValue() {
        let reply = DDCVolumeReply(current: 50, maximum: 100)

        XCTAssertEqual(reply.targetValue(for: 0.955), 96)
        XCTAssertEqual(reply.targetValue(for: -0.1), 0)
        XCTAssertEqual(reply.targetValue(for: 1.1), 100)
    }

    private func reply(changing index: Int, to value: UInt8) -> [UInt8] {
        reply(changing: index, to: value, and: nil, to: nil)
    }

    private func reply(
        changing firstIndex: Int,
        to firstValue: UInt8,
        and secondIndex: Int? = nil,
        to secondValue: UInt8? = nil
    ) -> [UInt8] {
        var bytes = valid
        bytes[firstIndex] = firstValue
        if let secondIndex, let secondValue {
            bytes[secondIndex] = secondValue
        }
        bytes[10] = bytes.prefix(10).reduce(UInt8(0x50), ^)
        return bytes
    }
}
