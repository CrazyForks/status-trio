import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class AppMenuBuilderTests: XCTestCase {
    func testMainMenuProvidesStandardPasteCommand() throws {
        let mainMenu = AppMenuBuilder.makeMainMenu()
        let editItem = try XCTUnwrap(mainMenu.item(withTitle: "Edit"))
        let pasteItem = try XCTUnwrap(editItem.submenu?.item(withTitle: "Paste"))

        XCTAssertEqual(pasteItem.keyEquivalent, "v")
        XCTAssertTrue(pasteItem.keyEquivalentModifierMask.contains(.command))
        XCTAssertEqual(pasteItem.action, #selector(NSText.paste(_:)))
    }
}
