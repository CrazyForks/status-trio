import AppKit
import SwiftUI

@MainActor
final class SettingsTabViewController: NSTabViewController {
    static let contentWidth: CGFloat = 450

    private let store: SettingsStore
    private let statusStore: SystemStatusStore
    private let localization: Localization

    init(
        store: SettingsStore,
        statusStore: SystemStatusStore,
        localization: Localization
    ) {
        self.store = store
        self.statusStore = statusStore
        self.localization = localization
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildTabs()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateWindowSize()
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        Task { @MainActor [weak self] in
            self?.updateWindowSize()
        }
    }

    func applyLocalization(_ language: AppLanguage) {
        for tab in SettingsTab.allCases {
            guard let item = tabViewItems.first(where: {
                ($0.identifier as? String) == tab.rawValue
            }) else {
                continue
            }
            item.label = localization.string(tab.titleKey, language: language)
            item.toolTip = item.label
        }

        view.needsLayout = true
        updateWindowSize()
    }

    var desiredContentSize: NSSize {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex),
              let currentView = tabViewItems[selectedTabViewItemIndex].viewController?.view else {
            return NSSize(width: Self.contentWidth, height: 220)
        }

        currentView.frame.size.width = Self.contentWidth
        currentView.layoutSubtreeIfNeeded()
        let fittingSize = currentView.fittingSize
        return NSSize(
            width: Self.contentWidth,
            height: max(150, ceil(fittingSize.height))
        )
    }

    private func buildTabs() {
        for tab in SettingsTab.allCases {
            let viewController = SettingsVisualEffectViewController(
                localization: localization
            ) {
                SettingsDetailView(
                    tab: tab,
                    store: store,
                    statusStore: statusStore
                )
            }
            viewController.view.frame.size.width = Self.contentWidth

            let item = NSTabViewItem(viewController: viewController)
            item.identifier = tab.rawValue
            item.label = localization.string(tab.titleKey)
            item.toolTip = item.label
            item.image = NSImage(
                systemSymbolName: tab.systemImage,
                accessibilityDescription: nil
            )
            addTabViewItem(item)
        }

        selectedTabViewItemIndex = 0
    }

    private func updateWindowSize() {
        guard let window = view.window else { return }
        let contentSize = desiredContentSize
        guard contentSize.height > 0 else { return }

        let targetFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        let currentFrame = window.frame
        let targetOrigin = NSPoint(
            x: currentFrame.minX,
            y: currentFrame.maxY - targetFrameSize.height
        )

        window.setFrame(
            NSRect(origin: targetOrigin, size: targetFrameSize),
            display: true
        )
    }
}
