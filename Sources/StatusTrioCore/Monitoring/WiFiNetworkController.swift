import CoreWLAN
import Foundation
import SystemConfiguration

struct WiFiServiceNetworkConfiguration {
    let ipv4Addresses: [String]
    let ipv6Addresses: [String]
    let router: String?
    let dnsServers: [String]

    static let unavailable = Self(ipv4Addresses: [], ipv6Addresses: [], router: nil, dnsServers: [])

    static func resolve(interface: String, snapshot: [String: [String: Any]]) -> Self {
        let prefix = "State:/Network/Service/"
        let serviceIDs = Set(snapshot.keys.compactMap { key -> String? in
            guard key.hasPrefix(prefix) else { return nil }
            return key.dropFirst(prefix.count).split(separator: "/", maxSplits: 1).first.map(String.init)
        })
        let candidates = serviceIDs.filter { serviceID in
            let base = prefix + serviceID
            return string(snapshot[base + "/Interface"], key: "DeviceName") == interface
                || string(snapshot[base + "/IPv4"], key: "InterfaceName") == interface
                || string(snapshot[base + "/IPv6"], key: "InterfaceName") == interface
        }
        let primary = string(snapshot["State:/Network/Global/IPv4"], key: "PrimaryService")
        let selected: String?
        if candidates.count == 1 {
            selected = candidates.first
        } else if let primary, candidates.contains(primary) {
            selected = primary
        } else {
            selected = nil
        }
        guard let selected else { return .unavailable }
        let base = prefix + selected
        let ipv4 = snapshot[base + "/IPv4"]
        let ipv6 = snapshot[base + "/IPv6"]
        let dns = snapshot[base + "/DNS"]
        return Self(
            ipv4Addresses: strings(ipv4, key: "Addresses"),
            ipv6Addresses: strings(ipv6, key: "Addresses"),
            router: string(ipv4, key: "Router"),
            dnsServers: strings(dns, key: "ServerAddresses")
        )
    }

    private static func string(_ dictionary: [String: Any]?, key: String) -> String? {
        dictionary?[key] as? String
    }

    private static func strings(_ dictionary: [String: Any]?, key: String) -> [String] {
        if let values = dictionary?[key] as? [String] { return values }
        if let value = dictionary?[key] as? String { return [value] }
        return []
    }
}

struct WiFiScanPayload: Sendable {
    let networks: [WiFiNetwork]
    let details: WiFiConnectionDetails
}

enum WiFiScanWorkerResult: Sendable {
    case success(WiFiScanPayload)
    case poweredOff
    case noInterface
    case failed
}

enum WiFiAssociationWorkerResult: Sendable {
    case success(WiFiConnectionDetails)
    case networkUnavailable
    case timedOut
    case failed
}

/// The scan, power and association calls the network list needs. CoreWLAN is
/// synchronous and serialized on the worker's own queue; the protocol exists so
/// a test can answer instantly and count the scans, which is how the cadence is
/// observable without sweeping every channel.
protocol WiFiNetworkScanning: AnyObject {
    func scan(completion: @escaping @Sendable (WiFiScanWorkerResult) -> Void)
    func setPower(_ isOn: Bool, completion: @escaping @Sendable (Bool) -> Void)
    func associate(
        to network: WiFiNetwork,
        password: String?,
        completion: @escaping @Sendable (WiFiAssociationWorkerResult) -> Void
    )
}

/// CoreWLAN exposes synchronous scan and association APIs. This worker owns a
/// serial queue so those calls never run on the main actor and cannot overlap.
private final class CoreWLANNetworkWorker: @unchecked Sendable, WiFiNetworkScanning {
    private let queue = DispatchQueue(label: "StatusTrio.CoreWLANNetworkWorker")
    private let knownNetworkProvider: any WiFiKnownNetworkProviding

    init(
        knownNetworkProvider: any WiFiKnownNetworkProviding = NetworksetupWiFiKnownNetworkProvider()
    ) {
        self.knownNetworkProvider = knownNetworkProvider
    }

    func scan(completion: @escaping @Sendable (WiFiScanWorkerResult) -> Void) {
        queue.async { [self] in
            completion(scanSynchronously())
        }
    }

