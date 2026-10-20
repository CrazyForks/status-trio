import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusBarMemoryPressureTests: XCTestCase {
    func testTrimForMemoryPressureKeepsVisiblePopoverContent() throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }

        harness.controller.togglePopover(anchoredAtScreenPoint: harness.anchorPoint)
        let popover = harness.controller.popoverForTesting
        XCTAssertTrue(popover.isShown)
        let content = try XCTUnwrap(popover.contentViewController)

        harness.controller.trimForMemoryPressure()

        XCTAssertTrue(popover.isShown)
        XCTAssertTrue(popover.contentViewController === content)
    }

    func testTrimForMemoryPressureReleasesClosedPopoverContent() throws {
        let harness = try StatusBarPressureHarness()
        defer { harness.cleanUp() }

        harness.controller.togglePopover(anchoredAtScreenPoint: harness.anchorPoint)
        let popover = harness.controller.popoverForTesting
        XCTAssertTrue(popover.isShown)
        XCTAssertNotNil(popover.contentViewController)

        popover.close()
        waitUntilClosed(popover)
        XCTAssertFalse(popover.isShown)
        XCTAssertNotNil(
            popover.contentViewController,
            "Closing normally retains content for the existing rapid-reopen path"
        )

        harness.controller.trimForMemoryPressure()

        XCTAssertNil(popover.contentViewController)
    }

    private func waitUntilClosed(_ popover: NSPopover) {
        let deadline = Date().addingTimeInterval(2)
        while popover.isShown, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }
}

@MainActor
private final class StatusBarPressureHarness {
    let defaults: UserDefaults
    let store: SystemStatusStore
    let iconPresentation: IconPresentationViewModel
    let controller: StatusBarController
    let anchorPoint: NSPoint
    private let suiteName: String

    init() throws {
        suiteName = "StatusTrioCoreTests.StatusBarMemoryPressure.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw HarnessError.missingDefaults
        }
        self.defaults = defaults
        let settings = SettingsStore(defaults: defaults)
        store = AppEnvironment.makeStore(
            batteryMonitor: PressureBatteryMonitor(),
            wifiMonitor: PressureWiFiMonitor(),
            volumeMonitor: PressureVolumeMonitor()
        )
        iconPresentation = makeTestIconPresentation(store: store, settings: settings)
        controller = StatusBarController(
            store: store,
            settings: settings,
            iconPresentation: iconPresentation,
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            renderMenuBarBase: { _, _, _, _ in nil },
            renderMenuBarOverlay: { _, _, _, _, _ in nil }
        )
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_024, height: 768)
        anchorPoint = NSPoint(x: visibleFrame.midX, y: visibleFrame.minY + 10)
        iconPresentation.start()
    }

    func cleanUp() {
        controller.popoverForTesting.close()
        controller.setVisible(false)
        iconPresentation.stop()
        store.stop()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private enum HarnessError: Error {
    case missingDefaults
}

@MainActor
private final class PressureBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class PressureWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class PressureVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
}
