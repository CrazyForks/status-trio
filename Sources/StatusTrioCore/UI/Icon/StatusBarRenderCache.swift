struct StatusBarRenderKey: Equatable {
    let status: MenuBarStatus
    let iconSize: Double
    let options: BatteryIconOptions
    let connectionOptions: ConnectionIconOptions
    let appearanceName: String
}

struct StatusBarRenderCache {
    private(set) var lastKey: StatusBarRenderKey?

    mutating func shouldRender(_ key: StatusBarRenderKey) -> Bool {
        guard key != lastKey else { return false }
        lastKey = key
        return true
    }
}
