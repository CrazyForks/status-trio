import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testShowCreatesReusesAndLocalizesSingleWindow() throws {
        let suiteName = "StatusTrioCoreTests.SettingsWindow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.simplifiedChinese))
        let statusStore = SystemStatusStore(
            batteryMonitor: SettingsWindowFakeBatteryMonitor(),
            wifiMonitor: SettingsWindowFakeWiFiMonitor(),
            volumeMonitor: SettingsWindowFakeVolumeMonitor()
        )
        let controller = SettingsWindowController(
            store: SettingsStore(defaults: defaults),
            statusStore: statusStore,
            localization: localization
        )
        XCTAssertNil(controller.window)

        controller.show()
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }

        XCTAssertEqual(window.title, "设置")
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.isVisible)

        localization.setPreference(.language(.german))
        XCTAssertEqual(window.title, "Einstellungen")

        controller.show()
        XCTAssertTrue(controller.window === window)
        XCTAssertEqual(SettingsTab.allCases.last, .preview)
    }
}

@MainActor
private final class SettingsWindowFakeBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
}

@MainActor
private final class SettingsWindowFakeWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private let continuation: AsyncStream<WiFiStatus>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
    func requestNameAccess() {}
}

@MainActor
private final class SettingsWindowFakeVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    private let continuation: AsyncStream<VolumeStatus>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
}
