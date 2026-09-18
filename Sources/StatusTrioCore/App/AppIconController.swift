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
        _ volumeOptions: VolumeIconOptions,
        _ bluetoothAudioOptions: BluetoothAudioIconOptions,
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
    private let imageCache = DockIconImageCache()
    private var hasRenderedDockIcon = false
    private var currentPlacement: AppIconPlacement
    private var currentBatteryOptions: BatteryIconOptions
    private var currentConnectionOptions: ConnectionIconOptions
    private var currentVolumeOptions: VolumeIconOptions
    private var currentBluetoothAudioOptions: BluetoothAudioIconOptions
    private var currentBackgroundPreference: DockIconBackgroundPreference
    private var isDockTileVisible: Bool
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
        self.currentVolumeOptions = settings.volumeIconOptions
        self.currentBluetoothAudioOptions = settings.bluetoothAudioIconOptions
        self.currentBackgroundPreference = settings.dockIconBackgroundPreference
        self.isDockTileVisible = activationPolicy.isRegularApp
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        // Adopt whatever the settings hold now: they can change between
        // construction and the first start.
        currentPlacement = settings.appIconPlacement
        currentBatteryOptions = settings.batteryIconOptions
        currentConnectionOptions = settings.connectionIconOptions
        currentVolumeOptions = settings.volumeIconOptions
        currentBluetoothAudioOptions = settings.bluetoothAudioIconOptions
        currentBackgroundPreference = settings.dockIconBackgroundPreference
        apply(currentPlacement)
        activationPolicy.$isRegularApp
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isRegular in
                // @Published emits before the stored value changes, so use the
                // value the publisher delivered.
                guard let self else { return }
                isDockTileVisible = isRegular
                dockTileVisibilityChanged()
            }
            .store(in: &cancellables)
        monitor.onChange = { [weak self] _ in
            self?.renderLatestDockIcon()
        }
        monitor.start()
        subscribeToPlacement()
        subscribeToSnapshot()
        subscribeToBatteryOptions()
        subscribeToConnectionOptions()
        subscribeToVolumeDisplayStyle()
        subscribeToBluetoothAudioOptions()
        subscribeToBackgroundStyle()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        cancellables.removeAll()
        monitor.onChange = nil
        monitor.stop()
        clearDockIcon()
    }

    private func dockTileVisibilityChanged() {
        guard isDockTileVisible else {
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
            .map { MenuBarStatus(snapshot: $0) }
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
        .combineLatest(settings.$showsPercentageWhenConnected)
        .combineLatest(settings.$batterySymbolScale)
        .dropFirst()
        .sink { [weak self] batteryValues, symbolScale in
            guard let self else { return }
            let (
                showsPercentage,
                showsChargingIndicator,
                usesStatusColors,
                criticalThreshold
            ) = batteryValues.0
            let showsPercentageWhenConnected = batteryValues.1
            currentBatteryOptions = BatteryIconOptions(
                showsPercentage: showsPercentage,
                showsChargingIndicator: showsChargingIndicator,
                usesStatusColors: usesStatusColors,
                criticalThreshold: Int(criticalThreshold.rounded()),
                showsPercentageWhenConnected: showsPercentageWhenConnected,
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
        .combineLatest(settings.$wifiSymbolScale)
        .dropFirst()
        .sink { [weak self] values, wifiScale in
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
                showsWiFiIconForInternetSharing: showsForInternetSharing,
                wifiScale: wifiScale
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

    private func subscribeToVolumeDisplayStyle() {
        settings.$volumeDisplayStyle
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] displayStyle in
                guard let self else { return }
                currentVolumeOptions = VolumeIconOptions(displayStyle: displayStyle)
                renderLatestDockIcon()
            }
        .store(in: &cancellables)
    }

    private func subscribeToBluetoothAudioOptions() {
        Publishers.CombineLatest4(
            settings.$replacesNetworkIconWithBluetoothAudio,
            settings.$usesBluetoothAudioVolumeColor,
            settings.$prioritizesNetworkErrorsOverBluetoothAudio,
            settings.$bluetoothSymbolScale
        )
        .dropFirst()
        .sink { [weak self] replacesNetworkIcon, usesVolumeColor, prioritizesNetworkErrors, symbolScale in
            guard let self else { return }
            currentBluetoothAudioOptions = BluetoothAudioIconOptions(
                replacesNetworkIcon: replacesNetworkIcon,
                usesVolumeColor: usesVolumeColor,
                prioritizesNetworkErrors: prioritizesNetworkErrors,
                symbolScale: symbolScale
            )
            renderLatestDockIcon()
        }
        .store(in: &cancellables)
    }

    private func apply(_ placement: AppIconPlacement) {
        currentPlacement = placement

        if placement.showsDockIcon {
            let didActivate = activationPolicy.setDockIconVisible(true)
            isDockTileVisible = activationPolicy.isRegularApp
            guard didActivate else {
                // Never trade the Menu Bar away for a Dock tile AppKit refused.
                setMenuBarVisible(true)
                return
            }
            renderLatestDockIcon()
            setMenuBarVisible(placement.showsMenuBarIcon)
        } else {
            setMenuBarVisible(true)
            _ = activationPolicy.setDockIconVisible(false)
            isDockTileVisible = activationPolicy.isRegularApp
        }
    }

    private func renderLatestDockIcon() {
        guard isDockTileVisible else { return }

        let backgroundStyle = DockIconBackgroundResolver.style(
            for: currentBackgroundPreference,
            theme: theme(),
            isDarkAppearance: isDarkAppearance()
        )
        let status = MenuBarStatus(snapshot: store.snapshot)
        let key = DockIconRenderKey(
            status: status,
            options: currentBatteryOptions,
            connectionOptions: currentConnectionOptions,
            volumeOptions: currentVolumeOptions,
            bluetoothAudioOptions: currentBluetoothAudioOptions,
            backgroundStyle: backgroundStyle
        )
        guard renderCache.shouldRender(key) else { return }

        if let cached = imageCache.image(for: key) {
            application.setApplicationIconImage(cached)
            hasRenderedDockIcon = true
            return
        }

        guard let image = renderDockIcon(
            status,
            currentBatteryOptions,
            currentConnectionOptions,
            currentVolumeOptions,
            currentBluetoothAudioOptions,
            backgroundStyle
        ) else {
            if !hasRenderedDockIcon {
                application.setApplicationIconImage(nil)
            }
            return
        }

        imageCache.store(image, for: key)
        application.setApplicationIconImage(image)
        hasRenderedDockIcon = true
    }
}
