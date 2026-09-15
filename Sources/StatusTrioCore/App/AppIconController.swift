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
        _ connectionOptions: ConnectionIconOptions
    ) -> NSImage?

    static let snapshotDebounceInterval: TimeInterval = 0.5

    private let store: SystemStatusStore
    private let settings: SettingsStore
    private let activationPolicy: AppActivationPolicy
    private let application: any ApplicationDockIconApplying
    private let setMenuBarVisible: (Bool) -> Void
    private let renderDockIcon: DockRenderer
    private var cancellables: Set<AnyCancellable> = []
    private var renderCache = DockIconRenderCache()
    private var hasRenderedDockIcon = false
    private var currentPlacement: AppIconPlacement
    private var currentBatteryOptions: BatteryIconOptions
    private var currentConnectionOptions: ConnectionIconOptions
    private var isStarted = false

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        activationPolicy: AppActivationPolicy,
        application: any ApplicationDockIconApplying = NSApplication.shared,
        setMenuBarVisible: @escaping (Bool) -> Void,
        renderDockIcon: @escaping DockRenderer
    ) {
        self.store = store
        self.settings = settings
        self.activationPolicy = activationPolicy
        self.application = application
        self.setMenuBarVisible = setMenuBarVisible
        self.renderDockIcon = renderDockIcon
        self.currentPlacement = settings.appIconPlacement
        self.currentBatteryOptions = settings.batteryIconOptions
        self.currentConnectionOptions = settings.connectionIconOptions
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        apply(currentPlacement)
        subscribeToPlacement()
        subscribeToSnapshot()
        subscribeToBatteryOptions()
        subscribeToConnectionOptions()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        cancellables.removeAll()
        application.setApplicationIconImage(nil)
        hasRenderedDockIcon = false
        renderCache.reset()
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
            application.setApplicationIconImage(nil)
            hasRenderedDockIcon = false
            renderCache.reset()
            _ = activationPolicy.setDockIconVisible(false)
        }
    }

    private func renderLatestDockIcon() {
        guard currentPlacement.showsDockIcon else { return }

        let key = DockIconRenderKey(
            status: MenuBarStatus(snapshot: store.snapshot),
            options: currentBatteryOptions,
            connectionOptions: currentConnectionOptions
        )
        guard renderCache.shouldRender(key) else { return }

        guard let image = renderDockIcon(
            key.status,
            currentBatteryOptions,
            currentConnectionOptions
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
