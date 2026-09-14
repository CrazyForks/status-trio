import AppKit
import Combine
import Foundation

@MainActor
final class SystemStatusStore: ObservableObject {
    static let popupDebounceInterval: Duration = .milliseconds(500)

    @Published private(set) var snapshot: StatusSnapshot
    @Published private(set) var popupSnapshot: StatusSnapshot
    @Published private(set) var isPreviewEnabled = false
    @Published private(set) var isPreviewBatteryAnimationRunning = false
    @Published private(set) var previewStatus = PreviewStatusConfiguration.standard
    @Published private(set) var liveVolume: VolumeStatus

    private let batteryMonitor: any BatteryMonitoring
    private let wifiMonitor: any WiFiMonitoring
    private let volumeMonitor: any VolumeMonitoring
    private let volumeController: (any VolumeControlling)?
    private let refreshInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let popupDebounceSleep: @Sendable (Duration) async throws -> Void
    private let previewAnimationSleep: @Sendable (Duration) async throws -> Void
    private let wakeNotificationCenter: NotificationCenter
    private var monitorTasks: [Task<Void, Never>] = []
    private var refreshTask: Task<Void, Never>?
    private var popupPublishTask: Task<Void, Never>?
    private var previewAnimationTask: Task<Void, Never>?
    nonisolated(unsafe) private var wakeObserver: NSObjectProtocol?
    private var liveSnapshot: StatusSnapshot
    private var lastPublishedSnapshot: StatusSnapshot?
    private var hasStarted = false
    private var hasStopped = false

    init(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        volumeMonitor: any VolumeMonitoring,
        refreshInterval: Duration = .seconds(5),
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
        initialSnapshot: StatusSnapshot = .placeholder
    ) {
        self.batteryMonitor = batteryMonitor
        self.wifiMonitor = wifiMonitor
        self.volumeMonitor = volumeMonitor
        self.volumeController = volumeMonitor as? any VolumeControlling
        self.refreshInterval = refreshInterval
        self.sleep = sleep
        self.popupDebounceSleep = popupDebounceSleep
        self.previewAnimationSleep = previewAnimationSleep
        self.wakeNotificationCenter = wakeNotificationCenter
        self.liveSnapshot = initialSnapshot
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
        volumeMonitor.start()

        let batteryUpdates = batteryMonitor.updates
        let wifiUpdates = wifiMonitor.updates
        let volumeUpdates = volumeMonitor.updates
        monitorTasks = [
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

        let refreshInterval = refreshInterval
        let sleep = sleep
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(refreshInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.refreshAll()
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
        volumeMonitor.stop()
        monitorTasks.forEach { $0.cancel() }
        monitorTasks.removeAll()
        refreshTask?.cancel()
        refreshTask = nil
        popupPublishTask?.cancel()
        popupPublishTask = nil
        stopPreviewBatteryAnimation()
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

    func updatePreview<Value>(
        _ keyPath: WritableKeyPath<PreviewStatusConfiguration, Value>,
        to value: Value
    ) {
        var next = previewStatus
        next[keyPath: keyPath] = value
        guard next != previewStatus else { return }
        previewStatus = next
        if isPreviewEnabled {
            publishImmediately(next.snapshot)
        }
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
        guard !hasStopped, !isPreviewEnabled else { return }
        volumeController?.selectOutputDevice(device.id)
    }

    func requestWiFiNameAccess() {
        guard !hasStopped, !isPreviewEnabled else { return }
        wifiMonitor.requestNameAccess()
    }

    func refreshForPopoverOpening() {
        guard !hasStopped else { return }
        popupPublishTask?.cancel()
        popupPublishTask = nil
        popupSnapshot = snapshot
        refreshAll()
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
        volumeMonitor.recover()
    }

    private func applyBattery(_ value: BatteryStatus) {
        liveSnapshot = liveSnapshot.replacingBattery(value)
        publishLiveSnapshot()
    }

    private func applyWiFi(_ value: WiFiStatus) {
        liveSnapshot = liveSnapshot.replacingWiFi(value)
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
            self.popupSnapshot = next
        }
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
        StatusSnapshot(battery: value, wifi: wifi, volume: volume)
    }

    func replacingWiFi(_ value: WiFiStatus) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: value, volume: volume)
    }

    func replacingVolume(_ value: VolumeStatus) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, volume: value)
    }
}
