import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

// TEMPORARY DIAGNOSTIC — remove before merging.
@MainActor
final class ZZToolchainDiagnosticTests: XCTestCase {
    func testWhichConditionRealizesTheRowTarget() {
        let localization = makeLocalization()

        probe("detached", localization: localization, inWindow: false, ordered: false)
        probe("window-not-ordered", localization: localization, inWindow: true, ordered: false)
        probe("window-ordered", localization: localization, inWindow: true, ordered: true)
    }

    private func probe(_ name: String, localization: Localization, inWindow: Bool, ordered: Bool) {
        let hostingView = NSHostingView(
            rootView: PreferenceCheckboxRow(
                label: .settingsBatteryShowPercentage,
                isOn: .constant(false)
            )
            .environmentObject(localization)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 40)

        var window: NSWindow?
        if inWindow {
            let created = NSWindow(
                contentRect: hostingView.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            created.contentView = hostingView
            window = created
            if ordered { created.makeKeyAndOrderFront(nil) }
        }

        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let qualifying = hostingView.subviews
            .filter { !$0.isHidden && $0.frame.height > 0 }
            .map { "\(type(of: $0))=\(Int($0.frame.size.width))" }
        print("DIAG-VARIANT \(name) qualifying=\(qualifying)")

        window?.orderOut(nil)
        window?.contentView = nil
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
