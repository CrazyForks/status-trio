import Foundation
import XCTest
@testable import StatusTrioCore

final class LocationUsageDescriptionTests: XCTestCase {
    func testAppDeclaresBothNativeMacAndWhenInUseLocationPurposes() throws {
        try assertLocationPurposes(in: root.appendingPathComponent("Support/Info.plist"))
    }

    func testEveryLanguageLocalizesBothLocationPurposes() throws {
        for language in AppLanguage.allCases {
            try assertLocationPurposes(in: root.appendingPathComponent(
                "Sources/StatusTrioCore/Resources/\(language.rawValue).lproj/InfoPlist.strings"
            ))
        }
    }

    private func assertLocationPurposes(in url: URL) throws {
        let values = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        for key in ["NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription"] {
            let value = try XCTUnwrap(values[key] as? String, "\(url.path) is missing \(key)")
            XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(url.path): \(key)")
        }
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
