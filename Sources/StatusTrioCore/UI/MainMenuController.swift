import AppKit
import Combine

@MainActor
final class MainMenuController: NSObject {
    private let localization: Localization
    private let openSettings: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(localization: Localization, openSettings: @escaping () -> Void) {
        self.localization = localization
        self.openSettings = openSettings
        super.init()
    }

    func start() {
        install()
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
        NSApplication.shared.mainMenu = nil
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
}
