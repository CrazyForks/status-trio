import Foundation

/// What tapping a device row asks the system to do.
enum BluetoothDeviceAction: Equatable, Sendable {
    case connect
    case disconnect

    /// The state a row shows while this action is in flight.
    var inFlightState: BluetoothDeviceActionState {
        switch self {
        case .connect: .connecting
        case .disconnect: .disconnecting
        }
    }
}

/// A row's action state. No entry for a device means the row reports the
/// device's own connection state.
enum BluetoothDeviceActionState: Equatable, Sendable {
    case connecting
    case disconnecting
    /// The action did not take effect; the row shows this for a few seconds.
    case failed(BluetoothDeviceAction)
}

/// The text a row shows where the connection state normally goes.
enum BluetoothDeviceRowStatus: Equatable, Sendable {
    case connected
    case notConnected
    case connecting
    case disconnecting
    case connectFailed
    case disconnectFailed
}

/// The rules a row's action follows, kept out of the views so both surfaces
/// agree and the rules can be unit-tested.
enum BluetoothDeviceActionPolicy {
    /// Which action a tap requests, from the device's current state.
    static func action(for device: BluetoothDevice) -> BluetoothDeviceAction {
        device.isConnected ? .disconnect : .connect
    }

    /// Disconnecting an input device would cut the user off from their own
    /// keyboard or mouse, so that one action is confirmed in place first. A
    /// connect never needs confirmation, and neither does disconnecting
    /// anything else.
    static func requiresConfirmation(for device: BluetoothDevice) -> Bool {
        device.isConnected && device.kind == .peripheral
    }

    /// What the row shows in place of its connection state.
    static func status(
        for device: BluetoothDevice,
        actionState: BluetoothDeviceActionState?
    ) -> BluetoothDeviceRowStatus {
        switch actionState {
        case .connecting: .connecting
        case .disconnecting: .disconnecting
        case .failed(.connect): .connectFailed
        case .failed(.disconnect): .disconnectFailed
        case nil: device.isConnected ? .connected : .notConnected
        }
    }
}
