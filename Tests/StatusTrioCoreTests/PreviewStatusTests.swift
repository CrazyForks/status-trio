import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class PreviewStatusTests: XCTestCase {
    func testPreviewConfigurationBuildsCompleteSnapshot() {
        var preview = PreviewStatusConfiguration.standard
        preview.batteryPercentage = 17
        preview.isBatteryPresent = true
        preview.isCharging = true
        preview.isCharged = false
        preview.isLowPowerMode = true
        preview.isConnectedToPower = true
        preview.wifiState = .noInternet
        preview.wifiRSSI = -72
        preview.wifiSSID = "Preview Network"
        preview.volumeScalar = 0.35
        preview.isMuted = true

        let snapshot = preview.snapshot

        XCTAssertEqual(snapshot.battery.rawPercentage, 17)
        XCTAssertTrue(snapshot.battery.isPresent)
        XCTAssertTrue(snapshot.battery.isCharging)
        XCTAssertFalse(snapshot.battery.isCharged)
        XCTAssertTrue(snapshot.battery.isLowPowerMode)
        XCTAssertTrue(snapshot.battery.isConnectedToPower)
        XCTAssertEqual(snapshot.wifi.state, .noInternet)
        XCTAssertEqual(snapshot.wifi.rssi, -72)
        XCTAssertEqual(snapshot.wifi.ssid, "Preview Network")
        XCTAssertEqual(snapshot.volume.scalar, 0.35)
        XCTAssertTrue(snapshot.volume.isMuted)
        XCTAssertEqual(snapshot.volume.outputDevices.first?.isCurrent, true)
    }

    func testPreviewModeUsesStaticSnapshotAndIgnoresRealUpdates() async {
        let battery = PreviewFakeBatteryMonitor()
        let store = makeStore(battery: battery)
        store.start()
        store.setPreviewEnabled(true)
        store.updatePreview(\.batteryPercentage, to: 37)

        var cancellables = Set<AnyCancellable>()
        let realUpdatePublished = expectation(description: "real update remains hidden")
        realUpdatePublished.isInverted = true
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                if snapshot.battery.percentage == 91 {
                    realUpdatePublished.fulfill()
                }
            }
            .store(in: &cancellables)

        battery.send(makeBattery(percentage: 91))
        await fulfillment(of: [realUpdatePublished], timeout: 0.1)

        XCTAssertTrue(store.isPreviewEnabled)
        XCTAssertEqual(store.snapshot.battery.percentage, 37)
        cancellables.removeAll()
        store.stop()
    }

    func testDisablingPreviewRestoresLatestRealSnapshot() async {
        let battery = PreviewFakeBatteryMonitor()
        let store = makeStore(battery: battery)

        store.start()
        battery.send(makeBattery(percentage: 42))
        for _ in 0..<20 where store.snapshot.battery.percentage != 42 {
            await Task.yield()
        }
        XCTAssertEqual(store.snapshot.battery.percentage, 42)

        store.setPreviewEnabled(true)
        store.updatePreview(\.batteryPercentage, to: 5)
        XCTAssertEqual(store.snapshot.battery.percentage, 5)

        store.setPreviewEnabled(false)

        XCTAssertFalse(store.isPreviewEnabled)
        XCTAssertEqual(store.snapshot.battery.percentage, 42)
        store.stop()
    }

    func testPreviewSnapshotUpdatesBypassLiveDebounce() {
        XCTAssertFalse(
            StatusBarController.shouldDebounceSnapshotUpdates(isPreviewEnabled: true)
        )
        XCTAssertTrue(
            StatusBarController.shouldDebounceSnapshotUpdates(isPreviewEnabled: false)
        )
    }

    func testBatteryAnimationDrainsToZeroThenChargesBackToFull() throws {
        let frames = PreviewBatteryAnimation.frames

        XCTAssertEqual(frames.first?.percentage, 100)
        XCTAssertFalse(frames.first?.isCharging ?? true)
        XCTAssertFalse(frames.first?.isConnectedToPower ?? true)

        let zeroIndex = try XCTUnwrap(frames.firstIndex { $0.percentage == 0 })
        XCTAssertTrue(frames[zeroIndex].isCharging)
        XCTAssertTrue(frames[zeroIndex].isConnectedToPower)

        XCTAssertEqual(frames[zeroIndex + 1].percentage, 1)
        XCTAssertTrue(frames[zeroIndex + 1].isCharging)
        XCTAssertEqual(frames.last?.percentage, 100)
        XCTAssertTrue(frames.last?.isCharged ?? false)
        XCTAssertFalse(frames.last?.isCharging ?? true)
        XCTAssertGreaterThanOrEqual(frames.count, 200)
    }

    func testStartingBatteryAnimationEnablesPreviewAndFinishesCharged() async {
        let store = SystemStatusStore(
            batteryMonitor: PreviewFakeBatteryMonitor(),
            wifiMonitor: PreviewFakeWiFiMonitor(),
            volumeMonitor: PreviewFakeVolumeMonitor(),
            refreshInterval: .seconds(60),
            previewAnimationSleep: { _ in }
        )

        store.togglePreviewBatteryAnimation()
        for _ in 0..<1_000 where store.isPreviewBatteryAnimationRunning {
            await Task.yield()
        }

        XCTAssertTrue(store.isPreviewEnabled)
        XCTAssertFalse(store.isPreviewBatteryAnimationRunning)
        XCTAssertEqual(store.previewStatus.batteryPercentage, 100)
        XCTAssertFalse(store.previewStatus.isCharging)
        XCTAssertTrue(store.previewStatus.isCharged)
        XCTAssertTrue(store.previewStatus.isConnectedToPower)
    }

    func testPreviewVolumeControlsUpdateStaticSnapshot() {
        let store = makeStore(battery: PreviewFakeBatteryMonitor())
        store.setPreviewEnabled(true)

        XCTAssertTrue(store.isVolumeControlAvailable)
        store.setVolume(0.25)
        store.toggleMute()

        XCTAssertEqual(store.snapshot.volume.scalar, 0.25)
        XCTAssertTrue(store.snapshot.volume.isMuted)
    }

    private func makeStore(battery: PreviewFakeBatteryMonitor) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: PreviewFakeWiFiMonitor(),
            volumeMonitor: PreviewFakeVolumeMonitor(),
            refreshInterval: .seconds(60),
            popupDebounceSleep: { _ in }
        )
    }

    private func makeBattery(percentage: Int) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
    }
}

@MainActor
private final class PreviewFakeBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
    func send(_ value: BatteryStatus) { continuation.yield(value) }
}

@MainActor
private final class PreviewFakeWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private let continuation: AsyncStream<WiFiStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
    func requestNameAccess() {}
}

@MainActor
private final class PreviewFakeVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    private let continuation: AsyncStream<VolumeStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
}
