import Foundation
import Testing
@testable import StatusTrioCore

struct NearbyBLEViewportPreferenceTests {
    @Test func defaultZeroPreferenceDoesNotEraseAValidViewport() {
        let validViewport = CGRect(x: 4, y: 8, width: 160, height: 168)
        var reducedViewport = CGRect.zero

        NearbyBLEViewportPreferenceKey.reduce(value: &reducedViewport) { validViewport }
        #expect(reducedViewport == validViewport)

        NearbyBLEViewportPreferenceKey.reduce(value: &reducedViewport) { .zero }
        #expect(reducedViewport == validViewport)
    }
}
