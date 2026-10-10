import Foundation
import PowerHelperProtocol

/// Accepts XPC connections from the app and exports the power-mode service.
///
/// The listener itself carries the code-signing requirement
/// (`setConnectionCodeSigningRequirement`), so a mismatched peer is rejected by
/// Foundation before this delegate runs. The delegate re-checks the caller as
/// defense in depth and logs any rejection.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: PowerModeService

    init(service: PowerModeService) {
        self.service = service
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard ClientAuthorization.isCallerAllowed(connection) else {
            NSLog(
                "StatusTrioPowerHelper rejected connection from pid %d",
                connection.processIdentifier
            )
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: PowerHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}