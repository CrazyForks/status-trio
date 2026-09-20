import AppKit
import Combine
import Foundation

@MainActor
final class SystemStatusStore: ObservableObject {
    static let popupDebounceInterval: Duration = .milliseconds(500)

    /// Tolerance for the fallback poll. Without one, macOS must wake the CPU on
    /// an exact schedule to satisfy the timer, which is exactly what an idle
    /// menu bar app should not ask for; a fifth of the interval still samples
    /// often enough for a value that the push channels did not report.
    static func refreshSleepTolerance(for interval: Duration) -> Duration {
        interval / 5
    }

    @Published private(set) var snapshot: StatusSnapshot
    @Published private(set) var popupSnapshot: StatusSnapshot
    /// True while the popover is waiting for a Wi-Fi name it has not read yet.
    @Published private(set) var isResolvingWiFiName = false
    @Published private(set) var liveVolume: VolumeStatus
    let batteryDetails: BatteryDetailsController
    let wifiNetworks: WiFiNetworkController
    let bluetoothDevices: BluetoothDeviceController

    private let batteryMonitor: any BatteryMonitoring
    private let wifiMonitor: any WiFiMonitoring
    private let connectionMonitor: (any NetworkConnectionMonitoring)?
    private let volumeMonitor: any VolumeMonitoring
    private let volumeController: (any VolumeControlling)?
    private var refreshInterval: Duration
    private let nameResolutionTimeout: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let popupDebounceSleep: @Sendable (Duration) async throws -> Void
    private let wakeNotificationCenter: NotificationCenter
    private var monitorTasks: [Task<Void, Never>] = []
    private var refreshTask: Task<Void, Never>?
    private var popupPublishTask: Task<Void, Never>?
    private var wifiNameResolutionTask: Task<Void, Never>?
    nonisolated(unsafe) private var wakeObserver: NSObjectProtocol?
    private var lastPublishedSnapshot: StatusSnapshot?
    private var hasStarted = false
    private var hasStopped = false
    @Published private(set) var isPopoverVisible = false
    private var isSettingsVisible = false
    private var isBluetoothEnabled = false
    private var isBluetoothDetailsOpen = false

    init(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        connectionMonitor: (any NetworkConnectionMonitoring)? = nil,
        volumeMonitor: any VolumeMonitoring,
        refreshInterval: Duration = .seconds(5),
        nameResolutionTimeout: Duration = .milliseconds(1500),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { interval in
            try await Task.sleep(
                for: interval,
                tolerance: SystemStatusStore.refreshSleepTolerance(for: interval)
            )
        },
        popupDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        wakeNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        batteryDetails: BatteryDetailsController = BatteryDetailsController(),
        wifiNetworks: WiFiNetworkController = WiFiNetworkController(),
        bluetoothDevices: BluetoothDeviceController = BluetoothDeviceController(),
        initialSnapshot: StatusSnapshot = .placeholder
    ) {
        self.batteryMonitor = batteryMonitor
        self.wifiMonitor = wifiMonitor
        self.connectionMonitor = connectionMonitor
        self.volumeMonitor = volumeMonitor
        self.volumeController = volumeMonitor as? any VolumeControlling
        self.refreshInterval = refreshInterval
        self.nameResolutionTimeout = nameResolutionTimeout
        self.sleep = sleep
        self.popupDebounceSleep = popupDebounceSleep
        self.wakeNotificationCenter = wakeNotificationCenter
        self.batteryDetails = batteryDetails
        self.wifiNetworks = wifiNetworks
        self.bluetoothDevices = bluetoothDevices
        self.snapshot = initialSnapshot
        self.popupSnapshot = initialSnapshot
        self.liveVolume = initialSnapshot.volume
    }

    deinit {
        if let wakeObserver {
            wakeNotificationCenter.removeObserver(wakeObserver)
        }
        monitorTasks.forEach { $0.cancel() }
        refreshTask?.cancel()
        popupPublishTask?.cancel()
    }

