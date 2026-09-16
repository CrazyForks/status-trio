import Foundation

struct WiFiStatusReading: Sendable {
    let interface: WiFiSystemReading?
    let sharingActive: Bool
}

@MainActor
protocol WiFiStatusReadingProviding: AnyObject {
    func read(
        includeSSID: Bool,
        completion: @escaping @MainActor @Sendable (WiFiStatusReading) -> Void
    )
}

/// CoreWLAN and SystemConfiguration reads are synchronous IPC. Keep them off
/// both the main actor and Swift's cooperative executor, on one serial queue.
@MainActor
final class CoreWLANStatusReader: WiFiStatusReadingProviding {
    private let queue = DispatchQueue(label: "StatusTrio.WiFiStatusReader", qos: .utility)
    private let readSystem: @Sendable (Bool) -> WiFiStatusReading

    init(readSystem: @escaping @Sendable (Bool) -> WiFiStatusReading = { includeSSID in
        let reading = CoreWLANWiFiSystemReader().read(includeSSID: includeSSID)
        let sharing = reading.map { $0.powerOn && $0.serviceActive } == true
            && SystemInternetSharingDetector().isActive() == true
        return WiFiStatusReading(interface: reading, sharingActive: sharing)
    }) {
        self.readSystem = readSystem
    }

    func read(
        includeSSID: Bool,
        completion: @escaping @MainActor @Sendable (WiFiStatusReading) -> Void
    ) {
        let readSystem = readSystem
        queue.async {
            let reading = readSystem(includeSSID)
            Task { @MainActor in completion(reading) }
        }
    }
}
