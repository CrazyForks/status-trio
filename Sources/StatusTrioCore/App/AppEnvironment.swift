import AppKit

@MainActor
final class AppEnvironment {
    let store: SystemStatusStore
    let settings: SettingsStore
    let localization: Localization
    let statusBarController: StatusBarController
    let settingsWindowController: SettingsWindowController

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        localization: Localization,
        statusBarController: StatusBarController,
        settingsWindowController: SettingsWindowController
    ) {
        self.store = store
        self.settings = settings
        self.localization = localization
        self.statusBarController = statusBarController
        self.settingsWindowController = settingsWindowController
    }

    static func makeStore(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        connectionMonitor: (any NetworkConnectionMonitoring)? = nil,
        volumeMonitor: any VolumeMonitoring
    ) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: batteryMonitor,
            wifiMonitor: wifiMonitor,
            connectionMonitor: connectionMonitor,
            volumeMonitor: volumeMonitor
        )
    }

    static func live() -> AppEnvironment {
        let store = makeStore(
            batteryMonitor: BatteryMonitor(),
            wifiMonitor: WiFiMonitor(),
            connectionMonitor: NetworkConnectionMonitor(),
            volumeMonitor: VolumeMonitor(outputController: CoreAudioOutputController())
        )
        let defaults = PreviewAppIdentity.userDefaults
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(defaults: defaults)
        let settingsWindowController = SettingsWindowController(
            store: settings,
            statusStore: store,
            localization: localization
        )
        let controller = StatusBarController(
            store: store,
            settings: settings,
            localization: localization,
            openSettings: { settingsWindowController.show() },
            quitAction: { NSApplication.shared.terminate(nil) }
        )
        return AppEnvironment(
            store: store,
            settings: settings,
            localization: localization,
            statusBarController: controller,
            settingsWindowController: settingsWindowController
        )
    }
}
