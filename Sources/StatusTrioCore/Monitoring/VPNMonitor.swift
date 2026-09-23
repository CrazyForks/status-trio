import Foundation
import SystemConfiguration

/// Delivers a callback whenever the system's network configuration changes.
protocol NetworkChangeObserving: AnyObject {
    func start(queue: DispatchQueue, handler: @escaping @Sendable () -> Void)
    func cancel()
}

/// A `SCDynamicStore` watcher over the keys and patterns a tunnel or a proxy
/// can move: the global proxy dictionary, the global IPv4 set, per-interface
/// IPv4, and the PPP/IPSec state of every service.
///
/// Only the notification is subscribed here. The read stays in `VPNReader`, so
/// the callback carries no payload and nothing is parsed off the change list.
final class SystemNetworkChangeObserver: @unchecked Sendable, NetworkChangeObserving {
    private let lock = NSLock()
    private var store: SCDynamicStore?
    private var handler: (@Sendable () -> Void)?

    func start(queue: DispatchQueue, handler: @escaping @Sendable () -> Void) {
        // A second `start` without a `cancel` would leave the first store
        // subscribed, reporting into a handler that is no longer the one in use.
        cancel()

        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let store = SCDynamicStoreCreate(
            nil,
            "StatusTrio.VPN" as CFString,
            vpnDynamicStoreCallback,
            &context
        ) else {
            return
        }

        let keys = [
            "State:/Network/Global/Proxies",
            "State:/Network/Global/IPv4"
        ] as CFArray
        let patterns = [
            "State:/Network/Interface/.*/IPv4",
            "State:/Network/Service/.*/PPP",
            "State:/Network/Service/.*/IPSec"
        ] as CFArray
        guard SCDynamicStoreSetNotificationKeys(store, keys, patterns) else { return }

        lock.withLock {
            self.store = store
            self.handler = handler
        }
        _ = SCDynamicStoreSetDispatchQueue(store, queue)
    }

    func cancel() {
        let store = lock.withLock { () -> SCDynamicStore? in
            let store = self.store
            self.store = nil
            self.handler = nil
            return store
        }
        guard let store else { return }
        // Clears the dispatch queue before the store is released, so a
        // notification already in flight cannot reach a handler that is gone.
        _ = SCDynamicStoreSetDispatchQueue(store, nil)
    }

    fileprivate func storeDidChange() {
        let handler = lock.withLock { self.handler }
        handler?()
    }
}

/// The callback is a plain C function pointer, so it cannot capture context.
/// The observer is recovered from the store's `info` pointer instead, which is
/// safe because the monitor holds the observer for the whole subscription.
private let vpnDynamicStoreCallback: SCDynamicStoreCallBack = { _, _, info in
    guard let info else { return }
    let observer = Unmanaged<SystemNetworkChangeObserver>
        .fromOpaque(info)
        .takeUnretainedValue()
    observer.storeDidChange()
}

/// Watches the three VPN signals and publishes the resolved status.
///
/// The lifecycle mirrors `NetworkConnectionMonitor`: `idle` → `running` →
/// `stopped`, with `recover()` available while running to re-subscribe after a
/// wake. Reads happen on the main actor because a full read is a `getifaddrs`
/// pass plus two `SystemConfiguration` lookups, measured in single-digit
/// milliseconds on macOS 26.6.1, and this monitor is refreshed by the store's
/// fallback tick rather than by a per-frame path — moving the read off the main
/// actor would buy nothing and add a sequence guard for out-of-order results.
@MainActor
final class VPNMonitor: VPNMonitoring {
    private enum Lifecycle {
        case idle
        case running
        case stopped
    }

    let updates: AsyncStream<VPNStatus>

    nonisolated(unsafe) private let reader: any VPNReading
    nonisolated(unsafe) private let observer: any NetworkChangeObserving
    private let queue = DispatchQueue(label: "StatusTrio.VPN")
    private let continuation: AsyncStream<VPNStatus>.Continuation
    private var lifecycle = Lifecycle.idle
    /// The last value handed to the stream, so a notification that changed
    /// nothing does not wake the store.
    private var lastPublished: VPNStatus?

    init(
        reader: any VPNReading = SystemVPNReader(),
        observer: any NetworkChangeObserving = SystemNetworkChangeObserver()
    ) {
        self.reader = reader
        self.observer = observer
        (updates, continuation) = MonitorStream.make(of: VPNStatus.self)
    }

    deinit {
        if lifecycle != .stopped {
            observer.cancel()
            continuation.finish()
        }
    }

    func start() {
        guard lifecycle == .idle else { return }
        lifecycle = .running
        startObserving()
        refresh()
    }

    func refresh() {
        guard lifecycle == .running else { return }
        publish(VPNStatusResolver.resolve(reader.read()))
    }

    /// Re-subscribes and reads again. The old subscription is cancelled first,
    /// the same way `NetworkConnectionMonitor.recover()` cancels its path
    /// monitor, so a monitor recovered twice cannot end up with two live
    /// stores both reporting.
    func recover() {
        guard lifecycle == .running else { return }
        observer.cancel()
        startObserving()
        refresh()
    }

    func stop() {
        guard lifecycle != .stopped else { return }
        lifecycle = .stopped
        observer.cancel()
        continuation.finish()
    }

    private func startObserving() {
        observer.start(queue: queue) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func publish(_ status: VPNStatus) {
        guard lifecycle == .running, status != lastPublished else { return }
        lastPublished = status
        continuation.yield(status)
    }
}
