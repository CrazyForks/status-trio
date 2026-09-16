import AppKit
import Combine
import CoreAudio
import Foundation

@MainActor
final class SystemStatusStore: ObservableObject {
    static let popupDebounceInterval: Duration = .milliseconds(500)

    @Published private(set) var snapshot: StatusSnapshot
    @Published private(set) var popupSnapshot: StatusSnapshot
    /// True while the popover is waiting for a Wi-Fi name it has not read yet.
    @Published private(set) var isResolvingWiFiName = false
    @Published private(set) var isPreviewEnabled = false
    @Published private(set) var isPreviewBatteryAnimationRunning = false
    @Published private(set) var previewStatus = PreviewStatusConfiguration.standard
    @Published private(set) var liveVolume: VolumeStatus
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
    private let previewAnimationSleep: @Sendable (Duration) async throws -> Void
    private let wakeNotificationCenter: NotificationCenter
    private var monitorTasks: [Task<Void, Never>] = []
    private var refreshTask: Task<Void, Never>?
    private var popupPublishTask: Task<Void, Never>?
    private var wifiNameResolutionTask: Task<Void, Never>?
    private var previewAnimationTask: Task<Void, Never>?
    nonisolated(unsafe) private var wakeObserver: NSObjectProtocol?
    private var liveSnapshot: StatusSnapshot
    private var lastPublishedSnapshot: StatusSnapshot?
    private var hasStarted = false
    private var hasStopped = false
    private var isPopoverVisible = false
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
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        popupDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        previewAnimationSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        wakeNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
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
        self.previewAnimationSleep = previewAnimationSleep
        self.wakeNotificationCenter = wakeNotificationCenter
        self.liveSnapshot = initialSnapshot
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
        previewAnimationTask?.cancel()
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
        stopPreviewBatteryAnimation()
        wifiNetworks.deactivate()
        bluetoothDevices.deactivate()
    }

    var displayedSnapshot: StatusSnapshot {
        isPreviewEnabled ? previewStatus.snapshot : snapshot
    }

    var displayedVolume: VolumeStatus {
        displayedSnapshot.volume
    }

    var isVolumeControlAvailable: Bool {
        isPreviewEnabled || (volumeController != nil && liveVolume.scalar != nil)
    }

    func setPreviewEnabled(_ enabled: Bool) {
        guard !hasStopped, enabled != isPreviewEnabled else { return }
        if !enabled {
            stopPreviewBatteryAnimation()
        }
        isPreviewEnabled = enabled
        publishImmediately(enabled ? previewStatus.snapshot : liveSnapshot)
    }

    func togglePreviewBatteryAnimation() {
        if isPreviewBatteryAnimationRunning {
            stopPreviewBatteryAnimation()
        } else {
            startPreviewBatteryAnimation()
        }
    }

    func startPreviewBatteryAnimation() {
        guard !hasStopped else { return }
        previewAnimationTask?.cancel()
        setPreviewEnabled(true)
        isPreviewBatteryAnimationRunning = true
        previewAnimationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runPreviewBatteryAnimation()
        }
    }

    func stopPreviewBatteryAnimation() {
        previewAnimationTask?.cancel()
        previewAnimationTask = nil
        isPreviewBatteryAnimationRunning = false
    }

    func addPreviewOutputDevice(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = "Virtual Output \(previewStatus.virtualOutputDevices.count + 1)"
        let device = PreviewVirtualOutputDevice(
            id: nextPreviewOutputDeviceID(),
            name: trimmedName.isEmpty ? fallbackName : trimmedName
        )

        var next = previewStatus
        next.virtualOutputDevices.append(device)
        if next.selectedVirtualOutputDeviceID == nil {
            next.selectedVirtualOutputDeviceID = device.id
        }
        updatePreviewConfiguration(next)
    }

    func removePreviewOutputDevice(id: AudioDeviceID) {
        var next = previewStatus
        next.virtualOutputDevices.removeAll { $0.id == id }
        if next.selectedVirtualOutputDeviceID == id {
            next.selectedVirtualOutputDeviceID = next.virtualOutputDevices.first?.id
        }
        updatePreviewConfiguration(next)
    }

    func renamePreviewOutputDevice(id: AudioDeviceID, name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = previewStatus.virtualOutputDevices.firstIndex(where: { $0.id == id }) else {
            return
        }

        var next = previewStatus
        next.virtualOutputDevices[index].name = trimmedName
        updatePreviewConfiguration(next)
    }

    func selectPreviewOutputDevice(id: AudioDeviceID) {
        guard previewStatus.virtualOutputDevices.contains(where: { $0.id == id }) else { return }
        var next = previewStatus
        next.selectedVirtualOutputDeviceID = id
        updatePreviewConfiguration(next)
    }

    func updatePreview<Value>(
        _ keyPath: WritableKeyPath<PreviewStatusConfiguration, Value>,
        to value: Value
    ) {
        var next = previewStatus
        next[keyPath: keyPath] = value
        updatePreviewConfiguration(next)
    }

    func setVolume(_ scalar: Double) {
        guard !hasStopped else { return }
        if isPreviewEnabled {
            updatePreview(
                \.volumeScalar,
                to: min(1, max(0, scalar))
            )
            return
        }

        guard volumeController != nil, scalar.isFinite else { return }
        liveVolume = liveVolume.replacingScalar(min(1, max(0, scalar)))
        liveSnapshot = liveSnapshot.replacingVolume(liveVolume)
        publish(liveSnapshot)
        volumeController?.setVolume(liveVolume.scalar ?? 0)
    }

    func toggleMute() {
        guard !hasStopped else { return }
        if isPreviewEnabled {
            updatePreview(\.isMuted, to: !previewStatus.isMuted)
            return
        }

        guard volumeController != nil, liveVolume.scalar != nil else { return }
        liveVolume = liveVolume.replacingMuted(!liveVolume.isMuted)
        liveSnapshot = liveSnapshot.replacingVolume(liveVolume)
        publish(liveSnapshot)
        volumeController?.toggleMute()
    }

    func selectOutputDevice(_ device: AudioOutputDevice) {
        guard !hasStopped else { return }
        if isPreviewEnabled {
            selectPreviewOutputDevice(id: device.id)
            return
        }
        volumeController?.selectOutputDevice(device.id)
    }

    func requestWiFiNameAccess() {
        guard !hasStopped, !isPreviewEnabled else { return }
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
    }

    /// Whether a popover detail panel (Wi-Fi or Bluetooth list) is currently open.
    var hasActivePopoverDetails: Bool {
        wifiNetworks.isActive || isBluetoothDetailsOpen
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

    private func updatePreviewConfiguration(_ next: PreviewStatusConfiguration) {
        guard next != previewStatus else { return }
        previewStatus = next
        if isPreviewEnabled {
            publishImmediately(next.snapshot)
        }
    }

    private func nextPreviewOutputDeviceID() -> AudioDeviceID {
        (previewStatus.virtualOutputDevices.map(\.id).max() ?? 999) + 1
    }

    private func applyBattery(_ value: BatteryStatus) {
        liveSnapshot = liveSnapshot.replacingBattery(value)
        publishLiveSnapshot()
    }

    private func applyWiFi(_ value: WiFiStatus) {
        liveSnapshot = liveSnapshot.replacingWiFi(value)
        publishLiveSnapshot()
        wifiNetworks.refresh(nameAccess: value.nameAccess)
    }

    private func applyConnection(_ value: NetworkConnection) {
        // Preview branch adaptation: main treats snapshot as the canonical state,
        // while this branch keeps a separate liveSnapshot so Preview data can be
        // isolated. Keep this implementation Preview-only during future merges.
        liveSnapshot = liveSnapshot.replacingConnection(value)
        publishLiveSnapshot()
    }

    private func applyVolume(_ value: VolumeStatus) {
        liveVolume = value
        liveSnapshot = liveSnapshot.replacingVolume(value)
        publishLiveSnapshot()
    }

    private func runPreviewBatteryAnimation() async {
        defer {
            if !Task.isCancelled {
                isPreviewBatteryAnimationRunning = false
            }
        }

        for frame in PreviewBatteryAnimation.frames {
            guard !Task.isCancelled, isPreviewEnabled else { return }
            applyPreviewBatteryAnimationFrame(frame)

            do {
                try await previewAnimationSleep(PreviewBatteryAnimation.frameInterval)
            } catch {
                return
            }
        }
    }

    private func applyPreviewBatteryAnimationFrame(_ frame: PreviewBatteryAnimationFrame) {
        var next = previewStatus
        next.batteryPercentage = frame.percentage
        next.isBatteryPresent = true
        next.isCharging = frame.isCharging
        next.isCharged = frame.isCharged
        next.isLowPowerMode = frame.isLowPowerMode
        next.isConnectedToPower = frame.isConnectedToPower

        guard next != previewStatus else { return }
        previewStatus = next
        if isPreviewEnabled {
            publishImmediately(next.snapshot)
        }
    }

    private func publishLiveSnapshot() {
        guard !isPreviewEnabled else { return }
        publish(liveSnapshot)
    }

    private func publishImmediately(_ next: StatusSnapshot) {
        guard !hasStopped else { return }
        lastPublishedSnapshot = next
        snapshot = next
        popupSnapshot = next
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
            guard !Task.isCancelled,
                  !self.isPreviewEnabled,
                  next == self.liveSnapshot else { return }
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
            outputDevices: outputDevices
        )
    }

    func replacingMuted(_ isMuted: Bool) -> VolumeStatus {
        VolumeStatus(
            scalar: scalar,
            isMuted: isMuted,
            deviceName: deviceName,
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
