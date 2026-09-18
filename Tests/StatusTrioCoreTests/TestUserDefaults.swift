import Foundation

/// Test-only helpers for discarding the isolated `UserDefaults` suites that
/// tests create.
///
/// The name-only entry point exists so teardown blocks can discard a suite
/// without capturing a `UserDefaults` instance, which is not `Sendable` and so
/// cannot be captured by an `@Sendable` teardown closure under Swift 6 strict
/// concurrency.
enum TestUserDefaults {
    /// Location of the plist `UserDefaults` persists a suite named `name` into.
    static func fileURL(forSuite name: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/\(name).plist")
    }

    /// Removes an isolated test suite.
    ///
    /// `removePersistentDomain(forName:)` empties the domain but leaves the
    /// backing `~/Library/Preferences/<name>.plist` on disk, so a test run used
    /// to leave one dead plist per suite behind forever. Removing the file as
    /// well is what keeps the user's preferences directory clean.
    static func removeSuite(named name: String) {
        UserDefaults().removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: fileURL(forSuite: name))
    }
}

extension UserDefaults {
    /// Convenience form of `TestUserDefaults.removeSuite(named:)` for call sites
    /// that already hold the suite.
    func removeTestSuite(named name: String) {
        TestUserDefaults.removeSuite(named: name)
    }
}
