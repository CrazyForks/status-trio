import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let store: SettingsStore
    private let statusStore: SystemStatusStore
    private let localization: Localization
    private var localizationCancellable: AnyCancellable?
    private var tabController: SettingsTabViewController?
    private var ownsActivationPolicy = false

    init(
        store: SettingsStore,
        statusStore: SystemStatusStore,
        localization: Localization
    ) {
        self.store = store
        self.statusStore = statusStore
        self.localization = localization
        super.init(window: nil)

        localizationCancellable = localization.$resolvedLanguage
            .removeDuplicates()
            .sink { [weak self] language in
                self?.applyLocalization(language: language)
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        applyLocalization()
        enterActivationPolicyIfNeeded()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        leaveActivationPolicyIfNeeded()
    }

    private func makeWindow() -> NSWindow {
        let tabController = SettingsTabViewController(
            store: store,
            statusStore: statusStore,
            localization: localization
        )
        self.tabController = tabController

        _ = tabController.view
        let contentSize = tabController.desiredContentSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = tabController
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .preference
        window.titlebarSeparatorStyle = .none
        window.setFrameAutosaveName("SettingsWindow.ToolbarTabs.v2")
        window.center()
        window.setContentSize(contentSize)
        return window
    }

    private func applyLocalization(language: AppLanguage? = nil) {
        let language = language ?? localization.resolvedLanguage
        window?.title = localization.string(.settingsTitle, language: language)
        window?.contentView?.userInterfaceLayoutDirection = language.nsLayoutDirection
        tabController?.applyLocalization(language)
    }

    private func enterActivationPolicyIfNeeded() {
        guard !ownsActivationPolicy else { return }
        ownsActivationPolicy = true
        AppActivationPolicy.enter()
    }

    private func leaveActivationPolicyIfNeeded() {
        guard ownsActivationPolicy else { return }
        ownsActivationPolicy = false
        AppActivationPolicy.leave()
    }
}
