import Combine
import Foundation

/// The one owner of periodic whole-machine (`PSTR`) power reads.
///
/// The menu-bar/Dock centre slot, the status panel summary and the battery
/// details page each need a system power reading. They register a demand here
/// instead of starting their own timer, so one surface ending never cuts the
/// sample another surface is still using, and the SMC is never read twice for
/// the same refresh.
///
/// Cadence follows the active demand: a panel or a details page is being read
/// by a person, so it gets the 2-second detail rhythm; an icon that keeps
/// showing watts while the panel is closed uses the 5-second idle rhythm.
@MainActor
final class PowerSamplingService: ObservableObject {
    enum Demand: Hashable, Sendable {
        /// The centre slot is set to show watts.
        case icon
        /// The status panel can present power (the battery summary or a
        /// no-battery device's power title).
        case panel
        /// The battery details page is open.
        case details
    }

    typealias Reader = @Sendable () -> SystemPowerSample?

    static let detailedInterval: Duration = .seconds(2)
    static let iconOnlyInterval: Duration = .seconds(5)

    @Published private(set) var systemPower: SystemPowerSample?
    /// Exposed for tests and diagnostics; production reads `wantsDetailedCadence`.
    private(set) var demands: Set<Demand> = []
    private(set) var isRunning = false

    var wantsDetailedCadence: Bool {
        demands.contains(.panel) || demands.contains(.details)
    }

    var currentInterval: Duration {
        wantsDetailedCadence ? Self.detailedInterval : Self.iconOnlyInterval
    }

    private static let queue = DispatchQueue(
        label: "com.lingsmbp.StatusTrio.power-sampling",
        qos: .utility
    )
    private let reader: Reader
    private var loopTask: Task<Void, Never>?
    private var generation = 0
    private var inFlight = false
    private var needsRefresh = false

    init(reader: @escaping Reader = { SystemPowerReader().read() }) {
        self.reader = reader
    }

    deinit { loopTask?.cancel() }

    /// Idempotent: calling `begin` for a demand already registered does nothing.
    func begin(_ demand: Demand) {
        guard demands.insert(demand).inserted else { return }
        if !isRunning {
            isRunning = true
            startLoop()
        }
        // The first demand or a cadence change must not wait a full cycle.
        refresh()
    }

    func end(_ demand: Demand) {
        guard demands.remove(demand) != nil else { return }
        if demands.isEmpty { stopLoop() }
    }

    func stopAll() {
        demands.removeAll()
        stopLoop()
    }

    /// Reads now instead of waiting for the next tick. Tests use it; production
    /// reaches the same path through `begin` and the loop.
    func refresh() {
        guard isRunning else { return }
        if inFlight {
            needsRefresh = true
            return
        }
        inFlight = true
        needsRefresh = false
        let generation = generation
        let reader = reader
        Self.queue.async { [weak self] in
            let sample = reader()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                if self.isRunning, self.generation == generation, let sample {
                    if self.systemPower != sample { self.systemPower = sample }
                }
                if self.needsRefresh {
                    self.needsRefresh = false
                    self.refresh()
                }
            }
        }
    }

    private func startLoop() {
        generation += 1
        loopTask?.cancel()
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.currentInterval
                do {
                    try await Task.sleep(for: interval, tolerance: .milliseconds(200))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
        isRunning = false
        generation += 1
        needsRefresh = false
        // A stopped sampler must not leave a value behind for a surface that
        // opens later; a fresh demand starts a new read.
        if systemPower != nil { systemPower = nil }
    }
}
