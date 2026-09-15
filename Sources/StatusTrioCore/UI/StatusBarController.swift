import AppKit
import Combine
import SwiftUI

private struct UncheckedSendableNSEvent: @unchecked Sendable {
    let event: NSEvent
}

private struct StatusBarAccessibilityKey: Equatable {
    let status: MenuBarStatus
    let language: AppLanguage
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    static let iconSnapshotDebounceInterval: TimeInterval = 0.5

    enum ClickKind: Equatable {
        case left
        case right
    }

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: SystemStatusStore
    private let settings: SettingsStore
    private let localization: Localization
    private var cancellable: AnyCancellable?
    private var localizationCancellable: AnyCancellable?
    private var iconSizeCancellable: AnyCancellable?
    private var batteryOptionsCancellable: AnyCancellable?
    private var connectionIconOptionsCancellable: AnyCancellable?
    private var screenParametersCancellable: AnyCancellable?
    private var refreshIntervalCancellable: AnyCancellable?
    private let openSettings: () -> Void
    private let quitAction: () -> Void
    private var appearanceObservations: [NSKeyValueObservation] = []
    private var renderCache = StatusBarRenderCache()
    private var isStatusItemVisible: Bool
    private var accessibilityKey: StatusBarAccessibilityKey?
    private var popoverDismissMonitor: Any?
    private var volumeScrollMonitor: Any?
    private let volumeScrollAdjustment = PopupVolumeScrollAdjustment()
    private var volumeScrollSession = PopupVolumeScrollSession()
    private var dockAnchorWindow: NSWindow?

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        localization: Localization,
        isVisible: Bool = true,
        openSettings: @escaping () -> Void,
        quitAction: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.localization = localization
        self.openSettings = openSettings
        self.quitAction = quitAction
        self.isStatusItemVisible = isVisible
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.isVisible = isVisible
        configureButton()
        configurePopover()
        observeAppearanceChanges()
        scheduleInitialRender()

        cancellable = store.$snapshot
            .removeDuplicates()
            .dropFirst()
            .debounce(
                for: .seconds(Self.iconSnapshotDebounceInterval),
                scheduler: RunLoop.main
            )
            .sink { [weak self] _ in
                self?.renderLatestSnapshot()
            }

        iconSizeCancellable = settings.$iconSize
            .removeDuplicates()
            .sink { [weak self] iconSize in
                guard let self else { return }
                self.render(
                    status: MenuBarStatus(snapshot: self.store.snapshot),
                    iconSize: iconSize,
                    options: self.settings.batteryIconOptions,
                    connectionOptions: self.settings.connectionIconOptions
                )
            }

        batteryOptionsCancellable = Publishers.CombineLatest4(
            settings.$showsBatteryPercentage,
            settings.$showsChargingIndicator,
            settings.$usesBatteryStatusColors,
            settings.$batteryCriticalThreshold
        )
        .combineLatest(settings.$batterySymbolScale)
        .sink { [weak self] batteryValues, symbolScale in
            guard let self else { return }
            let (
                showsPercentage,
                showsChargingIndicator,
                usesStatusColors,
                criticalThreshold
            ) = batteryValues
            let options = BatteryIconOptions(
                showsPercentage: showsPercentage,
                showsChargingIndicator: showsChargingIndicator,
                usesStatusColors: usesStatusColors,
                criticalThreshold: Int(criticalThreshold.rounded()),
                textScale: symbolScale * BatteryIconOptions.defaultTextScale
            )
            self.render(
                status: MenuBarStatus(snapshot: self.store.snapshot),
                iconSize: self.settings.iconSize,
                options: options,
                connectionOptions: self.settings.connectionIconOptions
            )
        }

        connectionIconOptionsCancellable = Publishers.CombineLatest4(
            settings.$showsWiFiIconForEthernet,
            settings.$showsWiFiIconForHotspot,
            settings.$showsWiFiIconForTemporaryConnection,
            settings.$showsWiFiIconForInternetSharing
        )
        .sink { [weak self] values in
            guard let self else { return }
            let (
                showsForEthernet,
                showsForHotspot,
                showsForTemporaryConnection,
                showsForInternetSharing
            ) = values
            self.render(
                status: MenuBarStatus(snapshot: self.store.snapshot),
                iconSize: self.settings.iconSize,
                options: self.settings.batteryIconOptions,
                connectionOptions: ConnectionIconOptions(
                    showsWiFiIconForEthernet: showsForEthernet,
                    showsWiFiIconForHotspot: showsForHotspot,
                    showsWiFiIconForTemporaryConnection: showsForTemporaryConnection,
                    showsWiFiIconForInternetSharing: showsForInternetSharing
                )
            )
        }

