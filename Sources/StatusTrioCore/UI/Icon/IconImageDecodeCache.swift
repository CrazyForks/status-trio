import AppKit

/// Bounded cache of decoded icon images keyed by their file URL.
///
/// The menu bar draws through an `NSImage` drawing handler on every display
/// pass, so without this each pass would re-read and re-decode the same input
/// source or audio-device icon from disk. Invalidation is identity-based: a
/// changed URL (or a changed source ID pointing at a new URL) is simply a new
/// key, and the oldest keys fall out beyond the bound.
final class IconImageDecodeCache: @unchecked Sendable {
    static let shared = IconImageDecodeCache()

    private let lock = NSLock()
    private let maximumEntries: Int
    private var storage: [URL: NSImage] = [:]
    private var order: [URL] = []

    init(maximumEntries: Int = 8) {
        precondition(maximumEntries > 0, "the cache needs room for at least one image")
        self.maximumEntries = maximumEntries
    }

    /// Returns the cached image for `url`, loading it through `load` once when
    /// absent. A failed load is not cached.
    func image(for url: URL, load: (URL) -> NSImage?) -> NSImage? {
        lock.lock()
        if let cached = storage[url] {
            touch(url)
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let image = load(url) else { return nil }

        lock.lock()
        defer { lock.unlock() }
        if let existing = storage[url] {
            touch(url)
            return existing
        }
        storage[url] = image
        order.append(url)
        while order.count > maximumEntries {
            let oldest = order.removeFirst()
            storage[oldest] = nil
        }
        return image
    }

    /// Convenience for callers whose loader is `NSImage(contentsOf:)`.
    func decodedImage(for url: URL) -> NSImage? {
        image(for: url) { NSImage(contentsOf: $0) }
    }

    private func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }
}
