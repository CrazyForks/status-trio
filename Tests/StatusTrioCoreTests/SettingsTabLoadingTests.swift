import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsTabLoadingTests: XCTestCase {
    func testBuildsOnlyTheSelectedTabAtFirst() throws {
        let suite = makeSuite()
        defer { suite.cleanUp() }
        let controller = try makeController(suite)

        _ = controller.view

        let items = controller.tabViewItems
        XCTAssertEqual(items.count, SettingsTab.allCases.count)
        XCTAssertEqual(controller.selectedTabViewItemIndex, 0)
        XCTAssertEqual(items[0].viewController?.isViewLoaded, true)

        for item in items.dropFirst() {
            XCTAssertEqual(
                item.viewController?.isViewLoaded,
                false,
                "\(item.identifier ?? "?") should not be built before it is opened"
            )
        }
    }

    func testSizingLoadsTheSelectedTabOnly() throws {
        let suite = makeSuite()
        defer { suite.cleanUp() }
        let controller = try makeController(suite)
        _ = controller.view

        controller.selectedTabViewItemIndex = 2
        _ = controller.desiredContentSize

        XCTAssertEqual(controller.tabViewItems[2].viewController?.isViewLoaded, true)
        XCTAssertEqual(controller.tabViewItems[1].viewController?.isViewLoaded, false)
    }

    private func makeController(
        _ suite: (defaults: UserDefaults, cleanUp: () -> Void)
    ) throws -> SettingsTabViewController {
        SettingsTabViewController(
            store: SettingsStore(defaults: suite.defaults),
            statusStore: SystemStatusStore(
                batteryMonitor: LazyTabBatteryMonitor(),
                wifiMonitor: LazyTabWiFiMonitor(),
                volumeMonitor: LazyTabVolumeMonitor()
            ),
            localization: Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        )
    }

    private func makeSuite() -> (defaults: UserDefaults, cleanUp: () -> Void) {
        let name = "StatusTrioCoreTests.SettingsTabLoading.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }
}

@MainActor
private final class LazyTabBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class LazyTabWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() {}
}

@MainActor
private final class LazyTabVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
