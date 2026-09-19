import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

// TEMPORARY DIAGNOSTIC — remove before merging. Dumps the AppKit view tree that
// SwiftUI realizes for the row views whose hit-area tests differ between the
// macOS 15 and macOS 26 toolchains.
@MainActor
final class ZZToolchainDiagnosticTests: XCTestCase {
    func testDumpRowViewTrees() {
        let localization = makeLocalization()

        dump("PreferenceCheckboxRow", PreferenceCheckboxRow(
            label: .settingsBatteryShowPercentage,
            isOn: .constant(false)
        ).environmentObject(localization), size: NSSize(width: 300, height: 40))

        dump("SettingsDisclosureRow", SettingsDisclosureRow(
            "cable.connector",
            tint: .teal,
            title: localization.string(.settingsNetworkConnectionIcons),
            subtitle: localization.string(.settingsNetworkConnectionIconsDescription),
            isExpanded: .constant(false)
        ).environmentObject(localization).frame(width: 300), size: NSSize(width: 300, height: 80))
    }

    private func dump<V: View>(_ name: String, _ view: V, size: NSSize) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        print("DIAG-BEGIN \(name) hosting=\(type(of: hostingView)) frame=\(hostingView.frame)")
        walk(hostingView, depth: 0)
        for x in stride(from: CGFloat(10), through: size.width - 10, by: 50) {
            let point = NSPoint(x: x, y: size.height / 2)
            let hit = hostingView.hitTest(point)
            print("DIAG-HIT \(name) x=\(x) -> \(hit.map { String(describing: type(of: $0)) } ?? "nil")")
        }
        print("DIAG-END \(name)")
    }

    private func walk(_ view: NSView, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        print("DIAG-TREE \(indent)\(type(of: view)) frame=\(view.frame) hidden=\(view.isHidden) alpha=\(view.alphaValue)")
        for child in view.subviews {
            walk(child, depth: depth + 1)
        }
    }

    private func makeLocalization() -> Localization {
        let suiteName = "StatusTrioCoreTests.Diagnostic.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removeTestSuite(named: suiteName)
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.simplifiedChinese))
        return localization
    }
}
