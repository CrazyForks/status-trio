import Foundation
import IOBluetooth

/// System-wide Bluetooth connect and disconnect notifications.
///
/// CoreBluetooth only reports `didConnect` for peripherals this process
/// connected itself, and the app never connects one: the paired-device database
/// belongs to macOS. `IOBluetoothDevice` connects are reported for every device
/// the system connects, which is what the summary row needs.
///
/// The callbacks are delivered on the thread that registered the notification,
/// so the implementation is nonisolated and lock-guarded, and the controller
/// hops to the main actor inside the handler it passes in.
protocol BluetoothConnectionEventMonitoring: AnyObject {
    /// Registers for connect notifications and hands back whether the system
    /// accepted the registration. A `false` result leaves the safety-net poll
    /// as the only source of device state.
    @discardableResult
    func start(handler: @escaping @Sendable () -> Void) -> Bool
    func stop()
}

final class IOBluetoothConnectionEventMonitor: NSObject, BluetoothConnectionEventMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    @discardableResult
    func start(handler: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock { self.handler = handler }
        let notification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        return lock.withLock {
            connectNotification = notification
            return notification != nil
        }
    }

    func stop() {
        let (connect, disconnects) = lock.withLock {
            () -> (IOBluetoothUserNotification?, [IOBluetoothUserNotification]) in
            let connect = connectNotification
            let disconnects = Array(disconnectNotifications.values)
            connectNotification = nil
            disconnectNotifications.removeAll()
            handler = nil
            return (connect, disconnects)
        }
        connect?.unregister()
        for notification in disconnects {
            notification.unregister()
        }
    }

    /// The connect notification is system-wide; the disconnect notification is
    /// per device, so each device that connects is watched as it arrives. The
    /// entry is overwritten on a reconnect, and every registration is released
    /// by `stop()`.
    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString ?? device.name ?? ""
        if !address.isEmpty,
           let token = device.register(
               forDisconnectNotification: self,
               selector: #selector(deviceDisconnected(_:device:))
           ) {
            lock.withLock { disconnectNotifications[address] = token }
        }
        lock.withLock { handler }?()
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString ?? ""
        lock.withLock { disconnectNotifications[address] = nil }
        lock.withLock { handler }?()
    }
}