    func start() {
        guard !hasStarted, !hasStopped else { return }
        hasStarted = true
        wifiMonitor.setDetailsVisible(false)
        volumeMonitor.setDetailsVisible(false)

        wakeObserver = wakeNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recoverAll()
                self.refreshAll()
            }
        }

        batteryMonitor.start()
        wifiMonitor.start()
        connectionMonitor?.start()
        volumeMonitor.start()

        let batteryUpdates = batteryMonitor.updates
        let wifiUpdates = wifiMonitor.updates
        let connectionUpdates = connectionMonitor?.updates
        let volumeUpdates = volumeMonitor.updates
        var tasks = [
            Task { [weak self] in
                for await value in batteryUpdates {
                    guard let self else { return }
                    self.applyBattery(value)
                }
            },
            Task { [weak self] in
                for await value in wifiUpdates {
                    guard let self else { return }
                    self.applyWiFi(value)
                }
            },
            Task { [weak self] in
                for await value in volumeUpdates {
                    guard let self else { return }
                    self.applyVolume(value)
                }
            }
        ]
        if let connectionUpdates {
            tasks.append(Task { [weak self] in
                for await value in connectionUpdates {
                    guard let self else { return }
                    self.applyConnection(value)
                }
            })
        }
        monitorTasks = tasks

        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let sleep = self?.sleep, let interval = self?.refreshInterval else { return }
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.refreshAll()
            }
        }
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true

        if let wakeObserver {
            wakeNotificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }

        batteryDetails.deactivate()
        batteryMonitor.stop()
        wifiMonitor.stop()
        connectionMonitor?.stop()
        volumeMonitor.stop()
        monitorTasks.forEach { $0.cancel() }
        monitorTasks.removeAll()
        refreshTask?.cancel()
        refreshTask = nil
        popupPublishTask?.cancel()
        popupPublishTask = nil
        clearWiFiNameResolution()
        wifiNetworks.deactivate()
        bluetoothDevices.deactivate()
    }

    var isVolumeControlAvailable: Bool {
        volumeController != nil && liveVolume.scalar != nil
    }

    func setVolume(_ scalar: Double) {
        guard !hasStopped,
              volumeController != nil,
              scalar.isFinite else {
            return
        }
        liveVolume = liveVolume.replacingScalar(min(1, max(0, scalar)))
        publish(snapshot.replacingVolume(liveVolume))
        volumeController?.setVolume(liveVolume.scalar ?? 0)
    }

    func toggleMute() {
        guard !hasStopped,
              volumeController != nil,
              liveVolume.scalar != nil else {
            return
        }
        liveVolume = liveVolume.replacingMuted(!liveVolume.isMuted)
        publish(snapshot.replacingVolume(liveVolume))
        volumeController?.toggleMute()
    }

    func selectOutputDevice(_ device: AudioOutputDevice) {
        guard !hasStopped else { return }
        volumeController?.selectOutputDevice(device.id)
    }

    func requestWiFiNameAccess() {
        guard !hasStopped else { return }
        wifiMonitor.requestNameAccess()
    }

    func requestBluetoothAuthorization() {
        setBluetoothEnabled(true)
    }

    func setBluetoothEnabled(_ enabled: Bool) {
        guard !hasStopped else { return }
        isBluetoothEnabled = enabled
        if enabled {
            bluetoothDevices.activate()
        } else {
            isBluetoothDetailsOpen = false
            bluetoothDevices.deactivate()
        }
    }

    func openBluetoothDetails() {
        guard !hasStopped else { return }
        isBluetoothDetailsOpen = true
        bluetoothDevices.activate()
    }

    func closeBluetoothDetails() {
        isBluetoothDetailsOpen = false
        if !isBluetoothEnabled {
            bluetoothDevices.deactivate()
        }
    }

    /// Enables the Bluetooth monitor when the popover opens, so the row can
    /// report device names. Starting the monitor is what raises the system
    /// permission prompt, so this only runs for an app that already holds the
    /// grant; every other state is left for the row to report and for the
    /// user's tap to resolve.
    private func activateBluetoothForPopover() {
        guard BluetoothPanelActivation.shouldActivate(
            authorization: bluetoothDevices.authorization
        ) else { return }
        setBluetoothEnabled(true)
    }

    func closeBatteryDetails() {
        batteryDetails.deactivate()
    }

    func refreshForPopoverOpening() {
        setPopoverVisible(true)
    }

    func setRefreshInterval(_ interval: Duration) {
        guard interval != refreshInterval else { return }
        refreshInterval = interval
    }

    func setPopoverVisible(_ visible: Bool) {
        guard !hasStopped else { return }
        isPopoverVisible = visible
        if !visible { batteryDetails.deactivate() }
        updateDetailsVisibility()

        guard visible else {
            clearWiFiNameResolution()
            return
        }
        popupPublishTask?.cancel()
        popupPublishTask = nil
        popupSnapshot = snapshot
        startWiFiNameResolutionIfNeeded()
        bluetoothDevices.prepareForPresentation()
        activateBluetoothForPopover()
        refreshAll()
        wifiNetworks.refresh(nameAccess: popupSnapshot.wifi.nameAccess)
    }

    func setSettingsVisible(_ visible: Bool) {
        guard !hasStopped, isSettingsVisible != visible else { return }
        isSettingsVisible = visible
        updateDetailsVisibility()

        if visible {
            refreshAll()
        }
    }

    func activateWiFiPanel() {
        guard !hasStopped else { return }
        wifiNetworks.activate(nameAccess: popupSnapshot.wifi.nameAccess)
    }

    func closePopoverDetails() {
        wifiNetworks.deactivate()
        closeBluetoothDetails()
        closeBatteryDetails()
    }

    /// Whether a popover detail panel (Wi-Fi, Bluetooth, or battery) is
    /// currently open. Query this before `setPopoverVisible(false)`: the
    /// battery page stops its collector when its view disappears, and that
    /// happens while the popover is already closing.
    var hasOpenPopoverPanel: Bool {
        wifiNetworks.isActive || isBluetoothDetailsOpen || batteryDetails.isActive
    }

    func refreshAll() {
        guard !hasStopped else { return }
        batteryMonitor.refresh()
        wifiMonitor.refresh()
        volumeMonitor.refresh()
    }

    private func recoverAll() {
        batteryMonitor.recover()
        wifiMonitor.recover()
        connectionMonitor?.recover()
        volumeMonitor.recover()
    }

    private func updateDetailsVisibility() {
        let detailsVisible = isPopoverVisible || isSettingsVisible
        wifiMonitor.setDetailsVisible(isPopoverVisible)
        volumeMonitor.setDetailsVisible(detailsVisible)
    }

    private func applyBattery(_ value: BatteryStatus) {
        publish(snapshot.replacingBattery(value))
    }

    private func applyWiFi(_ value: WiFiStatus) {
        publish(snapshot.replacingWiFi(value))
        wifiNetworks.refresh(nameAccess: value.nameAccess)
    }

    private func applyConnection(_ value: NetworkConnection) {
        publish(snapshot.replacingConnection(value))
    }

    private func applyVolume(_ value: VolumeStatus) {
        liveVolume = value
        publish(snapshot.replacingVolume(value))
    }

    private func publish(_ next: StatusSnapshot) {
        guard !hasStopped, next != lastPublishedSnapshot else { return }
        lastPublishedSnapshot = next
        snapshot = next
        schedulePopupSnapshot(next)
    }

    private func schedulePopupSnapshot(_ next: StatusSnapshot) {
        guard isPopoverVisible else { return }
        if isResolvingWiFiName, !next.wifi.isAwaitingName {
            // The name the popover is waiting for just arrived: show it right away
            // instead of leaving the row blank for the full debounce interval.
            popupPublishTask?.cancel()
            popupPublishTask = nil
            applyPopupSnapshot(next)
            return
        }
        popupPublishTask?.cancel()
        popupPublishTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.popupDebounceSleep(Self.popupDebounceInterval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.applyPopupSnapshot(next)
        }
    }

    private func applyPopupSnapshot(_ next: StatusSnapshot) {
        popupSnapshot = next
        if isResolvingWiFiName, !next.wifi.isAwaitingName {
            clearWiFiNameResolution()
        }
    }

    /// Leaves the Wi-Fi row blank right after the popover opens until the name arrives.
    private func startWiFiNameResolutionIfNeeded() {
        guard isPopoverVisible, popupSnapshot.wifi.isAwaitingName else {
            clearWiFiNameResolution()
            return
        }
        guard !isResolvingWiFiName else { return }

        isResolvingWiFiName = true
        let timeout = nameResolutionTimeout
        let sleep = popupDebounceSleep
        wifiNameResolutionTask = Task { @MainActor [weak self] in
            do {
                try await sleep(timeout)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            // The read never delivered a name: fall back to the plain state text.
            self.isResolvingWiFiName = false
        }
    }

    private func clearWiFiNameResolution() {
        wifiNameResolutionTask?.cancel()
        wifiNameResolutionTask = nil
        isResolvingWiFiName = false
    }
}

private extension VolumeStatus {
    func replacingScalar(_ scalar: Double) -> VolumeStatus {
        VolumeStatus(
            scalar: scalar,
            isMuted: isMuted,
            deviceName: deviceName,
            currentDevice: currentDevice,
            outputDevices: outputDevices
        )
    }

    func replacingMuted(_ isMuted: Bool) -> VolumeStatus {
        VolumeStatus(
            scalar: scalar,
            isMuted: isMuted,
            deviceName: deviceName,
            currentDevice: currentDevice,
            outputDevices: outputDevices
        )
    }
}

private extension StatusSnapshot {
    func replacingBattery(_ value: BatteryStatus) -> StatusSnapshot {
        StatusSnapshot(battery: value, wifi: wifi, connection: connection, volume: volume)
    }

    func replacingWiFi(_ value: WiFiStatus) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: value, connection: connection, volume: volume)
    }

    func replacingConnection(_ value: NetworkConnection) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, connection: value, volume: volume)
    }

    func replacingVolume(_ value: VolumeStatus) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, connection: connection, volume: value)
    }
}
