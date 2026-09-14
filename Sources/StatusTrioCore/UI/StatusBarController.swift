import AppKit
import Combine
import SwiftUI

private struct UncheckedSendableNSEvent: @unchecked Sendable {
    let event: NSEvent
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    static let iconSnapshotDebounceInterval: TimeInterval = 0.5
    static let iconFallbackRefreshInterval: TimeInterval = 5

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
    private let openSettings: () -> Void
    private let quitAction: () -> Void
    private var appearanceObservations: [NSKeyValueObservation] = []
    private var popoverDismissMonitor: Any?
    private var volumeScrollMonitor: Any?
    private let volumeScrollAdjustment = PopupVolumeScrollAdjustment()
    private var volumeScrollSession = PopupVolumeScrollSession()

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        localization: Localization,
        openSettings: @escaping () -> Void,
        quitAction: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.localization = localization
        self.openSettings = openSettings
        self.quitAction = quitAction
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configurePopover()
        observeAppearanceChanges()
        scheduleInitialRender()

        let snapshotUpdates = store.$snapshot
            .removeDuplicates()
            .dropFirst()

        let liveSnapshotUpdates = snapshotUpdates
            .filter { [weak self] _ in
                guard let self else { return false }
                return Self.shouldDebounceSnapshotUpdates(
                    isPreviewEnabled: self.store.isPreviewEnabled
                )
            }
            .debounce(
                for: .seconds(Self.iconSnapshotDebounceInterval),
                scheduler: RunLoop.main
            )
            .map { _ in () }

        let previewSnapshotUpdates = snapshotUpdates
            .filter { [weak self] _ in
                guard let self else { return false }
                return !Self.shouldDebounceSnapshotUpdates(
                    isPreviewEnabled: self.store.isPreviewEnabled
                )
            }
            .map { _ in () }

        let periodicUpdates = Timer.publish(
            every: Self.iconFallbackRefreshInterval,
            on: .main,
            in: .common
        )
        .autoconnect()
        .map { _ in () }

        cancellable = Publishers.Merge3(
            liveSnapshotUpdates,
            previewSnapshotUpdates,
            periodicUpdates
        )
        .sink { [weak self] in
            self?.renderLatestSnapshot()
        }

        iconSizeCancellable = settings.$iconSize
            .removeDuplicates()
            .sink { [weak self] iconSize in
                guard let self else { return }
                self.render(
                    snapshot: self.store.displayedSnapshot,
                    iconSize: iconSize,
                    options: self.settings.batteryIconOptions
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
                snapshot: self.store.displayedSnapshot,
                iconSize: self.settings.iconSize,
                options: options
            )
        }

        localizationCancellable = localization.$resolvedLanguage
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.renderLatestSnapshot()
                }
            }

        appearanceObservations.append(NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.renderLatestSnapshot()
            }
        })
    }

    static func shouldDebounceSnapshotUpdates(isPreviewEnabled: Bool) -> Bool {
        !isPreviewEnabled
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
            store.refreshForPopoverOpening()
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            // Status-item clicks come from the system menu bar process, so the
            // modern activate() can be ignored by the user-activation policy.
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
            installPopoverDismissMonitor()
            installVolumeScrollMonitor()
        }
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
    }

    private func render(snapshot: StatusSnapshot) {
        render(
            snapshot: snapshot,
            iconSize: settings.iconSize,
            options: settings.batteryIconOptions
        )
    }

    private func render(
        snapshot: StatusSnapshot,
        iconSize: Double,
        options: BatteryIconOptions
    ) {
        guard let button = statusItem.button else { return }
        button.image = StatusIconRenderer.image(
            snapshot: snapshot,
            size: iconSize,
            options: options,
            appearance: Self.resolvedAppearance(button: button)
        )
        button.setNeedsDisplay(button.bounds)
        button.setAccessibilityLabel(StatusPresentation.statusItemAccessibilityLabel)
        button.setAccessibilityValue(
            StatusPresentation.statusItemAccessibilityValue(
                snapshot,
                localization: localization
            )
        )
    }

    private func renderLatestSnapshot() {
        render(snapshot: store.displayedSnapshot)
    }

    static func resolvedAppearance(
        button: NSStatusBarButton?,
        application: NSApplication = .shared
    ) -> NSAppearance {
        button?.window?.effectiveAppearance
            ?? button?.effectiveAppearance
            ?? application.effectiveAppearance
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