        localizationCancellable = localization.$resolvedLanguage
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.renderLatestSnapshot()
                }
            }

        refreshIntervalCancellable = settings.$refreshIntervalSeconds
            .removeDuplicates()
            .sink { [weak self] seconds in
                self?.store.setRefreshInterval(.seconds(Int(seconds.rounded())))
            }

        screenParametersCancellable = NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification,
            object: NSApp
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.renderLatestSnapshot()
        }
    }

    static func clickKind(eventType: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> ClickKind? {
        if eventType == .rightMouseUp || modifiers.contains(.control) {
            return .right
        }
        if eventType == .leftMouseUp {
            return .left
        }
        return nil
    }

    func setVisible(_ isVisible: Bool) {
        guard isStatusItemVisible != isVisible else { return }
        isStatusItemVisible = isVisible

        if isVisible {
            statusItem.isVisible = true
            renderCache = StatusBarRenderCache()
            renderLatestSnapshot()
        } else {
            popover.performClose(nil)
            store.setPopoverVisible(false)
            statusItem.isVisible = false
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func observeAppearanceChanges() {
        guard let button = statusItem.button else { return }
        appearanceObservations.append(button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.renderLatestSnapshot()
            }
        })
    }

    private func scheduleInitialRender() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.renderLatestSnapshot()
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard
            let event = NSApp.currentEvent,
            let click = Self.clickKind(eventType: event.type, modifiers: event.modifierFlags)
        else { return }

        switch click {
        case .left:
            togglePopover()
        case .right:
            popover.performClose(nil)
            showMenu()
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
    }

    private func installPopoverContentIfNeeded() {
        guard popover.contentViewController == nil else { return }
        let rootView = LocalizedRootView(localization: localization) {
            StatusPopoverView(
                store: store,
                settings: settings,
                requestWiFiNameAccess: handleRequestWiFiNameAccess,
                openBatterySettings: handleOpenBatterySettings,
                openWiFiSettings: handleOpenWiFiSettings,
                openLocationSettings: handleOpenLocationSettings,
                openSettings: handleOpenSettings,
                openSoundSettings: handleOpenSoundSettings,
                quit: quitAction
            )
        }
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            presentPopover(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
    }

    /// Shows the same popover for a Dock icon click, above the clicked icon.
    func togglePopover(anchoredAtScreenPoint point: NSPoint) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        let anchorView = dockAnchorView(at: point)
        presentPopover(
            relativeTo: anchorView.bounds,
            of: anchorView,
            preferredEdge: .maxY
        )
    }

    private func presentPopover(
        relativeTo rect: NSRect,
        of view: NSView,
        preferredEdge: NSRectEdge
    ) {
        store.setPopoverVisible(true)
        installPopoverContentIfNeeded()
        // Activate first: a transient popover shown while the app is still
        // inactive can be dismissed again straight away.
        // Status-item clicks come from the system menu bar process, so the
        // modern activate() can be ignored by the user-activation policy.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
        popover.contentViewController?.view.window?.makeKey()
        installPopoverDismissMonitor()
        installVolumeScrollMonitor()
    }

    /// The Dock icon has no public frame, but the click happens on the icon, so
    /// a tiny invisible window at the click point anchors the popover there.
    private func dockAnchorView(at point: NSPoint) -> NSView {
        let window: NSWindow
        if let dockAnchorWindow {
            window = dockAnchorWindow
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            dockAnchorWindow = window
        }

        let tileHeight = NSApplication.shared.dockTile.size.height
        window.setFrameOrigin(
            NSPoint(x: point.x, y: point.y + max(0, tileHeight) / 2)
        )
        window.orderFront(nil)
        return window.contentView ?? window.contentViewController?.view ?? NSView()
    }

    private func installPopoverDismissMonitor() {
        removePopoverDismissMonitor()
        popoverDismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.popover.performClose(nil)
            }
        }
    }

    private func removePopoverDismissMonitor() {
        guard let popoverDismissMonitor else { return }
        NSEvent.removeMonitor(popoverDismissMonitor)
        self.popoverDismissMonitor = nil
    }

    private func installVolumeScrollMonitor() {
        removeVolumeScrollMonitor()
        volumeScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Local event monitors run on the main thread. Keep the non-Sendable
            // event inside this synchronous callback while hopping isolation.
            let boxedEvent = UncheckedSendableNSEvent(event: event)
            let shouldConsume = MainActor.assumeIsolated {
                self?.shouldConsumeVolumeScrollWheel(boxedEvent.event) ?? false
            }
            return shouldConsume ? nil : event
        }
    }

    private func removeVolumeScrollMonitor() {
        guard let volumeScrollMonitor else { return }
        NSEvent.removeMonitor(volumeScrollMonitor)
        self.volumeScrollMonitor = nil
        resetVolumeScrollSession()
    }

    private func shouldConsumeVolumeScrollWheel(_ event: NSEvent) -> Bool {
        guard event.window === popover.contentViewController?.view.window,
              store.isVolumeControlAvailable,
              !isPointerOverScrollView(event) else {
            return false
        }
        guard event.momentumPhase.isEmpty else { return true }

        guard let currentScalar = volumeScrollSession.scalar(
            at: event.timestamp,
            fallback: store.popupSnapshot.volume.scalar
        ) else {
            return false
        }
        let delta = volumeScrollAdjustment.volumeDelta(
            deltaY: Double(event.scrollingDeltaY),
            isPrecise: event.hasPreciseScrollingDeltas
        )
        guard let delta else { return true }

        let nextScalar = volumeScrollSession.applying(
            delta: delta,
            to: currentScalar
        )
        if volumeScrollSession.shouldUnmute(
            isMuted: store.popupSnapshot.volume.isMuted,
            isIncreasing: delta > 0
        ) {
            store.toggleMute()
        }
        store.setVolume(nextScalar)
        return true
    }

    private func isPointerOverScrollView(_ event: NSEvent) -> Bool {
        guard let rootView = popover.contentViewController?.view else { return false }
        let point = rootView.convert(event.locationInWindow, from: nil)
        var view = rootView.hitTest(point)
        while let currentView = view {
            if currentView is NSScrollView {
                return true
            }
            view = currentView.superview
        }
        return false
    }

    private func resetVolumeScrollSession() {
        volumeScrollSession.reset()
    }

    func popoverDidClose(_ notification: Notification) {
        removePopoverDismissMonitor()
        removeVolumeScrollMonitor()
        store.setPopoverVisible(false)
        popover.contentViewController = nil
    }

    private func render(status: MenuBarStatus) {
        render(
            status: status,
            iconSize: settings.iconSize,
            options: settings.batteryIconOptions,
            connectionOptions: settings.connectionIconOptions
        )
    }

    private func render(
        status: MenuBarStatus,
        iconSize: Double,
        options: BatteryIconOptions,
        connectionOptions: ConnectionIconOptions
    ) {
        guard isStatusItemVisible, let button = statusItem.button else { return }

        let key = StatusBarRenderKey(
            status: status,
            iconSize: iconSize,
            options: options,
            connectionOptions: connectionOptions,
            appearanceName: button.effectiveAppearance.name.rawValue
        )
        guard renderCache.shouldRender(key) else { return }

        button.image = StatusIconRenderer.image(
            menuBarStatus: status,
            size: iconSize,
            options: options,
            connectionOptions: connectionOptions
        )

        let nextAccessibilityKey = StatusBarAccessibilityKey(
            status: status,
            language: localization.resolvedLanguage
        )
        guard nextAccessibilityKey != accessibilityKey else { return }
        accessibilityKey = nextAccessibilityKey
        button.setAccessibilityLabel(StatusPresentation.statusItemAccessibilityLabel)
        button.setAccessibilityValue(
            StatusPresentation.statusItemAccessibilityValue(
                status,
                localization: localization
            )
        )
    }

    private func renderLatestSnapshot() {
        render(status: MenuBarStatus(snapshot: store.snapshot))
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    @objc private func handleOpenSettings() {
        popover.performClose(nil)
        openSettings()
    }

    @objc private func handleCheckForUpdates() {
        popover.performClose(nil)
        UpdaterManager.shared.checkForUpdates()
    }

    @objc private func handleRequestWiFiNameAccess() {
        NSApp.activate()
        store.requestWiFiNameAccess()
    }

    @objc private func handleOpenBatterySettings() {
        popover.performClose(nil)
        Self.openSystemSettings(Self.batterySettingsURLs)
    }

    @objc private func handleOpenWiFiSettings() {
        popover.performClose(nil)
        Self.openSystemSettings(Self.wifiSettingsURLs)
    }

    @objc private func handleOpenLocationSettings() {
        popover.performClose(nil)
        Self.openSystemSettings(Self.locationSettingsURLs)
    }

    @objc private func handleOpenSoundSettings() {
        popover.performClose(nil)
        Self.openSystemSoundSettings()
    }

    static let batterySettingsURLs = [
        "x-apple.systempreferences:com.apple.Battery-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.battery"
    ]
    .compactMap(URL.init(string:))

    static let wifiSettingsURLs = [
        "x-apple.systempreferences:com.apple.Network-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.network"
    ]
    .compactMap(URL.init(string:))

    static let locationSettingsURLs = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
    ]
    .compactMap(URL.init(string:))

    private static func openSystemSoundSettings() {
        let soundSettingsURLs = [
            "x-apple.systempreferences:com.apple.Sound-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.sound"
        ]
        .compactMap(URL.init(string:))

        for url in soundSettingsURLs where NSWorkspace.shared.open(url) {
            return
        }
    }

    private static func openSystemSettings(_ urls: [URL]) {
        for url in urls where NSWorkspace.shared.open(url) {
            return
        }
    }

    private func showMenu() {
        let menu = StatusMenuBuilder.makeMenu(
            version: Self.appVersion,
            settingsTarget: self,
            settingsAction: #selector(handleOpenSettings),
            localization: localization,
            updateTarget: self,
            updateAction: #selector(handleCheckForUpdates)
        )
        guard let button = statusItem.button else { return }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.maxY + 4),
            in: button
        )
    }
}
