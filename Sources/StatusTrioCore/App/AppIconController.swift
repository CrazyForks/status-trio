import AppKit
import Combine

@MainActor
protocol ApplicationDockIconApplying: AnyObject {
    func setApplicationIconImage(_ image: NSImage?)
}

extension NSApplication: ApplicationDockIconApplying {
    func setApplicationIconImage(_ image: NSImage?) {
        applicationIconImage = image
    }
}

@MainActor
final class AppIconController {
    typealias DockRenderer = (
        _ status: MenuBarStatus,
        _ options: BatteryIconOptions,
        _ connectionOptions: ConnectionIconOptions,
        _ backgroundStyle: DockIconBackgroundStyle
    ) -> NSImage?

    static let snapshotDebounceInterval: TimeInterval = 0.5

    private let store: SystemStatusStore
    private let settings: SettingsStore
    private let activationPolicy: AppActivationPolicy
    private let application: any ApplicationDockIconApplying
    private let setMenuBarVisible: (Bool) -> Void
    private let renderDockIcon: DockRenderer
    private let theme: () -> SystemIconAppearanceTheme
    private let isDarkAppearance: () -> Bool
    private let monitor: SystemIconAppearanceMonitor
    private var cancellables: Set<AnyCancellable> = []
    private var renderCache = DockIconRenderCache()
    private var hasRenderedDockIcon = false
    private var currentPlacement: AppIconPlacement
    private var currentBatteryOptions: BatteryIconOptions
    private var currentConnectionOptions: ConnectionIconOptions
    private var currentBackgroundPreference: DockIconBackgroundPreference
    private var isStarted = false

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        activationPolicy: AppActivationPolicy,
        application: any ApplicationDockIconApplying = NSApplication.shared,
        setMenuBarVisible: @escaping (Bool) -> Void,
        renderDockIcon: @escaping DockRenderer,
        theme: @escaping () -> SystemIconAppearanceTheme = {
            SystemIconAppearanceReader.current()
        },
        isDarkAppearance: @escaping () -> Bool = {
            NSApplication.shared.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        },
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.settings = settings
        self.activationPolicy = activationPolicy
        self.application = application
        self.setMenuBarVisible = setMenuBarVisible
        self.renderDockIcon = renderDockIcon
        self.theme = theme
        self.isDarkAppearance = isDarkAppearance
        self.monitor = SystemIconAppearanceMonitor(
            readTheme: theme,
            notificationCenter: notificationCenter
        )
        self.currentPlacement = settings.appIconPlacement
        self.currentBatteryOptions = settings.batteryIconOptions
        self.currentConnectionOptions = settings.connectionIconOptions
        self.currentBackgroundPreference = settings.dockIconBackgroundPreference
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        // Adopt whatever the settings hold now: they can change between
        // construction and the first start.
        currentPlacement = settings.appIconPlacement
        currentBatteryOptions = settings.batteryIconOptions
        currentConnectionOptions = settings.connectionIconOptions
        currentBackgroundPreference = settings.dockIconBackgroundPreference

