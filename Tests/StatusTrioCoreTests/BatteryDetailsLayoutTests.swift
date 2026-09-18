import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class BatteryDetailsLayoutTests: XCTestCase {
    func testBatteryPageFitsPopoverInEnglishAndChinese() async throws {
        for language in [AppLanguage.english, .simplifiedChinese] {
            let power = try await render(language: language, available: true)
            let unavailable = try await render(language: language, available: false)
            let collecting = try await render(language: language, available: false, collecting: true)
            XCTAssertLessThan(power.height, 380)
            XCTAssertLessThan(unavailable.height, power.height)
            XCTAssertLessThan(collecting.height, power.height)
            _ = try await renderSummary(language: language, isPresent: true)
            _ = try await renderSummary(language: language, isPresent: false)
        }
    }

    private func renderSummary(language: AppLanguage, isPresent: Bool) async throws -> NSSize {
        let suite = "StatusTrioCoreTests.BatterySummary.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        let battery = BatteryStatus(rawPercentage: isPresent ? 80 : nil, isPresent: isPresent,
                                    isCharging: false, isLowPowerMode: false,
                                    isConnectedToPower: false)
        let view = BatteryStatusView(battery: battery, onOpenBatteryDetails: {},
                                     onOpenBatterySettings: {})
            .padding(14)
            .frame(width: 330)
            .background(Color(white: 0.96))
            .environmentObject(localization)
            .environment(\.colorScheme, .light)
        return try await capture(view, named: "battery-\(language.rawValue)-row-\(isPresent ? "present" : "absent")")
    }

    /// Mounts the view, waits for SwiftUI's appearance task to deliver the
    /// fixture, then records the settled fitting size and an optional snapshot.
    @discardableResult
    private func capture<V: View>(_ view: V, named name: String) async throws -> NSSize {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        // Allow SwiftUI's appearance task and the serial reader to publish the fixture.
        try await Task.sleep(for: .milliseconds(50))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        if let directory = ProcessInfo.processInfo.environment["STATUS_TRIO_BATTERY_SNAPSHOTS"] {
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try png.write(to: url.appendingPathComponent("\(name).png"))
        }
        return size
    }

    private func render(language: AppLanguage, available: Bool,
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
        let view = BatteryDetailsView(
            controller: controller, battery: battery,
            onBack: {}, onOpenBatterySettings: {})
            .padding(14)
            .frame(width: 330)
            .background(Color(white: 0.96))
            .environmentObject(localization)
            .environment(\.colorScheme, .light)
        // Allow SwiftUI's appearance task and the serial reader to publish the fixture.
        let state = available ? "power" : (collecting ? "collecting" : "unavailable")
        let size = try await capture(view, named: "battery-\(language.rawValue)-page-\(state)")
        XCTAssertEqual(size.width, 330, accuracy: 0.5)
        return size
    }
}
