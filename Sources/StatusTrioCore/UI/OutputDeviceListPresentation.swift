enum OutputDeviceListPresentation {
    static func visibleDevices(
        from devices: [AudioOutputDevice],
        limit: Int?,
        isExpanded: Bool
    ) -> [AudioOutputDevice] {
        guard !isExpanded, let limit else { return devices }
        return Array(devices.prefix(max(0, limit)))
    }

    static func canToggleExpansion(
        for devices: [AudioOutputDevice],
        limit: Int?
    ) -> Bool {
        guard let limit else { return false }
        return devices.count > max(0, limit)
    }
}
