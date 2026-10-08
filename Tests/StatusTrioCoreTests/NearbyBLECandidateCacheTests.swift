import Foundation
import Testing
@testable import StatusTrioCore

struct NearbyBLECandidateCacheTests {
    @Test func anEmptyFollowupScanRemovesCandidatesFromThePriorScan() {
        let start = Date(timeIntervalSince1970: 10_000)
        let id = UUID()
        var cache = NearbyBLECandidateCache()
        cache.beginScan()
        cache.record(NearbyBLEDeviceCandidate(id: id, name: "Nearby", vendor: .apple, lastSeen: start))
        #expect(cache.finishScan(at: start).map(\.id) == [id])

        cache.beginScan()

        #expect(cache.finishScan(at: start.addingTimeInterval(5)).isEmpty)
    }

    @Test func candidatesExpireAfterTheDiscoveryFreshnessWindow() {
        let start = Date(timeIntervalSince1970: 20_000)
        let id = UUID()
        var cache = NearbyBLECandidateCache()
        cache.beginScan()
        cache.record(NearbyBLEDeviceCandidate(id: id, name: "Nearby", vendor: .other, lastSeen: start))
        _ = cache.finishScan(at: start)

        #expect(cache.expire(at: start.addingTimeInterval(NearbyBLEDeviceCatalog.recentCandidateLifetime + 1)).isEmpty)
    }
}
