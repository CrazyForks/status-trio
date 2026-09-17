import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsViewTests: XCTestCase {
    func testSettingsViewDimensionsAndSections() {
        XCTAssertEqual(SettingsView.Section.allCases.count, 7)
        XCTAssertEqual(SettingsView.sidebarWidth, 190)
        XCTAssertEqual(SettingsView.width, 720)
        XCTAssertEqual(SettingsView.height, 530)
    }

    func testSidebarListsEveryStatusElementBeforeTheAppWidePanes() {
        XCTAssertEqual(
            SettingsView.Section.allCases,
            [.appIcon, .battery, .network, .audio, .popover, .general, .about]
        )
        XCTAssertEqual(SettingsView.Section.allCases.first, .appIcon)
    }

    func testStatusElementPanesRenderWithoutCrashing() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        let store = SettingsStore(defaults: suite.defaults)
        let statusStore = makeStatusStore()
        let isDark = Binding.constant(true)

        let panes: [(String, AnyView)] = [
            ("appIcon", AnyView(AppIconSectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: isDark,
                onShowIconGuide: {}
            ))),
            ("battery", AnyView(BatterySectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: isDark
            ))),
            ("network", AnyView(NetworkSectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: isDark
            ))),
            ("audio", AnyView(AudioSectionView(
                store: store,
                statusStore: statusStore,
                previewIsDark: isDark
            ))),
            ("popover", AnyView(PopoverSectionView(
                store: store,
                statusStore: statusStore
            )))
        ]

        for (name, pane) in panes {
            let hostingView = NSHostingView(
                rootView: pane.environmentObject(localization)
            )
            hostingView.frame = NSRect(
                x: 0,
                y: 0,
                width: SettingsView.width - SettingsView.sidebarWidth,
                height: SettingsView.height
            )
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertNotNil(hostingView.subviews, "\(name) pane should host")
        }
    }

    func testSettingsViewHostingViewRendersWithoutCrashing() {
        let name = "StatusTrioCoreTests.SettingsViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { defaults.removePersistentDomain(forName: name) }

        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let store = SettingsStore(defaults: defaults)
        let statusStore = SystemStatusStore(
            batteryMonitor: DummyBatteryMonitor(),
            wifiMonitor: DummyWiFiMonitor(),
            volumeMonitor: DummyVolumeMonitor()
        )

        let view = SettingsView(
            store: store,
            statusStore: statusStore,
            localization: localization,
            onShowIconGuide: {}
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: SettingsView.width, height: SettingsView.height)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertNotNil(hostingView.subviews)
    }

    func testSectionTitlesLocalizedForAllLanguages() {
        let name = "StatusTrioCoreTests.SettingsViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { defaults.removePersistentDomain(forName: name) }

        for lang in AppLanguage.allCases {
            let localization = Localization(defaults: defaults, preferredLanguages: [lang.rawValue])
            for section in SettingsView.Section.allCases {
                let title = section.title(localization)
                XCTAssertFalse(title.isEmpty, "Section \(section) title should not be empty for \(lang)")
            }
        }
    }

    func testRenderArtifactScreenshots() {
        let suite = makeSuite()
        defer { clear(suite) }
        let store = SettingsStore(defaults: suite.defaults)
        let statusStore = makeStatusStore()
        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["zh-Hans"])

        func savePNG<V: View>(_ view: V, size: CGSize, filename: String) {
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            let dir = "/Users/reff/.gemini/antigravity/brain/33cfe6ca-60cf-4cdf-b9f2-6d2e73de178a"
            try? data.write(to: URL(fileURLWithPath: "\(dir)/\(filename)"))
        }

        // 1. Audio Section (Volume visual cards)
        let audioView = LocalizedRootView(localization: localization) {
            AudioSectionView(store: store, statusStore: statusStore, previewIsDark: .constant(true))
                .environmentObject(localization)
                .frame(width: 530, height: 460)
        }
        savePNG(audioView, size: CGSize(width: 530, height: 460), filename: "settings_audio_cards.png")

        // 2. App Icon Section (Placement, Ring Stroke & Dock Background visual cards)
        let appIconView = LocalizedRootView(localization: localization) {
            AppIconSectionView(store: store, statusStore: statusStore, previewIsDark: .constant(true))
                .environmentObject(localization)
                .frame(width: 530, height: 620)
        }
        savePNG(appIconView, size: CGSize(width: 530, height: 620), filename: "settings_appicon_cards.png")

        // 3. Clean Popover (Low Power Mode toggle removed)
        let popoverView = LocalizedRootView(localization: localization) {
            StatusPopoverView(
                store: statusStore,
                settings: store,
                scrollTargets: PopoverScrollTargets(),
                requestWiFiNameAccess: {},
                requestBluetoothAuthorization: {},
                openBatterySettings: {},
                openWiFiSettings: {},
                openLocationSettings: {},
                openBluetoothSettings: {},
                openSettings: {},
                openSoundSettings: {},
                quit: {}
            )
            .environmentObject(localization)
        }
        savePNG(popoverView, size: CGSize(width: 330, height: 350), filename: "popover_reverted_clean.png")

        // 4. Ring Stroke Style Comparison Board (Dark & Light)
        let darkComparison = RingStrokeComparisonBoard(statusStore: statusStore, isDark: true)
        savePNG(darkComparison, size: CGSize(width: 820, height: 640), filename: "ring_stroke_comparison_dark.png")

        let lightComparison = RingStrokeComparisonBoard(statusStore: statusStore, isDark: false)
        savePNG(lightComparison, size: CGSize(width: 820, height: 640), filename: "ring_stroke_comparison_light.png")
    }
}

