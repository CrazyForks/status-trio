import CoreAudio

/// The device family reported by `kAudioDevicePropertyTransportType`.
///
/// The transport type is the public CoreAudio signal that describes what kind
/// of hardware an output device is. macOS itself classifies Apple Bluetooth
/// accessories through a private Bluetooth product-ID table, so the AirPods and
/// HomePod model names in ``AudioOutputDeviceKind`` stay name based.
enum AudioOutputTransport: Equatable, Sendable {
    case builtIn
    case bluetooth
    case bluetoothLowEnergy
    case usb
    case hdmi
    case displayPort
    case thunderbolt
    case airPlay
    case aggregate
    case virtual
    case other

    init(coreAudioValue: UInt32) {
        self = Self.transportsByCoreAudioValue
            .first { $0.value == coreAudioValue }?
            .transport ?? .other
    }

    private static let transportsByCoreAudioValue: [(value: UInt32, transport: Self)] = [
        (kAudioDeviceTransportTypeBuiltIn, .builtIn),
        (kAudioDeviceTransportTypeBluetooth, .bluetooth),
        (kAudioDeviceTransportTypeBluetoothLE, .bluetoothLowEnergy),
        (kAudioDeviceTransportTypeUSB, .usb),
        (kAudioDeviceTransportTypeHDMI, .hdmi),
        (kAudioDeviceTransportTypeDisplayPort, .displayPort),
        (kAudioDeviceTransportTypeThunderbolt, .thunderbolt),
        (kAudioDeviceTransportTypeAirPlay, .airPlay),
        (kAudioDeviceTransportTypeAggregate, .aggregate),
        (kAudioDeviceTransportTypeAutoAggregate, .aggregate),
        (kAudioDeviceTransportTypeVirtual, .virtual)
    ]
}

/// The active data source of an output device, as reported by
/// `kAudioDevicePropertyDataSource`.
///
/// A Mac with a headphone jack keeps a single built-in output device and
/// switches this value between the internal speakers and the jack, which is how
/// the system volume menu knows to show headphones while they are plugged in.
enum AudioOutputDataSource: Equatable, Sendable {
    case internalSpeaker
    case headphones
    case externalSpeaker
    case other

    init(coreAudioValue: UInt32) {
        self = Self.dataSourcesByCoreAudioValue
            .first { $0.value == coreAudioValue }?
            .dataSource ?? .other
    }

    private static func fourCharacterCode(_ code: String) -> UInt32 {
        code.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static let dataSourcesByCoreAudioValue: [(value: UInt32, dataSource: Self)] = [
        (fourCharacterCode("ispk"), .internalSpeaker),
        (fourCharacterCode("hdpn"), .headphones),
        (fourCharacterCode("espk"), .externalSpeaker),
        (fourCharacterCode("spkr"), .externalSpeaker)
    ]
}

/// The output device classes the system volume menu distinguishes.
enum AudioOutputDeviceKind: Equatable, Sendable {
    case airPodsPro
    case airPodsMax
    case airPods
    case headphones
    case homePod
    case builtInSpeaker
    case externalSpeaker
    case display
    case television
    case airPlay
}

/// Picks the SF Symbol that matches an output device, the same way the system
/// volume menu picks its own icons.
enum AudioOutputDeviceIcon {
    static func symbolName(for device: AudioOutputDevice) -> String {
        symbolName(for: kind(for: device), isCurrent: device.isCurrent)
    }

    static func kind(for device: AudioOutputDevice) -> AudioOutputDeviceKind {
        let name = (device.name ?? "").lowercased()

        // Model families that no public CoreAudio property identifies.
        if name.contains("airpods max") {
            return .airPodsMax
        }
        if name.contains("airpods pro") {
            return .airPodsPro
        }
        if name.contains("airpods") {
            return .airPods
        }
        if name.contains("homepod") {
            return .homePod
        }

        if isHeadphoneName(name) {
            return .headphones
        }

        // A built-in device reports whether its jack or its speakers are live.
        if device.transport == .builtIn {
            return device.dataSource == .headphones ? .headphones : .builtInSpeaker
        }

        if isTelevisionName(name) {
            return .television
        }
        if isDisplayName(name) {
            return .display
        }
        if isSpeakerName(name) {
            return .externalSpeaker
        }

        switch device.transport {
        case .hdmi, .displayPort:
            return .display
        case .airPlay:
            return .airPlay
        case .bluetooth, .bluetoothLowEnergy:
            // Bluetooth audio is overwhelmingly headphones or earbuds; speakers
            // are caught by their name above.
            return .headphones
        default:
            return .externalSpeaker
        }
    }

    static func symbolName(for kind: AudioOutputDeviceKind, isCurrent: Bool) -> String {
        switch kind {
        case .airPodsPro: "airpodspro"
        case .airPodsMax: "airpodsmax"
        case .airPods: "airpods"
        case .headphones: "headphones"
        case .homePod: isCurrent ? "homepod.fill" : "homepod"
        case .builtInSpeaker, .externalSpeaker: isCurrent ? "hifispeaker.fill" : "hifispeaker"
        case .display: "display"
        case .television: "tv"
        case .airPlay: "airplayaudio"
        }
    }

    private static func isHeadphoneName(_ name: String) -> Bool {
        for keyword in ["headphone", "headset", "earbud", "earphone", "earpods"] where name.contains(keyword) {
            return true
        }
        for keyword in ["耳机", "头戴", "耳塞", "听筒"] where name.contains(keyword) {
            return true
        }
        return false
    }

    private static func isDisplayName(_ name: String) -> Bool {
        for keyword in ["display", "monitor", "hdmi"] where name.contains(keyword) {
            return true
        }
        return ["显示器", "显示屏"].contains { name.contains($0) }
    }

    private static func isTelevisionName(_ name: String) -> Bool {
        if name.contains("television") || name.contains("tv") {
            return true
        }
        return ["电视", "电视屏"].contains { name.contains($0) }
    }

    private static func isSpeakerName(_ name: String) -> Bool {
        for keyword in ["speaker", "soundbar", "sound bar", "boombox", "home theater"] where name.contains(keyword) {
            return true
        }
        return ["扬声器", "音响", "音箱"].contains { name.contains($0) }
    }
}
