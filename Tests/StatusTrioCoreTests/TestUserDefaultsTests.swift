import Foundation
import Testing

struct TestUserDefaultsTests {
    @Test func removingATestSuiteDeletesItsPreferenceFile() throws {
        let name = "StatusTrioCoreTests.TestUserDefaults.\(UUID().uuidString)"
        let fileURL = TestUserDefaults.fileURL(forSuite: name)
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set("value", forKey: "key")
        defaults.synchronize()
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        TestUserDefaults.removeSuite(named: name)

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    /// cfprefsd flushes a domain it still considers live a moment after the
    /// teardown runs. This pins that removing a suite survives that flush: the
    /// previous `removePersistentDomain`-based teardown lost the race and the
    /// file came back as an empty 42-byte plist, once per suite per run.
    @Test func removingATestSuiteKeepsThePreferenceFileDeleted() async throws {
        let name = "StatusTrioCoreTests.TestUserDefaults.\(UUID().uuidString)"
        let fileURL = TestUserDefaults.fileURL(forSuite: name)
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set("value", forKey: "key")
        defaults.synchronize()

        TestUserDefaults.removeSuite(named: name)

        try await Task.sleep(for: .seconds(1.5))
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }
}
