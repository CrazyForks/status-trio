import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

// TEMPORARY DIAGNOSTIC — remove before merging.
@MainActor
final class ZZToolchainDiagnosticTests: XCTestCase {
    func testDumpTreesWithWindow() {
        NSApplication.shared.setActivationPolicy(.accessory)
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
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let widths = hostingView.subviews
            .filter { !$0.isHidden && $0.frame.height > 0 }
            .map { "\(type(of: $0))=\($0.frame.size)" }
        print("DIAG-WINDOW \(name) qualifying=\(widths)")
        window.orderOut(nil)
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
