import Foundation
import Network

struct NetworkPathSnapshot: Equatable, Sendable {
    let connected: Bool
    let wired: Bool
    let wireless: Bool

    var connection: NetworkConnection {
        NetworkConnection.resolve(
            connected: connected,
            wired: wired,
            wireless: wireless
        )
    }
}

protocol NetworkPathMonitoring: AnyObject {
    func start(
        queue: DispatchQueue,
        handler: @escaping (NetworkPathSnapshot) -> Void
    )
    func cancel()
}

final class NWPathConnectionMonitor: @unchecked Sendable, NetworkPathMonitoring {
    private let lock = NSLock()
    private var monitor: NWPathMonitor?
    private var handler: ((NetworkPathSnapshot) -> Void)?

    func start(
        queue: DispatchQueue,
        handler: @escaping (NetworkPathSnapshot) -> Void
    ) {
        let monitor = NWPathMonitor()
        lock.withLock {
            self.monitor = monitor
            self.handler = handler
        }
        monitor.pathUpdateHandler = { [weak self, weak monitor] path in
            guard
                let self,
                let monitor,
                self.lock.withLock({ self.monitor === monitor })
            else { return }

            let snapshot = NetworkPathSnapshot(
                connected: path.status == .satisfied,
                wired: path.usesInterfaceType(.wiredEthernet),
                wireless: path.usesInterfaceType(.wifi)
            )
            let handler = self.lock.withLock { self.handler }
            handler?(snapshot)
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        let monitor = lock.withLock { () -> NWPathMonitor? in
            let monitor = self.monitor
            self.monitor = nil
            handler = nil
            return monitor
        }
        monitor?.cancel()
    }
}

@MainActor
final class NetworkConnectionMonitor: NetworkConnectionMonitoring {
    private enum Lifecycle {
        case idle
        case running
        case stopped
    }

    let updates: AsyncStream<NetworkConnection>

    nonisolated(unsafe) private let pathMonitor: any NetworkPathMonitoring
    private let queue = DispatchQueue(label: "StatusTrio.NetworkConnection")
    private let continuation: AsyncStream<NetworkConnection>.Continuation
    private var lifecycle = Lifecycle.idle

    init(pathMonitor: any NetworkPathMonitoring = NWPathConnectionMonitor()) {
        self.pathMonitor = pathMonitor
        (updates, continuation) = AsyncStream.makeStream()
    }

    deinit {
        if lifecycle != .stopped {
            pathMonitor.cancel()
            continuation.finish()
        }
    }

    func start() {
        guard lifecycle == .idle else { return }
        lifecycle = .running
        startPathMonitoring()
    }

    func recover() {
        guard lifecycle == .running else { return }
        pathMonitor.cancel()
        startPathMonitoring()
    }

    func stop() {
        guard lifecycle != .stopped else { return }
        lifecycle = .stopped
        pathMonitor.cancel()
        continuation.finish()
    }

    private func startPathMonitoring() {
        pathMonitor.start(queue: queue) { [weak self] snapshot in
            Task { @MainActor [weak self] in
                guard let self, self.lifecycle == .running else { return }
                self.continuation.yield(snapshot.connection)
            }
        }
    }
}
