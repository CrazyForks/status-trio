import AppKit

/// Bounded cache of decoded icon images keyed by their file URL.
///
/// The menu bar draws through an `NSImage` drawing handler on every display
/// pass, so without this each pass would re-read and re-decode the same input
/// source or audio-device icon from disk. Invalidation is identity-based: a
/// changed URL (or a changed source ID pointing at a new URL) is simply a new
/// key, and the oldest keys fall out beyond the bound. The panel's monochrome
/// version of the same file is a second kind of entry under the same URL, so
/// neither derivation reads the file twice.
final class IconImageDecodeCache: @unchecked Sendable {
    static let shared = IconImageDecodeCache()

    private enum Kind: Hashable {
        case decoded
        case inputSourceMask
    }

    private struct Key: Hashable {
        let url: URL
        let kind: Kind
    }

    private let lock = NSLock()
    private let maximumEntries: Int
    private var storage: [Key: NSImage] = [:]
    private var order: [Key] = []

    init(maximumEntries: Int = 8) {
        precondition(maximumEntries > 0, "the cache needs room for at least one image")
        self.maximumEntries = maximumEntries
    }

    /// Returns the cached image for `url`, loading it through `load` once when
    /// absent. A failed load is not cached.
    func image(for url: URL, load: (URL) -> NSImage?) -> NSImage? {
        image(for: Key(url: url, kind: .decoded), url: url, load: load)
    }

    /// The single-colour mark the status panel draws for an input source.
    ///
    /// See `InputSourceIconMask`: the panel tints its rows, so an icon has to
    /// survive as ink rather than as its own palette, and the conversion is not
    /// something the SwiftUI body may repeat per pass.
    func monochromeInputSourceIcon(for url: URL) -> NSImage? {
        image(for: Key(url: url, kind: .inputSourceMask), url: url) { url in
            guard let image = decodedImage(for: url) else { return nil }
            return InputSourceIconMask.make(from: image)
        }
    }

    private func image(for key: Key, url: URL, load: (URL) -> NSImage?) -> NSImage? {
        lock.lock()
        if let cached = storage[key] {
            touch(key)
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let image = load(url) else { return nil }

        lock.lock()
        defer { lock.unlock() }
        if let existing = storage[key] {
            touch(key)
            return existing
        }
        storage[key] = image
        order.append(key)
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

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
