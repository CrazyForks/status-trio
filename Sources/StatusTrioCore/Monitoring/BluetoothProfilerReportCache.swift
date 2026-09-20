import Foundation

/// One `system_profiler -json SPBluetoothDataType` run feeds both the paired
/// device list and the battery levels: both parsers read the same JSON, so a
/// second process would only repeat work the first one already did. The device
/// worker fills the cache, the battery worker reads it, and neither owns the
/// other, so the app shares a single instance.
final class BluetoothProfilerReportCache: @unchecked Sendable {
    static let shared = BluetoothProfilerReportCache()

    /// A report is treated as absent once this long has passed since the last
    /// `store` — the moment the report was produced — rather than since some
    /// earlier production. The workers store only the bytes they fetch, so a
    /// read that merely reuses a report does not move the window forward: a
    /// battery read that happens on its own still asks the system for current
    /// data instead of reusing a level that may already be stale.
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