    func setPower(
        _ isOn: Bool,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        queue.async {
            guard let interface = CWWiFiClient.shared().interface() else {
                completion(false)
                return
            }
            do {
                try interface.setPower(isOn)
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    func associate(
        to network: WiFiNetwork,
        password: String?,
        completion: @escaping @Sendable (WiFiAssociationWorkerResult) -> Void
    ) {
        queue.async { [self] in
            completion(associateSynchronously(to: network, password: password))
        }
    }

    private func scanSynchronously() -> WiFiScanWorkerResult {
        guard let interface = CWWiFiClient.shared().interface() else { return .noInterface }
        guard interface.powerOn() else { return .poweredOff }

        do {
            let rawNetworks = try interface.scanForNetworks(withSSID: nil)
            let associatedBSSID = interface.bssid()
            let candidates = rawNetworks.compactMap(projectCandidate)
            let knownSSIDs = interface.interfaceName.map {
                knownNetworkProvider.preferredNetworkSSIDs(interface: $0)
            } ?? []
            let actualNetwork = rawNetworks.first {
                bssid($0.bssid, matches: associatedBSSID)
            }
            return .success(
                WiFiScanPayload(
                    networks: WiFiNetwork.merge(
                        candidates,
                        connectedBSSID: associatedBSSID,
                        knownSSIDs: knownSSIDs
                    ),
                    details: makeDetails(interface: interface, actualNetwork: actualNetwork)
                )
            )
        } catch {
            return .failed
        }
    }

    private func associateSynchronously(
        to selected: WiFiNetwork,
        password: String?
    ) -> WiFiAssociationWorkerResult {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else {
            return .networkUnavailable
        }
        guard let targetBSSID = selected.preferredCandidate?.bssid else {
            return .networkUnavailable
        }

        do {
            let networks = try interface.scanForNetworks(withSSID: nil)
            guard let target = networks.first(where: {
                $0.ssid == selected.ssid
                    && securityKind(for: $0) == selected.security
                    && bssid($0.bssid, matches: targetBSSID)
            }) else {
                return .networkUnavailable
            }

            // Do not disassociate first: CoreWLAN is asked to associate directly
            // with the selected AP and macOS retains the prior association until
            // it has progressed the new request.
            try interface.associate(to: target, password: password)

            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                if isAssociated(interface: interface, with: selected, targetBSSID: targetBSSID) {
                    let actualNetwork = (try? interface.scanForNetworks(withSSID: selected.ssid.data(using: .utf8)))?
                        .first { bssid($0.bssid, matches: interface.bssid()) }
                    return .success(makeDetails(interface: interface, actualNetwork: actualNetwork ?? target))
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
            return .timedOut
        } catch {
            // CoreWLAN does not provide a stable public error taxonomy for all
            // authentication failures, so do not guess that this was a bad
            // password. The UI presents an accurate generic failure instead.
            return .failed
        }
    }

    private func isAssociated(
        interface: CWInterface,
        with selected: WiFiNetwork,
        targetBSSID: String
    ) -> Bool {
        if bssid(interface.bssid(), matches: targetBSSID) { return true }
        guard interface.ssid() == selected.ssid else { return false }
        return compatibleSecurity(
            WiFiSecurityKind(coreWLANRawValue: interface.security().rawValue),
            selected.security
        )
    }

    private func compatibleSecurity(_ lhs: WiFiSecurityKind, _ rhs: WiFiSecurityKind) -> Bool {
        guard lhs != .unknown, rhs != .unknown else { return false }
        if lhs == rhs { return true }
        let personalModes: Set<WiFiSecurityKind> = [
            .wpaPersonal, .wpaPersonalMixed, .wpa2Personal, .personal,
            .wpa3Personal, .wpa3Transition
        ]
        return personalModes.contains(lhs) && personalModes.contains(rhs)
    }

    private func securityKind(for network: CWNetwork) -> WiFiSecurityKind {
        let preferredKinds: [(CWSecurity, WiFiSecurityKind)] = [
            (.wpa3Transition, .wpa3Transition),
            (.wpa3Enterprise, .wpa3Enterprise),
            (.wpa3Personal, .wpa3Personal),
            (.oweTransition, .oweTransition),
            (.OWE, .owe),
            (.wpa2Enterprise, .wpa2Enterprise),
            (.wpaEnterpriseMixed, .wpaEnterpriseMixed),
            (.wpaEnterprise, .wpaEnterprise),
            (.enterprise, .enterprise),
            (.wpa2Personal, .wpa2Personal),
            (.wpaPersonalMixed, .wpaPersonalMixed),
            (.wpaPersonal, .wpaPersonal),
            (.personal, .personal),
            (.dynamicWEP, .dynamicWEP),
            (.WEP, .wep),
            (.none, .open)
        ]
        return preferredKinds.first { network.supportsSecurity($0.0) }?.1 ?? .unknown
    }

    private func projectCandidate(_ network: CWNetwork) -> WiFiNetworkCandidate? {
        guard let ssid = network.ssid else { return nil }
        return WiFiNetworkCandidate(
            ssid: ssid,
            bssid: network.bssid,
            rssi: normalizedMeasurement(network.rssiValue),
            channel: network.wlanChannel?.channelNumber,
            security: securityKind(for: network)
        )
    }

    private func makeDetails(
        interface: CWInterface,
        actualNetwork: CWNetwork?
    ) -> WiFiConnectionDetails {
        let interfaceName = interface.interfaceName
        let configuration = interfaceName.map(networkConfiguration(interface:)) ?? .unavailable
        let channel = interface.wlanChannel()
        let transmitRate = interface.transmitRate()

        return WiFiConnectionDetails(
            ssid: interface.ssid(),
            bssid: interface.bssid(),
            band: displayBand(channel?.channelBand.rawValue),
            channel: channel?.channelNumber,
            channelWidth: displayChannelWidth(channel?.channelWidth.rawValue),
            rssi: normalizedMeasurement(interface.rssiValue()),
            noise: actualNetwork.flatMap { normalizedMeasurement($0.noiseMeasurement) },
            phyMode: displayPHY(interface.activePHYMode().rawValue),
            transmitRateMbps: transmitRate.isFinite && transmitRate > 0 ? transmitRate : nil,
            security: WiFiSecurityKind(coreWLANRawValue: interface.security().rawValue),
            countryCode: actualNetwork?.countryCode,
            interfaceName: interfaceName,
            ipv4Addresses: configuration.ipv4Addresses,
            ipv6Addresses: configuration.ipv6Addresses,
            router: configuration.router,
            dnsServers: configuration.dnsServers
        )
    }

    private func networkConfiguration(interface: String) -> WiFiServiceNetworkConfiguration {
        guard let store = SCDynamicStoreCreate(nil, "StatusTrio" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/.*" as CFString) as? [String] else {
            return .unavailable
        }
        var snapshot: [String: [String: Any]] = [:]
        for key in keys where key == "State:/Network/Global/IPv4" || key.hasPrefix("State:/Network/Service/") {
            if let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] {
                snapshot[key] = value
            }
        }
        return WiFiServiceNetworkConfiguration.resolve(interface: interface, snapshot: snapshot)
    }

    private func normalizedMeasurement(_ value: Int) -> Int? {
        value < 0 ? value : nil
    }

    private func bssid(_ lhs: String?, matches rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private func displayBand(_ rawValue: Int?) -> String? {
        guard let rawValue else { return nil }
        return switch rawValue {
        case 1: "2.4 GHz"
        case 2: "5 GHz"
        case 3: "6 GHz"
        default: nil
        }
    }

    private func displayChannelWidth(_ rawValue: Int?) -> String? {
        guard let rawValue else { return nil }
        return switch rawValue {
        case 1: "20 MHz"
        case 2: "40 MHz"
        case 3: "80 MHz"
        case 4: "160 MHz"
        default: nil
        }
    }

    private func displayPHY(_ rawValue: Int) -> String? {
        return switch rawValue {
        case 1: "802.11a"
        case 2: "802.11b"
        case 3: "802.11g"
        case 4: "802.11n"
        case 5: "802.11ac"
        case 6: "802.11ax"
        default: nil
        }
    }
}

private final class WiFiCredentialWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "StatusTrio.WiFiCredentialWorker")
    private let store: any WiFiCredentialStoring

    init(store: any WiFiCredentialStoring) {
        self.store = store
    }

    func resolve(
        _ identity: WiFiNetworkIdentity,
        completion: @escaping @Sendable (WiFiCredentialResult) -> Void
    ) {
        queue.async { [self] in
            completion(store.resolveCredential(for: identity))
        }
    }

    func save(
        _ password: String,
        for identity: WiFiNetworkIdentity,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        queue.async { [self] in
            completion(store.save(password, for: identity))
        }
    }
}


@MainActor
final class WiFiNetworkController: ObservableObject {
    @Published private(set) var networks: [WiFiNetwork] = []
    @Published private(set) var details = WiFiConnectionDetails.unavailable
    @Published private(set) var state: WiFiListState = .idle
    @Published private(set) var passwordPromptNetwork: WiFiNetwork?
    @Published private(set) var credentialIssue: WiFiCredentialIssue?

    private let worker: any WiFiNetworkScanning
    private let credentialWorker: WiFiCredentialWorker
    private let now: () -> Date
    /// A full scan sweeps every channel, so the automatic path may not run one
    /// more often than this. Explicit user actions bypass it.
    private let minimumScanInterval: TimeInterval
    private let periodicRefreshInterval: Duration
    private let periodicRefreshSleep: @Sendable (Duration) async throws -> Void
    private var scanGate = AsyncRequestGate()
    private var connectionGate = AsyncRequestGate()
    private var pendingNetwork: WiFiNetwork?
    private(set) var isActive = false
    /// When the last scan started, which is what the interval is measured from.
    private var lastScanStartedAt: Date?
    private var periodicRefreshTask: Task<Void, Never>?
    private var lastNameAccess: WiFiNameAccess = .notDetermined

    init(
        credentialStore: any WiFiCredentialStoring = KeychainWiFiPasswordStore(),
        scanWorker: any WiFiNetworkScanning = CoreWLANNetworkWorker(),
        now: @escaping () -> Date = Date.init,
        minimumScanInterval: TimeInterval = 30,
        periodicRefreshInterval: Duration = .seconds(30),
        periodicRefreshSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        credentialWorker = WiFiCredentialWorker(store: credentialStore)
        self.worker = scanWorker
        self.now = now
        self.minimumScanInterval = minimumScanInterval
        self.periodicRefreshInterval = periodicRefreshInterval
        self.periodicRefreshSleep = periodicRefreshSleep
    }
    deinit {
        periodicRefreshTask?.cancel()
    }

    func activate(nameAccess: WiFiNameAccess) {
        lastNameAccess = nameAccess
        guard !isActive else { return }
        isActive = true
        schedulePeriodicRefresh()
        refresh()
    }
    func deactivate() {
        guard isActive else { return }
        isActive = false
        _ = scanGate.advance()
        _ = connectionGate.advance()
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        pendingNetwork = nil
        passwordPromptNetwork = nil
        credentialIssue = nil
        // A scan that is in flight now has a completion that the `isActive`
        // guard above will drop, so leaving the scan on `.scanning` would block
        // every later `refresh`/`refreshNow` through `startScan`'s
        // `!state.isScanning` guard. Clearing the floor timestamp as well makes
        // the next `activate` start a clean cadence instead of inheriting this
        // session's scan.
        if state.isScanning || state.isConnectionFlow {
            state = .idle
        }
        lastScanStartedAt = nil
    }

    /// The automatic path: the periodic loop and every Wi-Fi status yield come
    /// through here. Inside the interval the cached list is kept, because the
    /// list only changes when the radio or the association changes, and those
    /// paths call `refreshNow(nameAccess:)`.
    func refresh(nameAccess: WiFiNameAccess? = nil) {
        if let nameAccess { lastNameAccess = nameAccess }
        guard hasScanElapsed else { return }
        startScan()
    }

    /// The explicit path: the refresh button, the radio toggle and a completed
    /// association. A user asked for this, so it scans even inside the interval.
    func refreshNow(nameAccess: WiFiNameAccess? = nil) {
        if let nameAccess { lastNameAccess = nameAccess }
        startScan()
    }

    private var hasScanElapsed: Bool {
        guard let lastScanStartedAt else { return true }
        return now().timeIntervalSince(lastScanStartedAt) >= minimumScanInterval
    }

    private func startScan() {
        guard isActive, state.allowsRefresh else { return }

        let request = scanGate.advance()
        lastScanStartedAt = now()
        state = .scanning
        worker.scan { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.scanGate.accepts(request), !self.state.isConnectionFlow else { return }
                self.receiveScanResult(result)
            }
        }
    }
    func setPower(_ enabled: Bool) {
        guard isActive else { return }

        _ = scanGate.advance()
        _ = connectionGate.advance()
        pendingNetwork = nil
        passwordPromptNetwork = nil
        credentialIssue = nil
        worker.setPower(enabled) { [weak self] changed in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                if changed {
                    self.state = .ready
                    self.refreshNow()
                } else {
                    self.state = .failed
                }
            }
        }
    }

