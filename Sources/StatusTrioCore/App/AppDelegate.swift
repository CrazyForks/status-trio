import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var singleInstanceGuard: SingleInstanceGuard?
    private let updaterManager = UpdaterManager.shared

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard let singleInstanceGuard = SingleInstanceGuard() else {
            NSApplication.shared.terminate(nil)
            return
        }
        self.singleInstanceGuard = singleInstanceGuard

        let environment = AppEnvironment.live()
        self.environment = environment
        updaterManager.start()
        environment.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        environment?.stop()
    }

    public func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        environment?.settingsWindowController.show()
        return false
    }
}