        apply(currentPlacement)
        activationPolicy.dockTileVisibilityDidChange = { [weak self] _ in
            self?.dockTileVisibilityChanged()
        }
        monitor.onChange = { [weak self] _ in
            self?.renderLatestDockIcon()
        }
        monitor.start()
        subscribeToPlacement()
        subscribeToSnapshot()
        subscribeToBatteryOptions()
        subscribeToConnectionOptions()
        subscribeToBackgroundStyle()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        cancellables.removeAll()
        activationPolicy.dockTileVisibilityDidChange = nil
        monitor.onChange = nil
        monitor.stop()
        clearDockIcon()
    }

    private func dockTileVisibilityChanged() {
        guard activationPolicy.isDockTileVisible else {
            clearDockIcon()
            return
        }
        renderLatestDockIcon()
    }

    private func clearDockIcon() {
        defer { renderCache.reset() }
        guard hasRenderedDockIcon else { return }
        application.setApplicationIconImage(nil)
        hasRenderedDockIcon = false
    }

    private func subscribeToPlacement() {
        settings.$appIconPlacement
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] placement in
                self?.apply(placement)
            }
            .store(in: &cancellables)
    }

    private func subscribeToSnapshot() {
        store.$snapshot
            .removeDuplicates()
            .dropFirst()
            .debounce(
                for: .seconds(Self.snapshotDebounceInterval),
                scheduler: RunLoop.main
            )
            .sink { [weak self] _ in
                self?.renderLatestDockIcon()
            }
            .store(in: &cancellables)
    }

    private func subscribeToBatteryOptions() {
        // @Published emits before the stored value changes, so every sink keeps its
        // own copy of the delivered value instead of reading SettingsStore back.
        Publishers.CombineLatest4(
            settings.$showsBatteryPercentage,
            settings.$showsChargingIndicator,
            settings.$usesBatteryStatusColors,
            settings.$batteryCriticalThreshold
        )
        .combineLatest(settings.$batterySymbolScale)
        .dropFirst()
        .sink { [weak self] batteryValues, symbolScale in
            guard let self else { return }
            let (
                showsPercentage,
                showsChargingIndicator,
                usesStatusColors,
                criticalThreshold
            ) = batteryValues
            currentBatteryOptions = BatteryIconOptions(
                showsPercentage: showsPercentage,
                showsChargingIndicator: showsChargingIndicator,
                usesStatusColors: usesStatusColors,
                criticalThreshold: Int(criticalThreshold.rounded()),
                textScale: symbolScale * BatteryIconOptions.defaultTextScale
            )
            renderLatestDockIcon()
        }
        .store(in: &cancellables)
    }

    private func subscribeToConnectionOptions() {
        Publishers.CombineLatest4(
            settings.$showsWiFiIconForEthernet,
            settings.$showsWiFiIconForHotspot,
            settings.$showsWiFiIconForTemporaryConnection,
            settings.$showsWiFiIconForInternetSharing
        )
        .dropFirst()
        .sink { [weak self] values in
            guard let self else { return }
            let (
                showsForEthernet,
                showsForHotspot,
                showsForTemporaryConnection,
                showsForInternetSharing
            ) = values
            currentConnectionOptions = ConnectionIconOptions(
                showsWiFiIconForEthernet: showsForEthernet,
                showsWiFiIconForHotspot: showsForHotspot,
                showsWiFiIconForTemporaryConnection: showsForTemporaryConnection,
                showsWiFiIconForInternetSharing: showsForInternetSharing
            )
            renderLatestDockIcon()
        }
        .store(in: &cancellables)
    }

    private func subscribeToBackgroundStyle() {
        settings.$dockIconBackgroundPreference
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] preference in
                guard let self else { return }
                currentBackgroundPreference = preference
                renderLatestDockIcon()
            }
            .store(in: &cancellables)
    }

    private func apply(_ placement: AppIconPlacement) {
        currentPlacement = placement

        if placement.showsDockIcon {
            guard activationPolicy.setDockIconVisible(true) else {
                // Never trade the Menu Bar away for a Dock tile AppKit refused.
                setMenuBarVisible(true)
                return
            }
            renderLatestDockIcon()
            setMenuBarVisible(placement.showsMenuBarIcon)
        } else {
            setMenuBarVisible(true)
            _ = activationPolicy.setDockIconVisible(false)
        }
    }

    private func renderLatestDockIcon() {
        guard activationPolicy.isDockTileVisible else { return }

        let backgroundStyle = DockIconBackgroundResolver.style(
            for: currentBackgroundPreference,
            theme: theme(),
            isDarkAppearance: isDarkAppearance()
        )
        let key = DockIconRenderKey(
            status: MenuBarStatus(snapshot: store.snapshot),
            options: currentBatteryOptions,
            connectionOptions: currentConnectionOptions,
            backgroundStyle: backgroundStyle
        )
        guard renderCache.shouldRender(key) else { return }

        guard let image = renderDockIcon(
            key.status,
            currentBatteryOptions,
            currentConnectionOptions,
            backgroundStyle
        ) else {
            if !hasRenderedDockIcon {
                application.setApplicationIconImage(nil)
            }
            return
        }

        application.setApplicationIconImage(image)
        hasRenderedDockIcon = true
    }
}
