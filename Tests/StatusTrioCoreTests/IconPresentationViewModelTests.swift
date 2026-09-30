import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconPresentationViewModelTests: XCTestCase {
    func testInitPublishesInitialOutputAndStatusChangesPublishOneCompleteOutput() {
        let initialSnapshot = PresentationFixtures.snapshot()
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(initialSnapshot)
        let initialSettings = IconPresentationSettings(
            configuration: .standard,
            menuBarSize: 28,
            testsChargingEffect: false
        )
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(initialSettings)
        let model = IconPresentationViewModel(
            snapshot: snapshots.value,
            settings: preferences.value,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) }
        )

        var delivered: [IconPresentationOutput] = []
        let subscription = model.$output.sink { delivered.append($0) }
        XCTAssertEqual(delivered, [model.output])

        model.start()
        snapshots.send(PresentationFixtures.snapshot(rssi: -62, scalar: 0.74))

        XCTAssertEqual(delivered.count, 1)
        snapshots.send(PresentationFixtures.snapshot(rssi: -80, scalar: 0.1))

        XCTAssertEqual(delivered.count, 2)
        XCTAssertEqual(delivered.last?.menuBarSize, 28)
        XCTAssertNotEqual(delivered.last?.scene, delivered.first?.scene)
        subscription.cancel()
        model.stop()
    }

    func testStartIsIdempotentStopCancelsAndRestartUsesCurrentValues() {
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(PresentationFixtures.snapshot())
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(
            IconPresentationSettings(configuration: .standard, menuBarSize: 28, testsChargingEffect: false)
        )
        var snapshotSubscriptions = 0
        var snapshotCancellations = 0
        var preferenceSubscriptions = 0
        var preferenceCancellations = 0
        let snapshotPublisher = snapshots
            .handleEvents(
                receiveSubscription: { _ in snapshotSubscriptions += 1 },
                receiveCancel: { snapshotCancellations += 1 }
            )
            .eraseToAnyPublisher()
        let preferencePublisher = preferences
            .handleEvents(
                receiveSubscription: { _ in preferenceSubscriptions += 1 },
                receiveCancel: { preferenceCancellations += 1 }
            )
            .eraseToAnyPublisher()
        let model = IconPresentationViewModel(
            snapshot: snapshots.value,
            settings: preferences.value,
            snapshots: snapshotPublisher,
            preferences: preferencePublisher,
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) }
        )
        var delivered: [IconPresentationOutput] = []
        let subscription = model.$output.dropFirst().sink { delivered.append($0) }

        XCTAssertEqual(snapshotSubscriptions, 0)
        XCTAssertEqual(preferenceSubscriptions, 0)
        model.start()
        model.start()
        XCTAssertEqual(snapshotSubscriptions, 1)
        XCTAssertEqual(preferenceSubscriptions, 1)
        snapshots.send(PresentationFixtures.snapshot(rssi: -80))
        XCTAssertEqual(delivered.count, 1)

        model.stop()
        XCTAssertEqual(snapshotCancellations, 1)
        XCTAssertEqual(preferenceCancellations, 1)
        snapshots.send(PresentationFixtures.snapshot(rssi: -50))
        XCTAssertEqual(delivered.count, 1)

        model.start()
        XCTAssertEqual(snapshotSubscriptions, 2)
        XCTAssertEqual(preferenceSubscriptions, 2)
        XCTAssertEqual(delivered.count, 2)
        XCTAssertEqual(delivered.last?.scene, IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshots.value, audioIcon: nil),
            configuration: .standard
        ))

        subscription.cancel()
        model.stop()
        XCTAssertEqual(snapshotCancellations, 2)
        XCTAssertEqual(preferenceCancellations, 2)
    }

    func testSettingsPublishWholeLatestValueAndSizeDoesNotChangeScene() {
        let snapshot = PresentationFixtures.snapshot()
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(snapshot)
        let initial = IconPresentationSettings(configuration: .standard, menuBarSize: 28, testsChargingEffect: false)
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(initial)
        let model = IconPresentationViewModel(
            snapshot: snapshot,
            settings: initial,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) }
        )
        var delivered: [IconPresentationOutput] = []
        let subscription = model.$output.dropFirst().sink { delivered.append($0) }
        model.start()

        let initialScene = model.output.scene
        let sizeOnly = IconPresentationSettings(configuration: .standard, menuBarSize: 30, testsChargingEffect: false)
        preferences.send(sizeOnly)

        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.last, expectedOutput(snapshot: snapshot, settings: sizeOnly))
        XCTAssertEqual(delivered.last?.scene, initialScene)

        let configurationOnly = IconPresentationSettings(
            configuration: IconPresentationConfiguration(
                battery: BatteryIconOptions(showsPercentage: false),
                connection: .standard,
                volume: .standard,
                bluetooth: .standard
            ),
            menuBarSize: 30,
            testsChargingEffect: false
        )
        preferences.send(configurationOnly)
        XCTAssertEqual(delivered.count, 2)
        XCTAssertEqual(delivered.last, expectedOutput(snapshot: snapshot, settings: configurationOnly))
        XCTAssertNotEqual(delivered.last?.scene, delivered.first?.scene)

        let chargingTestMode = IconPresentationSettings(
            configuration: configurationOnly.configuration,
            menuBarSize: 32,
            testsChargingEffect: true
        )
        preferences.send(chargingTestMode)
        XCTAssertEqual(delivered.count, 3)
        XCTAssertEqual(delivered.last, expectedOutput(snapshot: snapshot, settings: chargingTestMode))
        XCTAssertEqual(model.output, expectedOutput(snapshot: snapshot, settings: chargingTestMode))

        subscription.cancel()
        model.stop()
    }

    func testChargingEffectTestModeProjectsSnapshotWithoutChangingOriginal() {
        let original = PresentationFixtures.snapshot()
        XCTAssertFalse(original.battery.isCharging)
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(original)
        let settings = IconPresentationSettings(configuration: .standard, menuBarSize: 28, testsChargingEffect: true)
        let model = IconPresentationViewModel(
            snapshot: original,
            settings: settings,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: Just(settings).eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) }
        )

        XCTAssertNotNil(model.output.scene.outerRing?.effect)
        XCTAssertFalse(original.battery.isCharging)
        XCTAssertFalse(model.output.scene.outerRing?.accessory == nil)
    }

    private func expectedOutput(
        snapshot: StatusSnapshot,
        settings: IconPresentationSettings
    ) -> IconPresentationOutput {
        let projected = ChargingEffectTestMode.snapshot(snapshot, enabled: settings.testsChargingEffect)
        let inputs = IconPresentationInputs(snapshot: projected, audioIcon: nil)
        return IconPresentationOutput(
            scene: IconPresentationMapper.scene(inputs: inputs, configuration: settings.configuration),
            menuBarSize: settings.menuBarSize
        )
    }
}
