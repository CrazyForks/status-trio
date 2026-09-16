import AppKit
import CoreAudio
import Darwin
import Foundation

/// The device family reported by `kAudioDevicePropertyTransportType`.
///
/// The transport type is the public CoreAudio signal that describes what kind
/// of hardware an output device is. macOS itself classifies Apple Bluetooth
/// accessories through a private Bluetooth product-ID table, so the AirPods,
/// Beats and HomePod model names stay name based.
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

/// The Mac family behind a built-in output device.
///
/// The system draws the machine itself, not a speaker, for a built-in output,
/// and `CoreTypes.bundle` declares one symbol per family: `com.apple.mac.laptop`
/// is `macbook`, `com.apple.macmini` is `macmini.gen2`, `com.apple.macstudio`
/// is `macstudio`, `com.apple.macpro` is `macpro.gen3`, and `com.apple.imac`
/// is `desktopcomputer`.
///
/// The built-in device name carries the family, for example
/// `MacBook Pro扬声器`. Apple Silicon model identifiers such as `Mac15,9` no
/// longer encode it, so `hw.model` is only a fallback.
enum HostMacKind: Equatable, Sendable {
    case laptop
    case mini
    case studio
    case macPro
    case desktop
    case unknown

    static let current = HostMacKind(modelIdentifier: currentModelIdentifier())

    init(modelIdentifier: String) {
        let identifier = modelIdentifier.lowercased()
        switch true {
        case identifier.hasPrefix("macbook"):
            self = .laptop
        case identifier.hasPrefix("macmini"):
            self = .mini
        case identifier.hasPrefix("macstudio"):
            self = .studio
        case identifier.hasPrefix("macpro"):
            self = .macPro
        case identifier.hasPrefix("imac"):
            self = .desktop
        default:
            self = .unknown
        }
    }

    /// Reads the family from the device name, falling back to the host machine.
    init(deviceName: String?, host: HostMacKind = .current) {
        let name = (deviceName ?? "").lowercased()
        switch true {
        case name.contains("macbook"):
            self = .laptop
        case name.contains("mac mini"), name.contains("macmini"):
            self = .mini
        case name.contains("mac studio"), name.contains("macstudio"):
            self = .studio
        case name.contains("imac"):
            self = .desktop
        case name.contains("mac pro"), name.contains("macpro"):
            self = .macPro
        default:
            self = host
        }
    }

    private static func currentModelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return ""
        }
        return String(cString: buffer)
    }
}

/// The output device classes the system volume menu distinguishes.
///
/// The cases mirror the device types declared in
/// `/System/Library/CoreServices/CoreTypes.bundle`.
enum AudioOutputDeviceKind: CaseIterable, Equatable, Sendable {
    case airPodsPro
    case airPodsProGen1
    case airPodsProGen3
    case airPods
    case airPodsGen3
    case airPodsGen4
    case airPodsMax
    case beatsPill
    case beatsSoloBuds
    case beatsStudioBudsPlus
    case beatsStudioBuds
    case beatsFitPro
    case beatsPowerbeatsPro2
    case beatsPowerbeatsPro
    case beatsPowerbeats3
    case beatsPowerbeats
    case beatsEarphones
    case beatsHeadphones
    case homePod
    case homePodMini
    case headphones
    case speaker
    case builtInSpeaker
    case display
    case appleTV
    case airPlay
}

/// What to draw for an output device: the image the driver ships, or an
/// SF Symbol.
enum AudioOutputDeviceIconSource: Equatable, Sendable {
    case image(URL)
    case symbol(String)
}

/// Picks the SF Symbol that matches an output device, using the symbol names
/// the system volume menu resolves for the same device class.
enum AudioOutputDeviceIcon {
    static func symbolName(for device: AudioOutputDevice) -> String {
        symbolName(for: kind(for: device), host: HostMacKind(deviceName: device.name))
    }

