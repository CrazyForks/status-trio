import AppKit
import Foundation

@MainActor
final class SystemIconAppearanceMonitor {
    /// Undocumented but exported by AppKit; registered by name so the app never
    /// links against a private symbol.
    static let didChangeNotificationName = Notification.Name(
        "NSWorkspaceIconAppearanceConfigurationDidChangeNotification"
    )

    private let readTheme: () -> SystemIconAppearanceTheme
    private let notificationCenter: NotificationCenter
    private var lastTheme: SystemIconAppearanceTheme
    private var observers: [NSObjectProtocol] = []

    var onChange: ((SystemIconAppearanceTheme) -> Void)?

    init(
        readTheme: @escaping () -> SystemIconAppearanceTheme = {
            SystemIconAppearanceReader.current()
        },
        notificationCenter: NotificationCenter = .default
    ) {
        self.readTheme = readTheme
        self.notificationCenter = notificationCenter
        self.lastTheme = readTheme()
    }

    func start() {
        guard observers.isEmpty else { return }
        observe(Self.didChangeNotificationName)
        observe(NSApplication.didBecomeActiveNotification)
    }

    func stop() {
        observers.forEach(notificationCenter.removeObserver)
        observers.removeAll()
    }

    /// Re-reads the system style and reports it when it actually changed.
    func refresh() {
        let theme = readTheme()
        guard theme != lastTheme else { return }
        lastTheme = theme
        onChange?(theme)
    }

    private func observe(_ name: Notification.Name) {
        observers.append(notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        })
    }
}
