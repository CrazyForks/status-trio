import AppKit
import Combine
import Foundation

@MainActor
final class ApplicationEnergyController: ObservableObject {
    typealias Reader = @Sendable ([EnergyApplication]) -> ApplicationEnergySnapshot
    @Published private(set) var ranking = ApplicationEnergyRanking()
    private let reader: Reader
    private let applications: @MainActor () -> [EnergyApplication]
    private static let queue = DispatchQueue(label: "com.lingsmbp.StatusTrio.application-energy", qos: .utility)
    private var previous: ApplicationEnergySnapshot?
    private var active = false
    private var generation = 0
    private var inFlight = false
    private var needsRefresh = false
    private var refreshTask: Task<Void, Never>?

    init(reader: @escaping Reader = { ApplicationEnergyReader().read(applications: $0) },
         applications: @escaping @MainActor () -> [EnergyApplication] = {
             NSWorkspace.shared.runningApplications.compactMap { app in
                 guard !app.isTerminated, app.activationPolicy != .prohibited,
                       let url = app.bundleURL, let name = app.localizedName else { return nil }
                 return EnergyApplication(id: url.path, name: name)
             }
         }) {
        self.reader = reader
        self.applications = applications
    }

    deinit { refreshTask?.cancel() }

    func activate() {
        guard !active else { return }
        active = true
        generation += 1
        previous = nil
        ranking = ApplicationEnergyRanking()
        refresh()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5), tolerance: .milliseconds(500)) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func deactivate() {
        guard active else { return }
        active = false
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        previous = nil
        needsRefresh = false
        ranking = ApplicationEnergyRanking()
    }

    func refresh(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard active else { return }
        if let previous, now - previous.readAt > 15 {
            self.previous = nil
            ranking = ApplicationEnergyRanking()
        }
        guard !inFlight else { needsRefresh = true; return }
        inFlight = true
        needsRefresh = false
        let generation = generation
        let applications = applications()
        let reader = reader
        Self.queue.async { [weak self] in
            guard self != nil else { return }
            let snapshot = reader(applications)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                if self.active && self.generation == generation {
                    // A blocked read must not publish a stale ranking.
                    if (0...15).contains(ProcessInfo.processInfo.systemUptime - snapshot.readAt) {
                        self.ranking = ApplicationEnergyRanking.rank(previous: self.previous, current: snapshot)
                        self.previous = snapshot
                    } else {
                        self.previous = nil
                        self.ranking = ApplicationEnergyRanking()
                    }
                }
                if self.needsRefresh { self.refresh() }
            }
        }
    }
}
