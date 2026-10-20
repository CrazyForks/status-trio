import Foundation

enum BluetoothRadioPower: Equatable, Sendable {
    case on
    case off
    case unavailable
    case unknown

    var isOn: Bool { self == .on }
}

enum BluetoothRadioPowerFailure: Equatable, Sendable {
    case requestRejected
    case stateDidNotChange
}

@MainActor
protocol BluetoothRadioPowerBacking: AnyObject {
    var isAvailable: Bool { get }
    func readPower() -> BluetoothRadioPower
    func setPower(_ enabled: Bool) async -> Bool
}

enum BluetoothRadioPowerPolicy {
    static func requiresConfirmation(beforeTurningOff devices: [BluetoothDevice]) -> Bool {
        devices.contains {
            $0.isConnected
                && ($0.kind.isPeripheral || $0.kind == .unknown)
        }
    }
}

struct BluetoothRadioPowerPresentation: Equatable, Sendable {
    let showsToggle: Bool
    let isOn: Bool
    let toggleEnabled: Bool
    let subtitle: String?

    @MainActor
    static func make(
        power: BluetoothRadioPower,
        isChanging: Bool,
        failure: BluetoothRadioPowerFailure?,
        localization: Localization
    ) -> Self {
        switch power {
        case .unavailable:
            return Self(
                showsToggle: false,
                isOn: false,
                toggleEnabled: false,
                subtitle: localization.string(.bluetoothUnavailable)
            )
        case .unknown:
            return Self(
                showsToggle: true,
                isOn: false,
                toggleEnabled: !isChanging,
                subtitle: localization.string(.bluetoothPowerUnknown)
            )
        case .off:
            return Self(
                showsToggle: true,
                isOn: false,
                toggleEnabled: !isChanging,
                subtitle: failure != nil
                    ? localization.string(.bluetoothPowerChangeFailed)
                    : localization.string(.bluetoothOff)
            )
        case .on:
            let failed = failure != nil
            return Self(
                showsToggle: true,
                isOn: true,
                toggleEnabled: !isChanging,
                subtitle: failed
                    ? localization.string(.bluetoothPowerChangeFailed)
                    : nil
            )
        }
    }
}

@MainActor
final class BluetoothRadioPowerController: ObservableObject {
    static let defaultReadBackAttempts = 12
    static let defaultReadBackInterval: Duration = .milliseconds(250)

    @Published private(set) var power: BluetoothRadioPower
    @Published private(set) var isChanging = false
    @Published private(set) var failure: BluetoothRadioPowerFailure?

    private let backend: any BluetoothRadioPowerBacking
    private let sleep: @Sendable (Duration) async throws -> Void
    private let readBackAttempts: Int
    private let readBackInterval: Duration

    init(
        backend: any BluetoothRadioPowerBacking = IOBluetoothRadioPowerBackend(),
        readBackAttempts: Int = defaultReadBackAttempts,
        readBackInterval: Duration = defaultReadBackInterval,
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.backend = backend
        self.readBackAttempts = max(1, readBackAttempts)
        self.readBackInterval = readBackInterval
        self.sleep = sleep
        power = backend.isAvailable ? .unknown : .unavailable
        refresh()
    }

    var canSetPower: Bool {
        backend.isAvailable && !isChanging
    }

    func refresh() {
        power = backend.readPower()
    }

    @discardableResult
    func setPower(_ enabled: Bool) async -> Bool {
        guard backend.isAvailable, !isChanging else { return false }
        isChanging = true
        failure = nil
        defer { isChanging = false }

        guard await backend.setPower(enabled) else {
            failure = .requestRejected
            refresh()
            return false
        }

        let expected: BluetoothRadioPower = enabled ? .on : .off
        for attempt in 0..<readBackAttempts {
            refresh()
            if power == expected {
                return true
            }
            guard attempt + 1 < readBackAttempts else { break }
            do {
                try await sleep(readBackInterval)
            } catch {
                break
            }
        }

        failure = .stateDidNotChange
        return false
    }
}
