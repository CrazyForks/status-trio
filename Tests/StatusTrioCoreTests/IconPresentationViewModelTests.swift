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
        let model = IconPresentationViewModel(
            snapshot: snapshots.value,
            settings: preferences.value,
            snapshots: snapshots.eraseToAnyPublisher(),
            preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationInputs(snapshot: $0, audioIcon: nil) }
        )
        var delivered: [IconPresentationOutput] = []
        let subscription = model.$output.dropFirst().sink { delivered.append($0) }

        model.start()
        model.start()
        snapshots.send(PresentationFixtures.snapshot(rssi: -80))
        XCTAssertEqual(delivered.count, 1)

        model.stop()
        snapshots.send(PresentationFixtures.snapshot(rssi: -50))
        XCTAssertEqual(delivered.count, 1)

        model.start()
        XCTAssertEqual(delivered.count, 2)
        XCTAssertEqual(delivered.last?.scene, IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshots.value, audioIcon: nil),
            configuration: .standard
        ))

        subscription.cancel()
        model.stop()
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
        preferences.send(IconPresentationSettings(configuration: .standard, menuBarSize: 30, testsChargingEffect: false))

        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.last?.menuBarSize, 30)
        XCTAssertEqual(delivered.last?.scene, initialScene)

        preferences.send(IconPresentationSettings(
            configuration: IconPresentationConfiguration(
                battery: BatteryIconOptions(showsPercentage: false),
                connection: .standard,
                volume: .standard,
                bluetooth: .standard
            ),
            menuBarSize: 32,
            testsChargingEffect: true
        ))
        XCTAssertEqual(delivered.last?.menuBarSize, 32)
        XCTAssertEqual(model.output, delivered.last)
        XCTAssertNotEqual(delivered.last?.scene, delivered.first?.scene)

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
}
