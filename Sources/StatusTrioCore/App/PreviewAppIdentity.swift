import Foundation

enum PreviewAppIdentity {
    static let bundleIdentifier = "com.lingsmbp.StatusTrio.preview"
    static let displayName = "Status Trio Preview"
    static let defaultsSuiteName = "com.lingsmbp.StatusTrio.preview"
    static let applicationSupportDirectoryName = "StatusTrioPreview"
    static let isPreviewBuild = true

    static var userDefaults: UserDefaults {
        UserDefaults(suiteName: defaultsSuiteName) ?? .standard
    }
}
