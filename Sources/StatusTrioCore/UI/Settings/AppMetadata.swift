import Foundation

enum AppMetadata {
    static let defaultName = "Status Trio"
    private static let nameKeys = ["CFBundleDisplayName", "CFBundleName"]

    static var name: String {
        for key in nameKeys {
            if let value = validName(Bundle.main.object(forInfoDictionaryKey: key)) {
                return value
            }
        }
        return defaultName
    }

    static func name(from infoDictionary: [String: Any]) -> String {
        for key in nameKeys {
            if let value = validName(infoDictionary[key]) {
                return value
            }
        }
        return defaultName
    }

    private static func validName(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    static let repositoryDisplayName = "github.com/lingyired/status-trio"
    static let repositoryURL = URL(string: "https://github.com/lingyired/status-trio")!
    static let projectHomepageURL = URL(string: "https://statustrio.lingai.net/")!
    static let authorName = "lingyired"
    static let authorURL = URL(string: "https://github.com/lingyired")!
    static let authorWebsiteURL = URL(string: "https://lingai.net/")!

    static var versionDisplayString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
