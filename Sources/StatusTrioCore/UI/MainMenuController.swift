import AppKit
import Combine

@MainActor
final class MainMenuController: NSObject {
    private let activationPolicy: AppActivationPolicy
    private let localization: Localization
    private let openSettings: () -> Void
    private let notificationCenter: NotificationCenter
    private var cancellables: Set<AnyCancellable> = []
    private var activationObservers: [NSObjectProtocol] = []
    private var isRegularApp = false
    private var isAppActive = false

    init(
        activationPolicy: AppActivationPolicy,
        localization: Localization,
        notificationCenter: NotificationCenter = .default,
        openSettings: @escaping () -> Void
    ) {
        self.activationPolicy = activationPolicy
        self.localization = localization
        self.notificationCenter = notificationCenter
        self.openSettings = openSettings
        super.init()
    }

    func start() {
        isAppActive = NSApplication.shared.isActive

        // Only a regular *and* active app owns the menu bar. Building it earlier
        // would load AppKit's menu machinery for nothing; leaving it installed
        // while another app is frontmost is equally pointless.
        activationPolicy.$isRegularApp
            .removeDuplicates()
            .sink { [weak self] isRegular in
                guard let self else { return }
                self.isRegularApp = isRegular
                self.updateInstallation()
            }
            .store(in: &cancellables)

        observe(NSApplication.didBecomeActiveNotification, isActive: true)
        observe(NSApplication.didResignActiveNotification, isActive: false)

        localization.$resolvedLanguage
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // @Published emits before the stored value changes, so rebuild
                // on the next main-actor turn to pick up the new language.
                Task { @MainActor [weak self] in
                    self?.install()
                }
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        activationObservers.forEach(notificationCenter.removeObserver)
        activationObservers.removeAll()
        setInstalled(false)
    }

    @objc private func handleOpenSettings() {
        openSettings()
    }

    private func install() {
        NSApplication.shared.mainMenu = AppMainMenu.make(
            localization: localization,
            target: self,
            openSettingsAction: #selector(handleOpenSettings)
        )
    }

    private func setInstalled(_ isInstalled: Bool) {
        guard isInstalled else {
            NSApplication.shared.mainMenu = nil
            return
        }
        install()
    }

    private func updateInstallation() {
        setInstalled(isRegularApp && isAppActive)
    }

    private func observe(_ name: Notification.Name, isActive: Bool) {
        activationObservers.append(notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isAppActive = isActive
                self.updateInstallation()
            }
        })
    }
}
