import Foundation
import Testing
@testable import StatusTrioCore

struct ChargingEffectPreviewPlaybackTests {
    @Test func playbackShowsTwoCyclesAndExpiresAtThreePointSixSeconds() throws {
        var playback = ChargingEffectPreviewPlayback()
        let start = Date(timeIntervalSince1970: 1_000)

        #expect(playback.isPlaying == false)
        #expect(playback.phase(at: start) == nil)
        playback.start(at: start)

        let firstCycle = try #require(playback.phase(at: start))
        let secondCycle = try #require(playback.phase(at: start.addingTimeInterval(1.8)))
        let lastFrame = try #require(playback.phase(at: start.addingTimeInterval(3.55)))

        #expect(playback.isPlaying)
        #expect(firstCycle.step == 0)
        #expect(secondCycle.step == 0)
        #expect(lastFrame.step == 35)
        #expect(playback.phase(at: start.addingTimeInterval(3.6)) == nil)

        playback.stop()
        #expect(playback.isPlaying == false)
        #expect(playback.phase(at: start.addingTimeInterval(1)) == nil)
    }

    @Test func restartingPlaybackStartsFromAZeroPhase() throws {
        var playback = ChargingEffectPreviewPlayback()
        let start = Date(timeIntervalSince1970: 500)
        playback.start(at: start)
        playback.stop()
        playback.start(at: start.addingTimeInterval(10))

        let restarted = try #require(playback.phase(at: start.addingTimeInterval(10)))
        #expect(restarted.step == 0)
        #expect(restarted.kind == .steady)
    }
}
