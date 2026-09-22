import Foundation
import IOBluetooth
import IOKit

/// Asks the system to connect or disconnect a paired device.
///
/// `IOBluetoothDevice`'s connect and disconnect calls are synchronous and can
/// block until the page timeout when a device is out of range, so the
/// implementation runs them on its own queue and the controller only ever sees
/// whether the system accepted the request. Whether the link actually comes up
/// is decided by the device report, never by this return value. `completion`
/// runs on the performer's private queue, never on the main thread.
protocol BluetoothDeviceActionPerforming: AnyObject {
    func setConnected(
        _ connected: Bool,
        forAddress address: String,
        completion: @escaping @Sendable (Bool) -> Void
    )
}

/// Which paired device an action request is aimed at.
///
/// Both sides are normalized: callers hand over the raw `device_address` the
/// report carries, which is the same address in another shape (`AC:90:85:C2:9C:1F`
/// against IOBluetooth's `ac-90-85-c2-9c-1f`), and IOBluetooth's own name for the
/// device is never consulted because it can still be the one from before a
/// rename.
enum BluetoothDeviceActionTargeting {
    static func matches(reported: String?, wanted: String) -> Bool {
        let wantedAddress = BluetoothBatteryReader.normalizedAddress(wanted)
        guard !wantedAddress.isEmpty else { return false }
        return BluetoothBatteryReader.normalizedAddress(reported ?? "") == wantedAddress
    }
}

/// `@unchecked Sendable` is safe: the type's only stored state is an immutable
/// `DispatchQueue`, and device handles are found inside the queued closure and
/// never leave it.
final class IOBluetoothDeviceActionPerformer: @unchecked Sendable, BluetoothDeviceActionPerforming {
    private let queue = DispatchQueue(
        label: "StatusTrio.IOBluetoothDeviceActionPerformer",
        qos: .userInitiated
    )

    func setConnected(
        _ connected: Bool,
        forAddress address: String,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        queue.async {
            // The paired list is the only source of a device handle, and it is
            // matched on the normalized address: IOBluetooth keeps reporting the
            // name a device had before it was renamed, so names cannot join it to
            // the report the UI is built from.
            let target = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?
                .first { BluetoothDeviceActionTargeting.matches(reported: $0.addressString, wanted: address) }
            guard let target else {
                // The device is gone from the paired database (unpaired, say).
                completion(false)
                return
            }
            let result = connected ? target.openConnection() : target.closeConnection()
            completion(result == kIOReturnSuccess)
        }
    }
}
