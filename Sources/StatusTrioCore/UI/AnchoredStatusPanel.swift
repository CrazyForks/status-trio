import AppKit
import Combine
import SwiftUI

/// The status panel window.
///
/// Issue #186 removes the arrow that `NSPopover` draws. AppKit has no public API
/// to hide it, so the panel is now a borderless `NSPanel` that reproduces the
/// popover's behaviour itself:
///
/// - native Liquid Glass on macOS 26+ (`NSGlassEffectView`), the pre-Tahoe
///   `NSVisualEffectView` material on macOS 13–25, and a solid fill when the
///   user has Reduce Transparency on;
/// - anchored placement with the same edge semantics, gap, screen clamping and
///   flip-to-the-other-side fallback as `NSPopover`;
/// - outside-click dismissal, Escape, app deactivation and the status item's
///   own toggle all close it.
///
/// The panel keeps `NSWindow.contentViewController` as its content owner so the
/// controller's five-second retention contract still applies unchanged.
@MainActor
final class AnchoredStatusPanel: NSPanel {
    static let didCloseNotification = Notification.Name(
        "StatusTrioAnchoredStatusPanelDidClose"
    )
    static let cornerRadius: CGFloat = 16

    /// Called once for every close, on the main actor, after the panel is off
    /// screen. Replaces `NSPopoverDelegate.popoverDidClose(_:)`.
    var onClose: (() -> Void)?

    private var anchor: StatusPanelAnchor?
    private var anchorView: NSView?
    private var anchorRectInView: NSRect = .zero
    private var preferredEdge: NSRectEdge = .minY
    private var showCancellables: Set<AnyCancellable> = []

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        isMovable = false
        isMovableByWindowBackground = false
    }

    /// A borderless, non-activating panel is only key when it says so.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var isShown: Bool { isVisible }

    // MARK: - Content

    /// Wraps the SwiftUI hosting controller in the panel's glass background and
    /// keeps the window sized to the content's intrinsic size.
    func installContent(_ hostingController: NSViewController) {
        let controller = StatusPanelContentViewController(hostingController: hostingController)
        controller.onIntrinsicSizeChange = { [weak self] size in
            self?.applyContentSize(size)
        }
        contentViewController = controller
    }

    // MARK: - Presentation

    func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {
        anchorView = view
        anchorRectInView = rect
        self.preferredEdge = preferredEdge
        anchor = StatusPanelAnchor(
            screenRect: Self.screenRect(for: rect, in: view),
            preferredEdge: preferredEdge
        )
        installShowObservers()

        if let content = contentViewController as? StatusPanelContentViewController {
            let size = content.intrinsicContentSize
            if size.width > 0, size.height > 0 {
                setFrame(placementFrame(for: size), display: false)
            }
        }
        orderFrontRegardless()
    }

    override func performClose(_ sender: Any?) {
        close()
    }

    override func close() {
        // A hidden window has nothing to tear down; callers rely on `isShown`
        // before they act on a close.
        guard isVisible else { return }
        removeShowObservers()
        super.close()
        NotificationCenter.default.post(name: Self.didCloseNotification, object: self)
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            performClose(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }

    // MARK: - Placement

    private func applyContentSize(_ size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
        let rounded = NSSize(width: ceil(size.width), height: ceil(size.height))
        guard abs(frame.width - rounded.width) >= 0.5 || abs(frame.height - rounded.height) >= 0.5
        else { return }
        setFrame(placementFrame(for: rounded), display: true)
    }

    private func reposition() {
        guard isVisible else { return }
        let target = placementFrame(for: frame.size)
        guard target != frame else { return }
        setFrame(target, display: true)
    }

    private func placementFrame(for contentSize: NSSize) -> NSRect {
        guard let currentAnchor = currentAnchor() else {
            return NSRect(origin: frame.origin, size: contentSize)
        }
        return StatusPanelPlacement.frame(
            contentSize: contentSize,
            anchor: currentAnchor,
            screens: NSScreen.screens.map { StatusPanelScreen($0) }
        )
    }

    private func currentAnchor() -> StatusPanelAnchor? {
        if let anchorView, let window = anchorView.window {
            let rectInWindow = anchorView.convert(anchorRectInView, to: nil)
            return StatusPanelAnchor(
                screenRect: window.convertToScreen(rectInWindow),
                preferredEdge: preferredEdge
            )
        }
        return anchor
    }

    private static func screenRect(for rect: NSRect, in view: NSView) -> NSRect {
        guard let window = view.window else { return view.convert(rect, to: nil) }
        return window.convertToScreen(view.convert(rect, to: nil))
    }

    // MARK: - Lifecycle observers

    private func installShowObservers() {
        removeShowObservers()
        let center = NotificationCenter.default
        center.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reposition()
            }
            .store(in: &showCancellables)
        center.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isVisible else { return }
                self.performClose(nil)
            }
            .store(in: &showCancellables)
    }

    private func removeShowObservers() {
        showCancellables.removeAll()
    }
}

// MARK: - Content view controller

/// Hosts the SwiftUI content inside the panel's background. `viewDidLayout` is
/// the sizing signal: `NSHostingView` reports the SwiftUI content's ideal size
/// through `fittingSize`, and the panel follows it for expanding rows and
/// detail pages.
@MainActor
final class StatusPanelContentViewController: NSViewController {
    let hostingController: NSViewController
    var onIntrinsicSizeChange: ((NSSize) -> Void)?

    private var backgroundView: NSView?
    private var lastReportedSize: NSSize = .zero

    init(hostingController: NSViewController) {
        self.hostingController = hostingController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        view = container

        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        if #available(macOS 26.0, *), !reduceTransparency {
            let glass = NSGlassEffectView(frame: container.bounds)
            glass.style = .regular
            glass.cornerRadius = AnchoredStatusPanel.cornerRadius
            glass.autoresizingMask = [.width, .height]
            glass.contentView = hostingController.view
            container.addSubview(glass)
            backgroundView = glass
        } else {
            let background: NSView
            if reduceTransparency {
                let solid = NSView(frame: container.bounds)
                solid.wantsLayer = true
                solid.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                solid.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
                solid.layer?.masksToBounds = true
                background = solid
            } else {
                let effect = NSVisualEffectView(frame: container.bounds)
                effect.material = .popover
                effect.blendingMode = .behindWindow
                effect.state = .active
                effect.wantsLayer = true
                effect.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
                effect.layer?.masksToBounds = true
                background = effect
            }
            background.autoresizingMask = [.width, .height]
            container.addSubview(background)
            backgroundView = background

            hostingController.view.frame = container.bounds
            hostingController.view.autoresizingMask = [.width, .height]
            container.addSubview(hostingController.view)
        }

        addChild(hostingController)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
            hostingController.view.frame = glass.bounds
        } else {
            hostingController.view.frame = view.bounds
        }

        let size = intrinsicContentSize
        guard size.width > 0, size.height > 0, size != lastReportedSize else { return }
        lastReportedSize = size
        onIntrinsicSizeChange?(size)
    }

    var intrinsicContentSize: NSSize {
        hostingController.view.layoutSubtreeIfNeeded()
        let fitting = hostingController.view.fittingSize
        if fitting.width > 0, fitting.height > 0 {
            return fitting
        }
        return hostingController.preferredContentSize
    }
}
