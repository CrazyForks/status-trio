import Combine
import Foundation

/// The existing battery icon monitor remains event-driven. Only the expanded
/// details view owns this collector; closing it ends all periodic work.
@MainActor
final class BatteryDetailsController: ObservableObject {
    typealias Reader = @Sendable (BatteryPowerState, Date?) -> BatteryDetails
    @Published private(set) var details: BatteryDetails?
    private let reader: Reader
    private static let queue = DispatchQueue(label: "com.lingsmbp.StatusTrio.battery-details", qos: .utility)
    private var active = false
    private var state: BatteryPowerState?
    private var notBefore: Date?
    private var generation = 0
    private var inFlight = false
    private var needsRefresh = false

    init(reader: @escaping Reader = { BatteryDetailsReader().read(state: $0, notBefore: $1) }) {
        self.reader = reader
    }

    func activate(state: BatteryPowerState, now: Date = Date()) {
        if let previous = self.state, previous != state {
            notBefore = now
        }
        self.state = state
        active = true
        generation += 1
        details = nil
        refresh()
    }

    func deactivate() {
        active = false
        generation += 1
        needsRefresh = false
        details = nil
    }

    func refresh() {
        guard active, let state else { return }
        guard !inFlight else {
            needsRefresh = true
            return
        }
        inFlight = true
        needsRefresh = false
        let generation = generation
        let notBefore = notBefore
        let reader = reader
        Self.queue.async { [weak self] in
            guard self != nil else { return }
            let result = reader(state, notBefore)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                if self.active && self.generation == generation {
                    self.details = result
                }
                if self.needsRefresh { self.refresh() }
            }
        }
    }
}
