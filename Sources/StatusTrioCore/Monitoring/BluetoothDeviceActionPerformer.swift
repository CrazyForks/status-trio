import Foundation
import IOBluetooth
import IOKit

/// Asks the system to connect or disconnect a paired device.
///
/// `IOBluetoothDevice`'s connect and disconnect calls are synchronous and can
/// block until the page timeout when a device is out of range, so the
/// implementation runs them on its own queue and the controller only ever sees
/// whether the system accepted the request. Whether the link actually comes up
/// is decided by the device report, never by this return value.
protocol BluetoothDeviceActionPerforming: AnyObject {
    func setConnected(
        _ connected: Bool,
        forAddress address: String,
        completion: @escaping @Sendable (Bool) -> Void
    )
}

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
                .first {
                    BluetoothBatteryReader.normalizedAddress($0.addressString ?? "") == address
                }
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
