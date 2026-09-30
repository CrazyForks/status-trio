import Combine
import Foundation

struct IconPresentationSettings: Equatable, Sendable {
    let configuration: IconPresentationConfiguration
    let menuBarSize: Double
    let testsChargingEffect: Bool
}

struct IconPresentationOutput: Equatable, Sendable {
    let scene: IconSceneState
    let menuBarSize: Double
}

@MainActor
final class IconPresentationViewModel: ObservableObject {
    @Published private(set) var output: IconPresentationOutput

    private let snapshots: AnyPublisher<StatusSnapshot, Never>
    private let preferences: AnyPublisher<IconPresentationSettings, Never>
    private let resolveInputs: @MainActor (StatusSnapshot) -> IconPresentationInputs
    private var subscription: AnyCancellable?

    init(
        snapshot: StatusSnapshot,
        settings: IconPresentationSettings,
        snapshots: AnyPublisher<StatusSnapshot, Never>,
        preferences: AnyPublisher<IconPresentationSettings, Never>,
        resolveInputs: @escaping @MainActor (StatusSnapshot) -> IconPresentationInputs
    ) {
        self.snapshots = snapshots
        self.preferences = preferences
        self.resolveInputs = resolveInputs
        self.output = Self.output(snapshot: snapshot, settings: settings, resolveInputs: resolveInputs)
    }

    func start() {
        guard subscription == nil else { return }

        subscription = snapshots
            .combineLatest(preferences)
            .map { [resolveInputs] snapshot, settings in
                Self.output(snapshot: snapshot, settings: settings, resolveInputs: resolveInputs)
            }
            .removeDuplicates()
            .sink { [weak self] next in
                MainActor.assumeIsolated {
                    guard let self, self.output != next else { return }
                    self.output = next
                }
            }
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
    }

    private static func output(
        snapshot: StatusSnapshot,
        settings: IconPresentationSettings,
        resolveInputs: @MainActor (StatusSnapshot) -> IconPresentationInputs
    ) -> IconPresentationOutput {
        let projected = ChargingEffectTestMode.snapshot(snapshot, enabled: settings.testsChargingEffect)
        return IconPresentationOutput(
            scene: IconPresentationMapper.scene(
                inputs: resolveInputs(projected),
                configuration: settings.configuration
            ),
            menuBarSize: settings.menuBarSize
        )
    }
}
