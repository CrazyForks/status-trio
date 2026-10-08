import Foundation
import XCTest

final class MacOS13UICompatibilityTests: XCTestCase {
    func testCompatibleViewsDoNotUseTheMacOS14TwoParameterOnChangeOverload() throws {
        let files = [
            "Sources/StatusTrioCore/UI/AudioInputControlsView.swift",
            "Sources/StatusTrioCore/UI/BluetoothDeviceList.swift",
            "Sources/StatusTrioCore/UI/BluetoothStatusView.swift",
            "Sources/StatusTrioCore/UI/IconGuideView.swift",
            "Sources/StatusTrioCore/UI/Settings/StatusIconPreviewCard.swift",
            "Sources/StatusTrioCore/UI/VolumeControlsView.swift"
        ]
        // Match the two-parameter closure in one line only. A multiline
        // regex here can run from an unrelated opening brace to the next
        // `_ ,` and report false positives in large view files.
        let pattern = try NSRegularExpression(
            pattern: #"\.onChange\(of:[^)]*\)\s*\{\s*_[^,]*,.*\}"#
        )

        for path in files {
            let source = try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            XCTAssertNil(
                pattern.firstMatch(in: source, range: range),
                "\(path) still uses the macOS 14 two-parameter onChange overload"
            )
        }
    }

    func testBluetoothViewsRouteEveryVisibilityChangeThroughASnapshot() throws {
        let statusSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/StatusTrioCore/UI/BluetoothStatusView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(statusSource.contains(".onChange(of: readAuthorizationSnapshot)"))
        XCTAssertTrue(statusSource.contains("updateReadAuthorization(snapshot)"))
        XCTAssertFalse(statusSource.contains(".onChange(of: showsBatteryLevels) { _ in updateNearbyReadAuthorization() }"))
        XCTAssertFalse(statusSource.contains(".onChange(of: showsAppleDevicesAndBattery) { _ in updateNearbyReadAuthorization() }"))

        let listSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/StatusTrioCore/UI/BluetoothDeviceList.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(listSource.contains("BluetoothDeviceListVisibilitySnapshot"))
        XCTAssertTrue(listSource.contains(".onChange(of: visibilitySnapshot)"))
    }

    func testPictureRowKeepsNativeActivationAndUsesMoveCommandForArrows() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/StatusTrioCore/UI/Settings/SettingsChrome.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".onMoveCommand"))
        XCTAssertTrue(source.contains(".onKeyPress"))
        XCTAssertEqual(
            source.components(separatedBy: ".focusEffectDisabled()").count - 1,
            1,
            "focusEffectDisabled must appear only in the macOS 14+ compatibility modifier"
        )
        let availability = try XCTUnwrap(source.range(of: "if #available(macOS 14.0, *)"))
        let focusEffect = try XCTUnwrap(source.range(of: ".focusEffectDisabled()"))
        XCTAssertLessThan(availability.lowerBound, focusEffect.lowerBound)
        XCTAssertTrue(source.contains("selectOption(option)"))
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
