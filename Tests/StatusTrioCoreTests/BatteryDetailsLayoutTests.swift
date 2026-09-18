import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class BatteryDetailsLayoutTests: XCTestCase {
    func testExpandedDetailsFitPopoverInEnglishAndChinese() async throws {
        for language in [AppLanguage.english, .simplifiedChinese] {
            let collapsed = try await render(language: language, expanded: false, available: true)
            let expanded = try await render(language: language, expanded: true, available: true)
            let unavailable = try await render(language: language, expanded: true, available: false)
            let collecting = try await render(language: language, expanded: true, available: false, collecting: true)
            XCTAssertGreaterThan(expanded.height, collapsed.height + 100)
            XCTAssertLessThan(expanded.height, 380)
            XCTAssertLessThan(unavailable.height, expanded.height)
            XCTAssertLessThan(collecting.height, expanded.height)
        }
    }

    private func render(language: AppLanguage, expanded: Bool, available: Bool,
                        collecting: Bool = false) async throws -> NSSize {
        let suite = "StatusTrioCoreTests.BatteryDetails.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        let fixture = BatteryDetails(
            remainingMinutes: available ? 121 : nil,
            cycleCount: 43,
            power: available ? BatteryPowerSample(volts: 12.279, amps: -1.528, updatedAt: Date()) : nil,
            powerAvailability: collecting ? .collecting : .available)
        let controller = BatteryDetailsController { _, _ in fixture }
        defer { controller.deactivate() }
        let battery = BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: false,
                                    isLowPowerMode: false, isConnectedToPower: false)
        let view = BatteryStatusView(battery: battery, detailsController: controller,
                                    isPresented: true, onOpenBatterySettings: {}, showsDetailsInitially: expanded)
            .padding(14)
            .frame(width: 330)
            .background(Color(white: 0.96))
            .environmentObject(localization)
            .environment(\.colorScheme, .light)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        // Allow SwiftUI's appearance task and the serial reader to publish the fixture.
        try await Task.sleep(for: .milliseconds(50))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(size.width, 330, accuracy: 0.5)
        if let directory = ProcessInfo.processInfo.environment["STATUS_TRIO_BATTERY_SNAPSHOTS"] {
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let state = available ? "power" : (collecting ? "collecting" : "unavailable")
            try png.write(to: url.appendingPathComponent("battery-\(language.rawValue)-\(expanded ? "expanded" : "collapsed")-\(state).png"))
        }
        return size
    }
}
