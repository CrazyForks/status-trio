import CoreAudio
import Foundation

@testable import StatusTrioCore

/// A discovery source that always finds nothing, so a view test that renders a
/// `BluetoothListeningModeController` never touches the machine's real CoreAudio
/// devices and its layout stays deterministic regardless of what is paired to the
/// test runner.
struct EmptyListeningModeEndpointProvider: CoreAudioBluetoothEndpointProviding {
    func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint] {
        []
    }
}

extension BluetoothListeningModeController {
    /// A controller for view/layout tests: no endpoints, an instant read-back, and a
    /// failure that never lingers. Publishing stays empty unless a test drives it.
    static func emptyForTesting() -> BluetoothListeningModeController {
        BluetoothListeningModeController(
            hal: BluetoothListeningModeHAL(
                backend: CoreAudioBluetoothListeningModeBackend(),
                sleeper: ImmediateListeningModeSleeper(),
                retryAttempts: 1,
                retryDelay: .milliseconds(1)
            ),
            endpointProvider: EmptyListeningModeEndpointProvider()
        )
    }
}
