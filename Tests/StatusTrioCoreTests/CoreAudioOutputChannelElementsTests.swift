import CoreAudio
import XCTest

@testable import StatusTrioCore

final class CoreAudioOutputChannelElementsTests: XCTestCase {
    func testMissingOrZeroChannelCountFallsBackToFirstTwoChannels() {
        XCTAssertEqual(CoreAudioOutputChannelElements.channels(forChannelCount: nil), [1, 2])
        XCTAssertEqual(CoreAudioOutputChannelElements.channels(forChannelCount: 0), [1, 2])
    }

    func testChannelCountProducesAllOneBasedElements() {
        XCTAssertEqual(CoreAudioOutputChannelElements.channels(forChannelCount: 4), [1, 2, 3, 4])
    }
}
