import AppKit

enum AppIconImage {
    static let bundledResourceName = "AppIcon"

    /// The packaged app icon, which stays stable even while the Dock tile shows
    /// the live status icon.
    static func bundled(in bundle: Bundle = .main) -> NSImage? {
        bundle.image(forResource: bundledResourceName)
    }
}
