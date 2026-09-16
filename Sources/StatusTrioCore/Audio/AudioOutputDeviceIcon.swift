import AppKit
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
///
/// The cases mirror the device types declared in
/// `/System/Library/CoreServices/CoreTypes.bundle`, the table the system UI
/// resolves its own device icons from. `public.speaker` declares
/// `hifispeaker.fill`, `public.display` declares `display`, and
/// `com.apple.airpods-pro` declares `airpods.pro.gen1`.
enum AudioOutputDeviceKind: CaseIterable, Equatable, Sendable {
    case airPodsPro
    case airPodsGen3
    case airPods
    case airPodsMax
    case beatsPowerbeatsPro
    case beatsPowerbeats
    case beatsStudioBuds
    case beatsFitPro
    case beatsEarphones
    case beatsHeadphones
    case homePodMini
    case homePod
    case headphones
    case speaker
    case display
    case appleTV
}

/// Picks the SF Symbol that matches an output device, using the symbol names
/// the system volume menu resolves for the same device class.
enum AudioOutputDeviceIcon {
    static func symbolName(for device: AudioOutputDevice) -> String {
        symbolName(for: kind(for: device))
    }

    static func symbolName(for kind: AudioOutputDeviceKind) -> String {
        let candidates = symbolCandidates(for: kind)
        return candidates.first {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        } ?? candidates.last ?? "hifispeaker.fill"
    }

    /// The SF Symbol names for a device class, most faithful to the system
    /// first. The last entry exists on the oldest supported macOS release, so a
    /// symbol the running system does not ship never renders as a blank icon.
    static func symbolCandidates(for kind: AudioOutputDeviceKind) -> [String] {
        switch kind {
        case .airPodsPro:
            ["airpods.pro.gen1", "airpodspro", "headphones"]
        case .airPodsGen3:
            ["airpods.gen3", "airpods", "headphones"]
        case .airPods:
            ["airpods", "headphones"]
        case .airPodsMax:
            ["airpodsmax", "headphones"]
        case .beatsPowerbeatsPro:
            ["beats.powerbeatspro", "beats.powerbeats.pro", "beats.headphones", "headphones"]
        case .beatsPowerbeats:
            ["beats.powerbeats", "beats.headphones", "headphones"]
        case .beatsStudioBuds:
            ["beats.studiobuds", "beats.headphones", "headphones"]
        case .beatsFitPro:
            ["beats.fit.pro", "beats.fitpro", "beats.headphones", "headphones"]
        case .beatsEarphones:
            ["beats.earphones", "beats.headphones", "headphones"]
        case .beatsHeadphones:
            ["beats.headphones", "headphones"]
        case .homePodMini:
            ["homepodmini", "homepod", "hifispeaker.fill"]
        case .homePod:
            ["homepod", "hifispeaker.fill"]
        case .headphones:
            ["headphones"]
        case .speaker:
            ["hifispeaker.fill", "hifispeaker"]
        case .display:
            ["display"]
        case .appleTV:
            ["appletv", "display"]
        }
    }

    static func kind(for device: AudioOutputDevice) -> AudioOutputDeviceKind {
        let name = (device.name ?? "").lowercased()

        // Model families that no public CoreAudio property identifies.
        if let family = appleOrBeatsFamily(in: name) {
            return family
        }

        if isHeadphoneName(name) {
            return .headphones
        }

        // A built-in device reports whether its jack or its speakers are live.
        if device.transport == .builtIn {
            return device.dataSource == .headphones ? .headphones : .speaker
        }

        if isDisplayName(name) || isTelevisionName(name) {
            return .display
        }
        if isSpeakerName(name) {
            return .speaker
        }

        switch device.transport {
        case .hdmi, .displayPort:
            return .display
        case .bluetooth, .bluetoothLowEnergy:
            // Bluetooth audio is overwhelmingly headphones or earbuds; speakers
            // are caught by their name above.
            return .headphones
        default:
            return .speaker
        }
    }

    private static func appleOrBeatsFamily(in name: String) -> AudioOutputDeviceKind? {
        if name.contains("airpods max") {
            return .airPodsMax
        }
        if name.contains("airpods pro") {
            return .airPodsPro
        }
        if name.contains("airpods") {
            return isThirdGenerationAirPods(name) ? .airPodsGen3 : .airPods
        }
        if name.contains("homepod mini") || name.contains("homepodmini") {
            return .homePodMini
        }
        if name.contains("homepod") {
            return .homePod
        }
        if name.contains("apple tv") || name.contains("appletv") {
            return .appleTV
        }
        if name.contains("beats") {
            if name.contains("powerbeats pro") {
                return .beatsPowerbeatsPro
            }
            if name.contains("powerbeats") {
                return .beatsPowerbeats
            }
            if name.contains("studio buds") || name.contains("studiobuds") {
                return .beatsStudioBuds
            }
            if name.contains("fit pro") {
                return .beatsFitPro
            }
            if name.contains("beatsx") || name.contains("beats flex") || name.contains("beats fit") {
                return .beatsEarphones
            }
            return .beatsHeadphones
        }
        return nil
    }

    private static func isThirdGenerationAirPods(_ name: String) -> Bool {
        for keyword in ["3rd generation", "third generation", "gen3", "gen 3", "第三代", "3代"] where name.contains(keyword) {
            return true
        }
        return false
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
