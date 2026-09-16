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
        let activationApplication = SettingsActivationPolicyApplicationSpy()
        let controller = SettingsWindowController(
            store: SettingsStore(defaults: defaults),
            statusStore: makeStatusStore(),
            localization: localization,
            activationPolicy: AppActivationPolicy(application: activationApplication)
        )
        XCTAssertNil(controller.window)

        controller.show()
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }

        XCTAssertEqual(window.title, "设置")
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(activationApplication.policies, [.regular])

        localization.setPreference(.language(.german))
        XCTAssertEqual(window.title, "Einstellungen")

        controller.show()
        XCTAssertTrue(controller.window === window)
        XCTAssertEqual(SettingsTab.allCases.last, .preview)
        XCTAssertEqual(activationApplication.policies, [.regular])
    }

    func testClosingWindowReleasesContentForNextPresentation() throws {
        let suiteName = "StatusTrioCoreTests.SettingsWindowRelease.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let activationApplication = SettingsActivationPolicyApplicationSpy()
        let controller = SettingsWindowController(
            store: SettingsStore(defaults: defaults),
            statusStore: makeStatusStore(),
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            activationPolicy: AppActivationPolicy(application: activationApplication)
        )

        controller.show()
        let firstWindow = try XCTUnwrap(controller.window)
        firstWindow.close()
        XCTAssertNil(controller.window)
        XCTAssertEqual(activationApplication.policies, [.regular, .accessory])

        controller.show()
        let secondWindow = try XCTUnwrap(controller.window)
        XCTAssertFalse(firstWindow === secondWindow)
        secondWindow.close()
    }

    func testClosingSettingsKeepsUserSelectedDockPolicyRegular() throws {
        let suiteName = "StatusTrioCoreTests.SettingsDockPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let activationApplication = SettingsActivationPolicyApplicationSpy()
        let policy = AppActivationPolicy(application: activationApplication)
        XCTAssertTrue(policy.setDockIconVisible(true))
        let controller = SettingsWindowController(
            store: SettingsStore(defaults: defaults),
            statusStore: makeStatusStore(),
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            activationPolicy: policy
        )

        controller.show()
        try XCTUnwrap(controller.window).close()

        XCTAssertEqual(activationApplication.policies, [.regular, .regular, .regular])
    }

    private func makeStatusStore() -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: NoopBatteryMonitor(),
            wifiMonitor: SettingsWindowFakeWiFiMonitor(),
            volumeMonitor: SettingsWindowFakeVolumeMonitor()
        )
    }
}

@MainActor
private final class SettingsActivationPolicyApplicationSpy: ApplicationActivationPolicyApplying {
    private(set) var policies: [NSApplication.ActivationPolicy] = []
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        policies.append(activationPolicy)
        guard currentActivationPolicy != activationPolicy else { return false }
        currentActivationPolicy = activationPolicy
        return true
    }
}

@MainActor
private final class NoopBatteryMonitor: BatteryMonitoring {
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