    /// Prefers the icon the driver ships for the device, which is what the
    /// system shows for HAL plugins such as Background Music, and falls back to
    /// the SF Symbol for the device class.
    static func source(
        for device: AudioOutputDevice,
        host: HostMacKind = .current
    ) -> AudioOutputDeviceIconSource {
        if let iconURL = device.iconURL,
           FileManager.default.fileExists(atPath: iconURL.path) {
            return .image(iconURL)
        }
        let deviceKind = kind(for: device)
        return .symbol(
            symbolName(for: deviceKind, host: HostMacKind(deviceName: device.name, host: host))
        )
    }

    static func symbolName(for kind: AudioOutputDeviceKind, host: HostMacKind = .current) -> String {
        let candidates = symbolCandidates(for: kind, host: host)
        return candidates.first {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        } ?? candidates.last ?? "hifispeaker.fill"
    }

    /// The SF Symbol names for a device class, most faithful to the system
    /// first. The last entry exists on the oldest supported macOS release, so a
    /// symbol the running system does not ship never renders as a blank icon.
    static func symbolCandidates(
        for kind: AudioOutputDeviceKind,
        host: HostMacKind = .current
    ) -> [String] {
        switch kind {
        case .airPodsPro:
            ["airpods.pro", "airpodspro", "headphones"]
        case .airPodsProGen1:
            ["airpods.pro.gen1", "airpods.pro", "airpodspro", "headphones"]
        case .airPodsProGen3:
            ["airpods.pro.gen3", "airpods.pro", "airpodspro", "headphones"]
        case .airPods:
            ["airpods", "headphones"]
        case .airPodsGen3:
            ["airpods.gen3", "airpods", "headphones"]
        case .airPodsGen4:
            ["airpods.gen4", "airpods", "headphones"]
        case .airPodsMax:
            ["airpodsmax", "airpods.max", "headphones"]
        case .beatsPill:
            ["beats.pill", "beats.headphones", "headphones"]
        case .beatsSoloBuds:
            ["beats.solobuds", "beats.studiobuds", "beats.headphones", "headphones"]
        case .beatsStudioBudsPlus:
            ["beats.studiobuds.plus", "beats.studiobuds", "beats.headphones", "headphones"]
        case .beatsStudioBuds:
            ["beats.studiobuds", "beats.headphones", "headphones"]
        case .beatsFitPro:
            ["beats.fit.pro", "beats.fitpro", "beats.headphones", "headphones"]
        case .beatsPowerbeatsPro2:
            ["beats.powerbeats.pro.2", "beats.powerbeatspro", "beats.headphones", "headphones"]
        case .beatsPowerbeatsPro:
            ["beats.powerbeatspro", "beats.powerbeats.pro", "beats.headphones", "headphones"]
        case .beatsPowerbeats3:
            ["beats.powerbeats3", "beats.powerbeats", "beats.headphones", "headphones"]
        case .beatsPowerbeats:
            ["beats.powerbeats", "beats.headphones", "headphones"]
        case .beatsEarphones:
            ["beats.earphones", "beats.headphones", "headphones"]
        case .beatsHeadphones:
            ["beats.headphones", "headphones"]
        case .homePod:
            ["homepod", "hifispeaker.fill"]
        case .homePodMini:
            ["homepodmini", "homepod.mini", "homepod", "hifispeaker.fill"]
        case .headphones:
            ["headphones"]
        case .speaker:
            ["hifispeaker.fill", "hifispeaker"]
        case .builtInSpeaker:
            builtInSpeakerCandidates(for: host)
        case .display:
            ["display"]
        case .appleTV:
            ["appletv", "display"]
        case .airPlay:
            ["airplayaudio", "hifispeaker.fill"]
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
            return device.dataSource == .headphones ? .headphones : .builtInSpeaker
        }

        if name.contains("airplay") {
            return .airPlay
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
        case .airPlay:
            return .airPlay
        case .bluetooth, .bluetoothLowEnergy:
            // Bluetooth audio is overwhelmingly headphones or earbuds; speakers
            // are caught by their name above.
            return .headphones
        default:
            return .speaker
        }
    }

