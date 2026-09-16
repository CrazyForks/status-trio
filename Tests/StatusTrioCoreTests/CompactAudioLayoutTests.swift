import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class CompactAudioLayoutTests: XCTestCase {
    func testAlwaysShowAllPreferenceKeepsDevicesVisible() throws {
        let collapsed = try render(alwaysShowAll: false, language: .english, dark: false)
        let expanded = try render(alwaysShowAll: true, language: .english, dark: false)
        XCTAssertGreaterThan(expanded.height, collapsed.height + 60)
        XCTAssertEqual(collapsed.width, 330, accuracy: 0.5)
        XCTAssertEqual(expanded.width, 330, accuracy: 0.5)
    }

    func testLongDeviceNamesAndLocalizedControlsFitPopoverWidth() throws {
        for language in [AppLanguage.english, .simplifiedChinese, .german, .arabic] {
            let size = try render(alwaysShowAll: false, language: language, dark: true)
            XCTAssertEqual(size.width, 330, accuracy: 0.5)
            XCTAssertLessThan(size.height, 230)
        }
    }

    private func render(alwaysShowAll: Bool, language: AppLanguage, dark: Bool) throws -> NSSize {
        let suite = "StatusTrioCoreTests.CompactAudio.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: [language.rawValue])
        let settings = SettingsStore(defaults: defaults)
        settings.alwaysShowsAllOutputDevices = alwaysShowAll
        let devices = [
            AudioOutputDevice(id: 1, name: "Studio AirPods Pro with a very long device name", isCurrent: true, volume: 0.19, transport: .bluetooth),
            AudioOutputDevice(id: 2, name: "MacBook Pro Speakers", isCurrent: false, volume: 0.51, transport: .builtIn),
            AudioOutputDevice(id: 3, name: "External Display", isCurrent: false, transport: .hdmi)
        ]
        let view = VStack(alignment: .leading, spacing: 12) {
            VolumeControlsView(
                settings: settings,
                volume: VolumeStatus(scalar: 0.19, isMuted: false, deviceName: devices[0].name, outputDevices: devices),
                isEnabled: true,
                onVolumeChange: { _ in }, onToggleMute: {}, onSelectOutputDevice: { _ in }, onOpenSoundSettings: {}
            )
            Divider()
            PopoverFooterView(openSettings: {}, quit: {})
        }
        .padding(14)
        .frame(width: 330)
        // A fixture backdrop makes the transparent offscreen capture inspectable.
        .background(dark ? Color(white: 0.15) : Color(white: 0.96))
        .environmentObject(localization)
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        if let directory = ProcessInfo.processInfo.environment["STATUS_TRIO_LAYOUT_SNAPSHOTS"] {
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try png.write(to: url.appendingPathComponent("audio-\(language.rawValue)-\(dark ? "dark" : "light")-\(alwaysShowAll ? "all" : "collapsed").png"))
        }
        return size
    }
}
