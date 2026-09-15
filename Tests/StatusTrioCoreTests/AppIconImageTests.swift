import AppKit
import XCTest
@testable import StatusTrioCore

final class AppIconImageTests: XCTestCase {
    func testBundledIconLoadsFromBundleResources() throws {
        let fixture = try makeBundle(includingIcon: true)
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        let image = try XCTUnwrap(AppIconImage.bundled(in: fixture.bundle))

        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testBundledIconIsNilWithoutResource() throws {
        let fixture = try makeBundle(includingIcon: false)
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        XCTAssertNil(AppIconImage.bundled(in: fixture.bundle))
    }

    private func makeBundle(includingIcon: Bool) throws -> (bundle: Bundle, url: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AppIconImage-\(UUID().uuidString).bundle", isDirectory: true)
        let contents = root.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.lingsmbp.StatusTrioTests.AppIconFixture",
            "CFBundlePackageType": "BNDL"
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contents.appendingPathComponent("Info.plist"))

        if includingIcon {
            let image = NSImage(size: NSSize(width: 64, height: 64))
            image.lockFocus()
            NSColor.systemBlue.setFill()
            NSRect(x: 0, y: 0, width: 64, height: 64).fill()
            image.unlockFocus()

            let representation = try XCTUnwrap(
                NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))
            )
            let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try data.write(to: resources.appendingPathComponent("AppIcon.png"))
        }

        return (try XCTUnwrap(Bundle(url: root)), root)
    }
}