    private static func builtInSpeakerCandidates(for host: HostMacKind) -> [String] {
        switch host {
        case .laptop:
            ["macbook"]
        case .mini:
            ["macmini.gen2", "macmini", "desktopcomputer"]
        case .studio:
            ["macstudio", "desktopcomputer"]
        case .macPro:
            ["macpro.gen3", "desktopcomputer"]
        case .desktop:
            ["desktopcomputer"]
        case .unknown:
            ["macbook", "desktopcomputer"]
        }
    }

    private static func appleOrBeatsFamily(in name: String) -> AudioOutputDeviceKind? {
        if name.contains("airpods max") {
            return .airPodsMax
        }
        if name.contains("airpods pro") {
            switch airPodsGeneration(in: name) {
            case 1:
                return .airPodsProGen1
            case 3:
                return .airPodsProGen3
            default:
                return .airPodsPro
            }
        }
        if name.contains("airpods") {
            switch airPodsGeneration(in: name) {
            case 4:
                return .airPodsGen4
            case 3:
                return .airPodsGen3
            default:
                return .airPods
            }
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
            return beatsFamily(in: name)
        }
        return nil
    }

    private static func beatsFamily(in name: String) -> AudioOutputDeviceKind {
        if name.contains("beats pill") || name.contains("beatspill") {
            return .beatsPill
        }
        if name.contains("solo buds") || name.contains("solobuds") {
            return .beatsSoloBuds
        }
        if name.contains("studiobudsplus") || name.contains("studio buds plus") || name.contains("studio buds +") {
            return .beatsStudioBudsPlus
        }
        if name.contains("studio buds") || name.contains("studiobuds") {
            return .beatsStudioBuds
        }
        if name.contains("fit pro") || name.contains("fitpro") {
            return .beatsFitPro
        }
        if name.contains("powerbeats pro 2") || name.contains("powerbeatspro2") {
            return .beatsPowerbeatsPro2
        }
        if name.contains("powerbeats pro") || name.contains("powerbeatspro") {
            return .beatsPowerbeatsPro
        }
        if name.contains("powerbeats3") || name.contains("powerbeats 3") {
            return .beatsPowerbeats3
        }
        if name.contains("powerbeats") {
            return .beatsPowerbeats
        }
        if name.contains("beatsx") || name.contains("beats x") || name.contains("urbeats") || name.contains("beats flex") {
            return .beatsEarphones
        }
        return .beatsHeadphones
    }

    private static func matchesGeneration(_ name: String, generation: Int) -> Bool {
        let suffixes = ["th", "st", "nd", "rd"]
        var keywords = [
            "gen\(generation)",
            "gen \(generation)",
            "generation \(generation)",
            "\(generation)代",
            "第\(generation)代"
        ]
        for suffix in suffixes {
            keywords.append("\(generation)\(suffix) generation")
        }
        keywords.append(contentsOf: chineseNumerals.compactMap { numeral, value in
            value == generation ? numeral : nil
        })

        for keyword in keywords where name.contains(keyword) {
            return true
        }
        return false
    }

    /// Reads the AirPods generation from explicit wording ("3rd generation",
    /// "第三代") or from the marketing number in a device name such as
    /// "AirPods Pro 3".
    private static func airPodsGeneration(in name: String) -> Int? {
        for generation in 1...6 where matchesGeneration(name, generation: generation) {
            return generation
        }

        for generation in 1...6 {
            let modelNumbers = [
                "airpods pro \(generation)",
                "airpods pro\(generation)",
                "airpods \(generation)",
                "airpods\(generation)"
            ]
            if modelNumbers.contains(where: { name.contains($0) }) {
                return generation
            }
        }
        return nil
    }

    private static let chineseNumerals: [(numeral: String, generation: Int)] = [
        ("第一代", 1),
        ("第二代", 2),
        ("第三代", 3),
        ("第四代", 4),
        ("一代", 1),
        ("二代", 2),
        ("三代", 3),
        ("四代", 4)
    ]

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
