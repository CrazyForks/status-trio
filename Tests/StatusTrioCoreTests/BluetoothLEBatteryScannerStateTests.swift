import Foundation
import Testing
@testable import StatusTrioCore

struct BluetoothLEBatteryScannerStateTests {
    @Test func passiveDiscoveryKeepsScanCadenceWithoutAnyConnectionQueue() {
        let start = Date(timeIntervalSince1970: 1_000)
        var policy = BluetoothLEBatteryScanPolicy()

        #expect(BluetoothLEBatteryScanPolicy.scanWindow == .seconds(5))
        #expect(BluetoothLEBatteryScanPolicy.automaticScanInterval == 60)
        let firstScan = policy.beginScan(at: start, manual: false)
        let earlyAutomaticScan = policy.beginScan(at: start.addingTimeInterval(59), manual: false)
        let manualRefresh = policy.beginScan(at: start.addingTimeInterval(59), manual: true)
        #expect(firstScan)
        #expect(!earlyAutomaticScan)
        #expect(manualRefresh)
    }

    @Test func stopInvalidatesCallbacksFromThePreviousPassiveScan() {
        var policy = BluetoothLEBatteryScanPolicy()
        let started = policy.beginScan(at: Date(timeIntervalSince1970: 2_000), manual: true)
        let oldGeneration = policy.generation

        policy.stop()

        #expect(started)
        #expect(!policy.acceptsCallback(from: oldGeneration))
    }
}
