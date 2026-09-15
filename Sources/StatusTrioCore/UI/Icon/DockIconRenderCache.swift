struct DockIconRenderKey: Equatable {
    let status: MenuBarStatus
    let options: BatteryIconOptions
    let connectionOptions: ConnectionIconOptions
    let backgroundStyle: DockIconBackgroundStyle
}

struct DockIconRenderCache {
    private(set) var lastKey: DockIconRenderKey?

    mutating func shouldRender(_ key: DockIconRenderKey) -> Bool {
        guard key != lastKey else { return false }
        lastKey = key
        return true
    }

    mutating func reset() {
        lastKey = nil
    }
}
