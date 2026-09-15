import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct AppIconControllerTests {
    @Test func dockOnlyActivatesAndRendersBeforeHidingMenuBar() throws {
        let harness = try AppIconControllerHarness()
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.events.removeAll()

        harness.settings.appIconPlacement = .dock

        #expect(harness.log.events == ["policy:regular", "dock:image", "menu:false"])
    }

    @Test func rejectedDockActivationKeepsMenuBarVisible() throws {
        let harness = try AppIconControllerHarness(acceptsActivationPolicy: false)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.events.removeAll()

        harness.settings.appIconPlacement = .dock

        #expect(harness.log.events == ["policy:regular", "menu:true"])
    }

    @Test func menuBarOnlyRestoresMenuBeforeRemovingDock() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.events.removeAll()

        harness.settings.appIconPlacement = .menuBar

        #expect(harness.log.events == ["menu:true", "dock:nil", "policy:accessory"])
    }

    @Test func bothPlacementKeepsMenuBarVisible() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .both)
        defer { harness.cleanUp() }
        harness.log.events.removeAll()

        harness.controller.start()

        #expect(harness.log.events == ["policy:regular", "dock:image", "menu:true"])
    }

    @Test func hiddenDockDoesNotRenderStatusChanges() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .menuBar)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.renderCount = 0

        harness.publishDifferentSnapshot()
        try await Task.sleep(for: .milliseconds(900))

        #expect(harness.log.renderCount == 0)
    }

    @Test func visibleDockRendersStatusChanges() async throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        harness.log.renderCount = 0

        harness.publishDifferentSnapshot()
        try await Task.sleep(for: .milliseconds(900))

        #expect(harness.log.renderCount == 1)
    }

    @Test func stopRestoresBundledDockIcon() throws {
        let harness = try AppIconControllerHarness(initialPlacement: .dock)
        defer { harness.cleanUp() }
        harness.controller.start()
        #expect(harness.application.applicationIconImage != nil)

        harness.controller.stop()

        #expect(harness.application.applicationIconImage == nil)
        harness.log.events.removeAll()
        harness.controller.stop()
        #expect(harness.log.events.isEmpty)
    }
}

@MainActor
private final class AppIconControllerHarness {
    let log = AppIconEventLog()
    let application: AppIconApplicationSpy
    let activationPolicy: AppActivationPolicy
    let settings: SettingsStore
    let store: SystemStatusStore
    let controller: AppIconController

    private let suiteName: String
    private let defaults: UserDefaults
    private let battery = ControllableBatteryMonitor()

    init(
        initialPlacement: AppIconPlacement = .menuBar,
        acceptsActivationPolicy: Bool = true
    ) throws {
        suiteName = "StatusTrioCoreTests.AppIconController.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw AppIconHarnessError.missingDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        self.defaults = defaults

        let log = self.log
        let application = AppIconApplicationSpy(
            log: log,
            acceptsActivationPolicy: acceptsActivationPolicy
        )
        self.application = application

        let settings = SettingsStore(defaults: defaults)
        settings.appIconPlacement = initialPlacement
        self.settings = settings

        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: NoopWiFiMonitor(),
            volumeMonitor: NoopVolumeMonitor(),
            refreshInterval: .seconds(60)
        )
        self.store = store

        let activationPolicy = AppActivationPolicy(application: application)
        self.activationPolicy = activationPolicy

        controller = AppIconController(
            store: store,
            settings: settings,
            activationPolicy: activationPolicy,
            application: application,
            setMenuBarVisible: { isVisible in
                log.events.append(isVisible ? "menu:true" : "menu:false")
            },
            renderDockIcon: { _, _, _ in
                log.renderCount += 1
                return NSImage(size: NSSize(width: 512, height: 512))
            }
        )

        store.start()
    }

    func publishDifferentSnapshot() {
        battery.send(BatteryStatus(
            rawPercentage: 42,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        ))
    }

    func cleanUp() {
        store.stop()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private enum AppIconHarnessError: Error {
    case missingDefaultsSuite
}

@MainActor
private final class AppIconEventLog {
    var events: [String] = []
    var renderCount = 0
}

@MainActor
private final class AppIconApplicationSpy: ApplicationActivationPolicyApplying, ApplicationDockIconApplying {
    private let log: AppIconEventLog
    private let acceptsActivationPolicy: Bool

    private(set) var applicationIconImage: NSImage?

    init(log: AppIconEventLog, acceptsActivationPolicy: Bool) {
        self.log = log
        self.acceptsActivationPolicy = acceptsActivationPolicy
    }

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        log.events.append(activationPolicy == .regular ? "policy:regular" : "policy:accessory")
        return acceptsActivationPolicy
    }

    func setApplicationIconImage(_ image: NSImage?) {
        applicationIconImage = image
        log.events.append(image == nil ? "dock:nil" : "dock:image")
    }
}

@MainActor
private final class ControllableBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}

    func send(_ status: BatteryStatus) {
        continuation.yield(status)
    }
}

@MainActor
private final class NoopWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() {}
}

@MainActor
private final class NoopVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
