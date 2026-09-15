import AppKit
import Combine

@MainActor
final class MainMenuController: NSObject {
    private let activationPolicy: AppActivationPolicy
    private let localization: Localization
    private let openSettings: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(
        activationPolicy: AppActivationPolicy,
        localization: Localization,
        openSettings: @escaping () -> Void
    ) {
        self.activationPolicy = activationPolicy
        self.localization = localization
        self.openSettings = openSettings
        super.init()
    }

    func start() {
        // A regular app owns the menu bar; an accessory app must not, otherwise
        // its menu would replace the frontmost app's while a popover is open.
        activationPolicy.$isRegularApp
            .removeDuplicates()
            .sink { [weak self] isRegular in
                self?.setInstalled(isRegular)
            }
            .store(in: &cancellables)

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
}
