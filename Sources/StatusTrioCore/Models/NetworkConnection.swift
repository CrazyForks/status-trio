enum NetworkConnection: Equatable, Sendable {
    case wifi
    case ethernet
    case other
    case offline
    case unknown

    static func resolve(connected: Bool, wired: Bool, wireless: Bool) -> NetworkConnection {
        guard connected else { return .offline }
        if wired { return .ethernet }
        if wireless { return .wifi }
        return .other
    }
}
