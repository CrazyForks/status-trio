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
}
