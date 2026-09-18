import Foundation
import Testing
@testable import StatusTrioCore

/// `IOBluetoothDevice.nameOrAddress` returns a cached name that never picks up
/// a rename, so the paired list is read from the system profiler instead: the
/// same source the battery levels already come from.
struct BluetoothPairedDeviceListTests {
    private let connectedAndPaired = """
    {
      "SPBluetoothDataType": [
          {
            "device_connected": [
              {
                "机灵的AirPods": {
                  "device_address": "AC:90:85:C2:9C:1F",
                  "device_minorType": "Headphones"
                }
              }
            ],
            "device_not_connected": [
              {
                "MX Keys": {
                  "device_address": "D3:6D:6C:40:A3:2E",
                  "device_minorType": "Keyboard"
                }
              }
            ]
          }
        ]
    }
    """

    /// The regression: a renamed device has to report its current name, which
    /// the IOBluetooth cache did not.
    @Test func reportsTheNameTheSystemCurrentlyUses() throws {
        let devices = try #require(
            BluetoothPairedDeviceReader.parse(json: Data(connectedAndPaired.utf8))
        )

        #expect(devices.count == 2)
        let airPods = try #require(devices.first { $0.id == "AC:90:85:C2:9C:1F" })
        #expect(airPods.name == "机灵的AirPods")
        #expect(airPods.isConnected)
        #expect(airPods.kind == .audio)
    }

    @Test func keepsPairedButDisconnectedDevices() throws {
        let devices = try #require(
            BluetoothPairedDeviceReader.parse(json: Data(connectedAndPaired.utf8))
        )

        let keyboard = try #require(devices.first { $0.id == "D3:6D:6C:40:A3:2E" })
        #expect(keyboard.name == "MX Keys")
        #expect(keyboard.isConnected == false)
        #expect(keyboard.kind == .peripheral)
    }

    @Test func normalizesTheAddressToMatchTheBatteryReader() throws {
        let devices = try #require(
            BluetoothPairedDeviceReader.parse(json: Data(connectedAndPaired.utf8))
        )

        let airPods = try #require(devices.first { $0.name == "机灵的AirPods" })
        #expect(BluetoothBatteryReader.normalizedAddress(airPods.id) == "AC9085C29C1F")
    }

    /// An unsupported minor type stays generic rather than being guessed as
    /// audio, which would make it eligible for a battery level.
    @Test func unknownMinorTypesStayGeneric() throws {
        let json = """
        {"SPBluetoothDataType": [{"device_connected": [
          {"Mystery Device": {"device_address": "AA:BB:CC:DD:EE:FF", "device_minorType": "Unknown"}}
        ]}]}
        """
        let devices = try #require(BluetoothPairedDeviceReader.parse(json: Data(json.utf8)))

        #expect(devices.first?.kind == .unknown)
        #expect(devices.first?.isAirPods == false)
    }

    @Test func majorTypeDrivesTheKindWhenTheMinorTypeIsMissing() throws {
        let json = """
        {"SPBluetoothDataType": [{"device_connected": [
          {"Generic Peripheral": {"device_address": "AA:BB:CC:DD:EE:FF", "device_majorType": "Peripheral"}}
        ]}]}
        """
        let devices = try #require(BluetoothPairedDeviceReader.parse(json: Data(json.utf8)))

        #expect(devices.first?.kind == .peripheral)
    }

    /// No readable device database is a read failure, not "no paired devices".
    @Test func malformedOutputIsAReadFailure() {
        #expect(BluetoothPairedDeviceReader.parse(json: Data("not json".utf8)) == nil)
    }

    /// A machine that genuinely has no paired devices reports an empty list.
    @Test func emptyDatabaseIsAnEmptyList() throws {
        let json = """
        {"SPBluetoothDataType": [{"device_connected": [], "device_not_connected": []}]}
        """
        let devices = try #require(BluetoothPairedDeviceReader.parse(json: Data(json.utf8)))

        #expect(devices.isEmpty)
    }

    @Test func readerSurfacesProfilerOutput() async {
        let worker = SystemProfilerBluetoothPairedDeviceWorker {
            Data(self.connectedAndPaired.utf8)
        }
        let box = ResultBox()

        worker.read { box.set($0) }
        await waitUntil { box.value != nil }

        guard case .success(let devices) = box.value else {
            Issue.record("expected a successful read, got \(String(describing: box.value))")
            return
        }
        #expect(devices.contains { $0.name == "机灵的AirPods" })
    }

    @Test func readerReportsFailureWithoutProfilerOutput() async {
        let worker = SystemProfilerBluetoothPairedDeviceWorker { nil }
        let box = ResultBox()

        worker.read { box.set($0) }
        await waitUntil { box.value != nil }

        guard case .failed = box.value else {
            Issue.record("expected a read failure, got \(String(describing: box.value))")
            return
        }
    }

    /// The reader answers on its own serial queue.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for the profiler read")
    }
}

/// The reader delivers on its own queue, so the test needs somewhere
/// thread-safe to collect the result.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: BluetoothWorkerResult?

    var value: BluetoothWorkerResult? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ result: BluetoothWorkerResult) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}
