import AppKit
import Combine
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = NSSize(
        width: IconGuideOnboardingView.contentWidth,
        height: 700
    )

    private let settings: SettingsStore
    private let localization: Localization
    private let activationPolicy: AppActivationPolicy
    private let backgroundUITesting: BackgroundUITestingConfiguration
    private let presentWindow: @MainActor (NSWindow, SettingsWindowPresentation) -> Void
    private var localizationCancellable: AnyCancellable?
    private var ownsActivationPolicy = false
    private var previewVisibilityObserver: ((Bool) -> Void)?
    private var isPreviewWindowVisible = false
    var openSettings: (() -> Void)?

    init(
        settings: SettingsStore,
        localization: Localization,
        activationPolicy: AppActivationPolicy,
        backgroundUITesting: BackgroundUITestingConfiguration = .disabled,
        presentWindow: @escaping @MainActor (NSWindow, SettingsWindowPresentation) -> Void = {
            window, presentation in presentation.present(window)
        }
    ) {
        self.settings = settings
        self.localization = localization
        self.activationPolicy = activationPolicy
        self.backgroundUITesting = backgroundUITesting
        self.presentWindow = presentWindow
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

    func startPreviewResourceObservation(_ observer: @escaping (Bool) -> Void) {
        guard previewVisibilityObserver == nil else { return }
        previewVisibilityObserver = observer
        observer(isPreviewWindowVisible)
    }

    func stopPreviewResourceObservation() {
        guard previewVisibilityObserver != nil else { return }
        previewVisibilityObserver = nil
    }

    @discardableResult
    func showIfNeeded() -> Bool {
        guard IconGuideOnboardingPolicy.shouldPresentGuide(settings: settings) else {
            return false
        }
        show()
        return true
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        applyLocalization()
        if backgroundUITesting.isEnabled {
            BackgroundUIWindowPlacement.position(window, display: backgroundUITesting.display)
        } else {
            enterActivationPolicyIfNeeded()
        }
        presentWindow(window, backgroundUITesting.isEnabled ? .background : .activating)
        setPreviewWindowVisible(true)
    }

    func windowWillClose(_ notification: Notification) {
        leaveActivationPolicyIfNeeded()
        setPreviewWindowVisible(false)
        window?.contentView = nil
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let rootView = LocalizedRootView(localization: localization) {
            IconGuideOnboardingView(
                settings: settings,
                onCustomize: { [weak self] in self?.handleCustomize() },
                onDone: { [weak self] in self?.window?.close() }
            )
        }

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: Self.contentSize)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.delegate = self
        window.isReleasedWhenClosed = true
        window.contentMinSize = NSSize(
            width: IconGuideOnboardingView.contentWidth,
            height: 420
        )
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
        return window
    }

    private func handleCustomize() {
        window?.close()
        openSettings?()
    }

    private func applyLocalization(language: AppLanguage? = nil) {
        let language = language ?? localization.resolvedLanguage
        window?.title = localization.string(.guideTitle, language: language)
        window?.contentView?.userInterfaceLayoutDirection = language.nsLayoutDirection
    }

    private func enterActivationPolicyIfNeeded() {
        guard !ownsActivationPolicy else { return }
        ownsActivationPolicy = true
        activationPolicy.enterTemporaryRegularMode()
    }

    private func leaveActivationPolicyIfNeeded() {
        guard ownsActivationPolicy else { return }
        ownsActivationPolicy = false
        activationPolicy.leaveTemporaryRegularMode()
    }

    private func setPreviewWindowVisible(_ visible: Bool) {
        guard isPreviewWindowVisible != visible else { return }
        isPreviewWindowVisible = visible
        previewVisibilityObserver?(visible)
    }
}
