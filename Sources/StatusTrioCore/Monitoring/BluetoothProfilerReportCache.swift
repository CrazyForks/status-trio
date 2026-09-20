import Foundation

/// One `system_profiler -json SPBluetoothDataType` run feeds both the paired
/// device list and the battery levels: both parsers read the same JSON, so a
/// second process would only repeat work the first one already did. The device
/// worker fills the cache, the battery worker reads it, and neither owns the
/// other, so the app shares a single instance.
final class BluetoothProfilerReportCache: @unchecked Sendable {
    static let shared = BluetoothProfilerReportCache()

    /// A report older than this is treated as absent, so a battery read that
    /// happens on its own still asks the system for current data instead of
    /// reusing a level that may already be stale.
    static let defaultMaxAge: TimeInterval = 5

    private let lock = NSLock()
    private var entry: (data: Data, storedAt: Date)?

    func store(_ data: Data, at date: Date = Date()) {
        lock.withLock { entry = (data, date) }
    }

    func freshData(
        maxAge: TimeInterval = BluetoothProfilerReportCache.defaultMaxAge,
        now: Date = Date()
    ) -> Data? {
        lock.withLock {
            guard let entry, now.timeIntervalSince(entry.storedAt) < maxAge else { return nil }
            return entry.data
        }
    }
}
