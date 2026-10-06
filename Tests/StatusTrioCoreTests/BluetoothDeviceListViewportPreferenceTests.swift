import SwiftUI
import Testing
@testable import StatusTrioCore

struct BluetoothDeviceListViewportPreferenceTests {
    @Test func zeroDefaultDoesNotErasePreviouslyReportedViewport() {
        let reportedViewport = CGRect(x: 10, y: 20, width: 200, height: 330)
        var value = reportedViewport

        BluetoothDeviceListViewportPreferenceKey.reduce(value: &value, nextValue: { .zero })

        #expect(value == reportedViewport)
    }

    @Test func positiveViewportReplacesPreviouslyReportedViewport() {
        let previousViewport = CGRect(x: 10, y: 20, width: 200, height: 330)
        let nextViewport = CGRect(x: 30, y: 40, width: 180, height: 168)
        var value = previousViewport

        BluetoothDeviceListViewportPreferenceKey.reduce(value: &value, nextValue: { nextViewport })

        #expect(value == nextViewport)
    }
}