@MainActor
private func makeSuite() -> (defaults: UserDefaults, name: String) {
    let name = "StatusTrioCoreTests.SettingsViewTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return (defaults, name)
}

private func clear(_ suite: (defaults: UserDefaults, name: String)) {
    suite.defaults.removePersistentDomain(forName: suite.name)
}

@MainActor
private func makeStatusStore() -> SystemStatusStore {
    SystemStatusStore(
        batteryMonitor: DummyBatteryMonitor(),
        wifiMonitor: DummyWiFiMonitor(),
        volumeMonitor: DummyVolumeMonitor()
    )
}

@MainActor
private final class DummyBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class DummyWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() {}
}

@MainActor
private final class DummyVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private struct RingStrokeComparisonBoard: View {
    let statusStore: SystemStatusStore
    let isDark: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 6) {
                Text("StatusTrio 状态环线条粗细方案对比 (Plan B)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isDark ? .white : .black)
                Text("标准 (1.0x)  vs  加粗 (1.25x)  vs  粗体 (1.5x)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isDark ? Color(white: 0.7) : Color(white: 0.3))
            }
            .padding(.top, 12)

            // 3 Columns
            HStack(spacing: 16) {
                styleColumn(style: .light, title: "细 (1.0x)", batteryWidth: "1.6 pt (8.0)", volumeWidth: "1.4 pt (7.0)", dotDiameter: "2.2 pt (11.0)")
                styleColumn(style: .regular, title: "正常 (1.25x)", batteryWidth: "2.0 pt (10.0)", volumeWidth: "1.75 pt (8.75)", dotDiameter: "2.75 pt (13.75)")
                styleColumn(style: .bold, title: "粗 (1.5x)", batteryWidth: "2.4 pt (12.0)", volumeWidth: "2.1 pt (10.5)", dotDiameter: "3.3 pt (16.5)")
            }

            // Real Size 24pt Menu Bar Simulation Strips
            VStack(alignment: .leading, spacing: 10) {
                Text("实际菜单栏 1:1 实时渲染效果 (24 pt 图标)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDark ? .white : .black)

                // Dark Menu Bar row
                menuBarStripRow(isDarkMenu: true)
                // Light Menu Bar row
                menuBarStripRow(isDarkMenu: false)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)))
        }
        .padding(20)
        .frame(width: 820, height: 640)
        .background(isDark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(red: 0.96, green: 0.96, blue: 0.97))
    }

    private func styleColumn(style: RingStrokeStyle, title: String, batteryWidth: String, volumeWidth: String, dotDiameter: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isDark ? .white : .black)

            // Zoomed preview (Arc mode)
            VStack(spacing: 4) {
                Image(nsImage: StatusIconRenderer.image(
                    menuBarStatus: previewStatus,
                    size: 76,
                    options: BatteryIconOptions(showsPercentage: true, showsChargingIndicator: true, usesStatusColors: true, criticalThreshold: 20, ringStrokeScale: style.scale),
                    connectionOptions: ConnectionIconOptions(wifiScale: 1.6),
                    volumeOptions: VolumeIconOptions(displayStyle: .arc, ringStrokeScale: style.scale),
                    appearance: isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
                ))
                .frame(width: 76, height: 76)
                Text("圆弧模式")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(width: 236)
            .background(RoundedRectangle(cornerRadius: 8).fill(isDark ? Color.black.opacity(0.4) : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))

            // Zoomed preview (Dots mode)
            VStack(spacing: 4) {
                Image(nsImage: StatusIconRenderer.image(
                    menuBarStatus: previewStatus,
                    size: 76,
                    options: BatteryIconOptions(showsPercentage: true, showsChargingIndicator: true, usesStatusColors: true, criticalThreshold: 20, ringStrokeScale: style.scale),
                    connectionOptions: ConnectionIconOptions(wifiScale: 1.6),
                    volumeOptions: VolumeIconOptions(displayStyle: .dots, ringStrokeScale: style.scale),
                    appearance: isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
                ))
                .frame(width: 76, height: 76)
                Text("四个点模式")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(width: 236)
            .background(RoundedRectangle(cornerRadius: 8).fill(isDark ? Color.black.opacity(0.4) : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))

            // Specs
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("电池线宽:").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text(batteryWidth).font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                HStack {
                    Text("音量弧线:").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text(volumeWidth).font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                HStack {
                    Text("音量点径:").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text(dotDiameter).font(.system(size: 10, weight: .medium, design: .monospaced))
                }
            }
            .padding(8)
            .frame(width: 236)
            .background(RoundedRectangle(cornerRadius: 6).fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)))
        }
    }

    private func menuBarStripRow(isDarkMenu: Bool) -> some View {
        HStack(spacing: 16) {
            ForEach([RingStrokeStyle.light, .regular, .bold]) { style in
                HStack(spacing: 10) {
                    Text(style == .light ? "细" : style == .regular ? "正常" : "粗")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isDarkMenu ? .white.opacity(0.85) : .black.opacity(0.85))
                        .frame(width: 28, alignment: .leading)

                    // Arc icon
                    VStack(spacing: 2) {
                        Image(nsImage: StatusIconRenderer.image(
                            menuBarStatus: previewStatus,
                            size: 24,
                            options: BatteryIconOptions(showsPercentage: true, showsChargingIndicator: true, usesStatusColors: true, criticalThreshold: 20, ringStrokeScale: style.scale),
                            connectionOptions: ConnectionIconOptions(wifiScale: 1.6),
                            volumeOptions: VolumeIconOptions(displayStyle: .arc, ringStrokeScale: style.scale),
                            appearance: isDarkMenu ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
                        ))
                        Text("圆弧")
                            .font(.system(size: 8))
                            .foregroundStyle(isDarkMenu ? .white.opacity(0.5) : .black.opacity(0.5))
                    }

                    // Dots icon
                    VStack(spacing: 2) {
                        Image(nsImage: StatusIconRenderer.image(
                            menuBarStatus: previewStatus,
                            size: 24,
                            options: BatteryIconOptions(showsPercentage: true, showsChargingIndicator: true, usesStatusColors: true, criticalThreshold: 20, ringStrokeScale: style.scale),
                            connectionOptions: ConnectionIconOptions(wifiScale: 1.6),
                            volumeOptions: VolumeIconOptions(displayStyle: .dots, ringStrokeScale: style.scale),
                            appearance: isDarkMenu ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
                        ))
                        Text("点")
                            .font(.system(size: 8))
                            .foregroundStyle(isDarkMenu ? .white.opacity(0.5) : .black.opacity(0.5))
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 6).fill(isDarkMenu ? Color(red: 0.16, green: 0.16, blue: 0.17) : Color(red: 0.90, green: 0.90, blue: 0.92)))
            }
        }
    }

    private var previewStatus: MenuBarStatus {
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 86,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: WiFiStatus(state: .connected, rssi: -45, ssid: "Home-WiFi"),
            volume: VolumeStatus(scalar: 0.75, isMuted: false, deviceName: "MacBook Pro 扬声器")
        )
        return MenuBarStatus(snapshot: snapshot)
    }
}

