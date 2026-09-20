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

/// A registration handed back by IOBluetooth. `unregister()` is the SDK's
/// invalidation mechanism, so dropping the last reference to one does not
/// deregister it. Keeping the handle abstract lets the lifetime bookkeeping be
/// tested with counted fakes instead of the system's Bluetooth service.
protocol BluetoothNotificationToken: AnyObject {
    func unregister()
}

extension IOBluetoothUserNotification: BluetoothNotificationToken {}

final class IOBluetoothConnectionEventMonitor: NSObject, BluetoothConnectionEventMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var connectNotification: (any BluetoothNotificationToken)?
    private var disconnectNotifications: [String: any BluetoothNotificationToken] = [:]

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
            () -> ((any BluetoothNotificationToken)?, [any BluetoothNotificationToken]) in
            let connect = connectNotification
            let disconnects = Array(disconnectNotifications.values)
            connectNotification = nil
            disconnectNotifications.removeAll()
            handler = nil
            return (connect, disconnects)
        }
        // Unregistered outside the lock: `unregister()` is an SDK call, and
        // holding the lock across it would let a notification callback that is
        // already running deadlock against teardown.
        connect?.unregister()
        for notification in disconnects {
            notification.unregister()
        }
    }

    /// The connect notification is system-wide; the disconnect notification is
    /// per device, so each device that connects is watched as it arrives. A
    /// device's entry is unregistered before it is dropped — both when the
    /// device disconnects and when a reconnect replaces it — and `stop()`
    /// releases whatever is still registered, so no registration outlives the
    /// device state it describes.
    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        handleDeviceConnected(
            identity: Self.deviceIdentity(addressString: device.addressString, name: device.name)
        ) {
            device.register(
                forDisconnectNotification: self,
                selector: #selector(deviceDisconnected(_:device:))
            )
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        handleDeviceDisconnected(
            identity: Self.deviceIdentity(addressString: device.addressString, name: device.name)
        )
    }

    /// The key a device is registered and removed under. Both callbacks derive
    /// it the same way: a device with no address falls back to its name, so the
    /// disconnect path removes exactly the key the connect path inserted.
    static func deviceIdentity(addressString: String?, name: String?) -> String {
        addressString ?? name ?? ""
    }

    /// The bookkeeping behind the connect callback, with the registration
    /// supplied by the caller, so registration and unregistration can be counted
    /// without touching the system's Bluetooth service.
    func handleDeviceConnected(
        identity: String,
        registerDisconnect: () -> (any BluetoothNotificationToken)?
    ) {
        if !identity.isEmpty, let token = registerDisconnect() {
            // Replaced under the lock and unregistered outside it: `unregister()`
            // is an SDK call and must not run while the lock is held.
            let replaced = lock.withLock { disconnectNotifications.updateValue(token, forKey: identity) }
            replaced?.unregister()
        }
        lock.withLock { handler }?()
    }

    /// The bookkeeping behind the disconnect callback. The token is unregistered
    /// before it is dropped: `unregister()` is what invalidates the
    /// registration, so clearing the entry alone would leave the callback armed
    /// and fire it again on the next disconnect.
    func handleDeviceDisconnected(identity: String) {
        let removed = lock.withLock { disconnectNotifications.removeValue(forKey: identity) }
        removed?.unregister()
        lock.withLock { handler }?()
    }
}
