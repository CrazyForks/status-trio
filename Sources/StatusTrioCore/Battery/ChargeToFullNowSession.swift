import Foundation

struct ChargeToFullNowSession: Codable, Equatable, Sendable {
    let originalLimit: Int?
    let acceptedAt: Date
}

@MainActor
protocol ChargeToFullNowSessionStoring: AnyObject {
    func load() -> ChargeToFullNowSession?
    func save(_ session: ChargeToFullNowSession)
    func clear()
}

@MainActor
final class UserDefaultsChargeToFullNowSessionStore: ChargeToFullNowSessionStoring {
    static let defaultsKey = "chargeToFullNow.session.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> ChargeToFullNowSession? {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let session = try? JSONDecoder().decode(
                ChargeToFullNowSession.self,
                from: data
              ) else {
            return nil
        }
        return session
    }

    func save(_ session: ChargeToFullNowSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}

@MainActor
final class VolatileChargeToFullNowSessionStore: ChargeToFullNowSessionStoring {
    private var session: ChargeToFullNowSession?

    init(session: ChargeToFullNowSession? = nil) {
        self.session = session
    }

    func load() -> ChargeToFullNowSession? {
        session
    }

    func save(_ session: ChargeToFullNowSession) {
        self.session = session
    }

    func clear() {
        session = nil
    }
}

/// The last user charge limit the app observed. macOS removes the persisted
/// `powerd` policy while its own temporary override runs, so this value is the
/// only restore target left when the override starts outside the app.
@MainActor
protocol ChargeLimitMemoryStoring: AnyObject {
    func load() -> Int?
    func save(_ limit: Int)
}

@MainActor
final class UserDefaultsChargeLimitMemoryStore: ChargeLimitMemoryStoring {
    static let defaultsKey = "chargeToFullNow.lastKnownLimit.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> Int? {
        guard defaults.object(forKey: Self.defaultsKey) != nil else {
            return nil
        }
        let limit = defaults.integer(forKey: Self.defaultsKey)
        return (80..<100).contains(limit) ? limit : nil
    }

    func save(_ limit: Int) {
        defaults.set(limit, forKey: Self.defaultsKey)
    }
}

@MainActor
final class VolatileChargeLimitMemoryStore: ChargeLimitMemoryStoring {
    private var limit: Int?

    init(limit: Int? = nil) {
        self.limit = limit
    }

    func load() -> Int? {
        limit
    }

    func save(_ limit: Int) {
        self.limit = limit
    }
}