    func beginConnection(to network: WiFiNetwork) {
        guard isActive, !state.isConnectionFlow else { return }

        pendingNetwork = network
        passwordPromptNetwork = nil
        credentialIssue = nil

        if network.security.isEnterprise {
            state = .enterpriseNetwork
            return
        }

        guard network.security.requiresPassword else {
            startAssociation(to: network, password: nil, suppliedPassword: nil, rememberPassword: false)
            return
        }

        let request = connectionGate.advance()
        state = .resolvingCredentials
        credentialWorker.resolve(network.identity) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.connectionGate.accepts(request), self.pendingNetwork?.identity == network.identity else { return }
                self.receiveCredentialResult(result, for: network)
            }
        }
    }

    func connect(to network: WiFiNetwork, password: String?, rememberPassword: Bool) {
        guard isActive else { return }

        if network.security.requiresPassword {
            guard let password, !password.isEmpty else {
                pendingNetwork = network
                passwordPromptNetwork = network
                state = .needsPassword
                return
            }
        }

        pendingNetwork = network
        passwordPromptNetwork = nil
        credentialIssue = nil
        startAssociation(
            to: network,
            password: password,
            suppliedPassword: password,
            rememberPassword: rememberPassword
        )
    }

    func cancelPasswordEntry() {
        guard state.isConnectionFlow || passwordPromptNetwork != nil else { return }
        _ = connectionGate.advance()
        passwordPromptNetwork = nil
        pendingNetwork = nil
        credentialIssue = nil
        state = .ready
    }

    func enterPasswordManually() {
        guard let pendingNetwork else { return }
        credentialIssue = nil
        passwordPromptNetwork = pendingNetwork
        state = .needsPassword
    }

    private func receiveCredentialResult(_ result: WiFiCredentialResult, for network: WiFiNetwork) {
        switch result {
        case let .credential(password, _):
            startAssociation(to: network, password: password, suppliedPassword: nil, rememberPassword: false)
        case .noCredential:
            passwordPromptNetwork = network
            state = .needsPassword
        case let .issue(issue):
            credentialIssue = issue
            switch issue {
            case .cancelled:
                state = .credentialAccessCancelled
            case .accessDenied:
                state = .credentialAccessDenied
            case .keychainLocked:
                state = .credentialStoreLocked
            case .readFailed, .saveFailed:
                state = .credentialReadFailed
            }
        }
    }

    private func startAssociation(
        to network: WiFiNetwork,
        password: String?,
        suppliedPassword: String?,
        rememberPassword: Bool
    ) {
        let request = connectionGate.advance()
        passwordPromptNetwork = nil
        state = .connecting(network.identity)

        worker.associate(to: network, password: password) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.connectionGate.accepts(request) else { return }
                self.receiveAssociationResult(
                    result,
                    for: network,
                    suppliedPassword: suppliedPassword,
                    rememberPassword: rememberPassword,
                    request: request
                )
            }
        }
    }

    private func receiveAssociationResult(
        _ result: WiFiAssociationWorkerResult,
        for network: WiFiNetwork,
        suppliedPassword: String?,
        rememberPassword: Bool,
        request: UInt64
    ) {
        switch result {
        case let .success(connectionDetails):
            self.details = connectionDetails
            state = .ready
            pendingNetwork = nil
            credentialIssue = nil
            if rememberPassword, let suppliedPassword {
                credentialWorker.save(suppliedPassword, for: network.identity) { [weak self] saved in
                    Task { @MainActor [weak self] in
                        guard let self, self.connectionGate.accepts(request) else { return }
                        if !saved {
                            self.credentialIssue = .saveFailed
                        }
                    }
                }
            }
            refreshNow()
        case .networkUnavailable:
            pendingNetwork = network
            state = .networkUnavailable
        case .timedOut:
            pendingNetwork = network
            state = .connectionTimedOut
        case .failed:
            pendingNetwork = network
            state = .connectionFailed
        }
    }

    private func receiveScanResult(_ result: WiFiScanWorkerResult) {
        switch result {
        case let .success(payload):
            details = payload.details
            networks = payload.networks
            if payload.networks.isEmpty,
               lastNameAccess == .denied || lastNameAccess == .restricted {
                state = .permissionDenied
            } else {
                state = .ready
            }
        case .poweredOff:
            details = .unavailable
            networks = []
            state = .poweredOff
        case .noInterface:
            details = .unavailable
            networks = []
            state = .noInterface
        case .failed:
            state = lastNameAccess == .denied || lastNameAccess == .restricted
                ? .permissionDenied
                : .failed
        }
    }

    private func schedulePeriodicRefresh() {
        periodicRefreshTask?.cancel()
        let interval = periodicRefreshInterval
        let sleep = periodicRefreshSleep
        periodicRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard let self, self.isActive else { return }
                self.refresh()
            }
        }
    }

}
