import AppKit
import CoreAudio
import Testing
@testable import StatusTrioCore

struct AudioOutputDeviceIconTests {
    @Test("Built-in speakers draw the machine, not a speaker")
    func builtInSpeakersDrawTheMachine() {
        #expect(candidates(name: "MacBook Pro扬声器", transport: .builtIn, dataSource: .internalSpeaker).first == "macbook")
        #expect(candidates(name: "Mac mini扬声器", transport: .builtIn, dataSource: .internalSpeaker).first == "macmini.gen2")
        #expect(candidates(name: "Mac Studio扬声器", transport: .builtIn, dataSource: .internalSpeaker).first == "macstudio")
        #expect(candidates(name: "Mac Pro扬声器", transport: .builtIn, dataSource: .internalSpeaker).first == "macpro.gen3")
        #expect(candidates(name: "iMac扬声器", transport: .builtIn, dataSource: .internalSpeaker).first == "desktopcomputer")
        // A localized name that does not name the machine falls back to the host.
        #expect(candidates(name: "内置扬声器", transport: .builtIn, dataSource: .other, host: .unknown).first == "macbook")
        #expect(candidates(name: "内置扬声器", transport: .builtIn, dataSource: .other, host: .mini).first == "macmini.gen2")
    }

    @Test("The headphone jack keeps the headphone symbol on built-in hardware")
    func headphoneJackKeepsHeadphoneSymbol() {
        #expect(candidates(name: "MacBook Pro扬声器", transport: .builtIn, dataSource: .headphones, host: .laptop).first == "headphones")
        #expect(candidates(name: "外置耳机", transport: .builtIn, host: .laptop).first == "headphones")
    }

    @Test("Host machine identifiers map to their families")
    func hostMachineIdentifiersMapToFamilies() {
        #expect(HostMacKind(modelIdentifier: "MacBookPro18,3") == .laptop)
        #expect(HostMacKind(modelIdentifier: "Macmini9,1") == .mini)
        #expect(HostMacKind(modelIdentifier: "MacPro7,1") == .macPro)
        #expect(HostMacKind(modelIdentifier: "iMac21,1") == .desktop)
        // Apple Silicon identifiers no longer name the family.
        #expect(HostMacKind(modelIdentifier: "Mac15,9") == .unknown)
        #expect(HostMacKind(modelIdentifier: "Mac13,1") == .unknown)
    }

    @Test("Device names identify the machine family")
    func deviceNamesIdentifyTheMachineFamily() {
        #expect(HostMacKind(deviceName: "MacBook Pro扬声器", host: .unknown) == .laptop)
        #expect(HostMacKind(deviceName: "Mac mini扬声器", host: .laptop) == .mini)
        #expect(HostMacKind(deviceName: "Mac Studio扬声器", host: .laptop) == .studio)
        #expect(HostMacKind(deviceName: "iMac扬声器", host: .laptop) == .desktop)
        #expect(HostMacKind(deviceName: "Mac Pro扬声器", host: .laptop) == .macPro)
        #expect(HostMacKind(deviceName: "内置扬声器", host: .mini) == .mini)
    }

    @Test("AirPods models use the symbol the system declares for their type")
    func airPodsModelsUseSystemSymbol() {
        #expect(candidates(name: "Wong-Harry的AirPods Pro 3", transport: .bluetooth).first == "airpods.pro.gen3")
        #expect(candidates(name: "AirPods Pro", transport: .bluetooth).first == "airpods.pro")
        #expect(candidates(name: "AirPods Pro (1st generation)", transport: .bluetooth).first == "airpods.pro.gen1")
        #expect(candidates(name: "AirPods Max", transport: .bluetooth).first == "airpodsmax")
        #expect(candidates(name: "AirPods", transport: .bluetooth).first == "airpods")
        #expect(candidates(name: "AirPods (3rd generation)", transport: .bluetooth).first == "airpods.gen3")
        #expect(candidates(name: "AirPods (4th generation)", transport: .bluetooth).first == "airpods.gen4")
        #expect(candidates(name: "AirPods 第四代", transport: .bluetooth).first == "airpods.gen4")
    }

    @Test("Beats models use the symbol the system declares for their type")
    func beatsModelsUseSystemSymbol() {
        #expect(candidates(name: "Beats Pill", transport: .bluetooth).first == "beats.pill")
        #expect(candidates(name: "Beats Solo Buds", transport: .bluetooth).first == "beats.solobuds")
        #expect(candidates(name: "Beats Studio Buds +", transport: .bluetooth).first == "beats.studiobuds.plus")
        #expect(candidates(name: "Beats Studio Buds", transport: .bluetooth).first == "beats.studiobuds")
        #expect(candidates(name: "Beats Fit Pro", transport: .bluetooth).first == "beats.fit.pro")
        #expect(candidates(name: "Powerbeats Pro 2", transport: .bluetooth).first == "beats.powerbeats.pro.2")
        #expect(candidates(name: "Powerbeats Pro", transport: .bluetooth).first == "beats.powerbeatspro")
        #expect(candidates(name: "Powerbeats3", transport: .bluetooth).first == "beats.powerbeats3")
        #expect(candidates(name: "Powerbeats", transport: .bluetooth).first == "beats.powerbeats")
        #expect(candidates(name: "BeatsX", transport: .bluetooth).first == "beats.earphones")
        #expect(candidates(name: "Beats Studio3", transport: .bluetooth).first == "beats.headphones")
    }

    @Test("HomePod, Apple TV and AirPlay use their own symbols")
    func homePodAppleTVAndAirPlaySymbols() {
        #expect(candidates(name: "HomePod mini", transport: .airPlay).first == "homepodmini")
        #expect(candidates(name: "客厅 HomePod", transport: .airPlay).first == "homepod")
        #expect(candidates(name: "客厅 Apple TV", transport: .airPlay).first == "appletv")
        #expect(candidates(name: "客厅", transport: .airPlay).first == "airplayaudio")
        #expect(candidates(name: "Living Room AirPlay", transport: .other).first == "airplayaudio")
    }

    @Test("External speakers keep the system speaker symbol")
    func externalSpeakersKeepSpeakerSymbol() {
        #expect(candidates(name: "JBL Flip 6 Speaker", transport: .bluetooth).first == "hifispeaker.fill")
        #expect(candidates(name: "客厅音箱", transport: .bluetooth).first == "hifispeaker.fill")
        #expect(candidates(name: "FiiO K5 Pro", transport: .usb).first == "hifispeaker.fill")
        #expect(candidates(name: "Background Music", transport: .virtual).first == "hifispeaker.fill")
        #expect(candidates(name: nil, transport: nil).first == "hifispeaker.fill")
    }

    @Test("Displays use the display symbol")
    func displayTransportsUseDisplaySymbol() {
        #expect(candidates(name: "XV272U", transport: .hdmi).first == "display")
        #expect(candidates(name: "DELL U2720Q", transport: .displayPort).first == "display")
        #expect(candidates(name: "Studio Display", transport: .other).first == "display")
        // No public device type describes a television, so the system shows the
        // display icon for anything that is not an Apple TV.
        #expect(candidates(name: "客厅电视", transport: .hdmi).first == "display")
        #expect(candidates(name: "Living Room TV", transport: .hdmi).first == "display")
    }

    @Test("Bluetooth audio defaults to headphones but honors speaker names")
    func bluetoothAudioClassification() {
        #expect(candidates(name: "OPPO Enco Air4i", transport: .bluetooth).first == "headphones")
        #expect(candidates(name: "Jabra Evolve2", transport: .bluetoothLowEnergy).first == "headphones")
        #expect(candidates(name: "罗技 USB 耳机", transport: .usb).first == "headphones")
    }

    @Test("Every device class resolves to a symbol the running system ships")
    func everyKindResolvesToAnAvailableSymbol() {
        for kind in AudioOutputDeviceKind.allCases {
            for host in [HostMacKind.laptop, .mini, .studio, .macPro, .desktop, .unknown] {
                let candidates = AudioOutputDeviceIcon.symbolCandidates(for: kind, host: host)
                let resolved = AudioOutputDeviceIcon.symbolName(for: kind, host: host)

                #expect(!candidates.isEmpty, "\(kind) \(host)")
                #expect(candidates.contains(resolved), "\(kind) \(host) resolved \(resolved)")
                #expect(
                    NSImage(systemSymbolName: resolved, accessibilityDescription: nil) != nil,
                    "\(kind) \(host) produced the unavailable symbol \(resolved)"
                )
            }
        }
    }

    @Test("Newer symbols fall back to one that older releases ship")
    func newerSymbolsFallBackToOlderOnes() {
        #expect(AudioOutputDeviceIcon.symbolCandidates(for: .airPodsPro).last == "headphones")
        #expect(AudioOutputDeviceIcon.symbolCandidates(for: .airPodsProGen3).last == "headphones")
        #expect(AudioOutputDeviceIcon.symbolCandidates(for: .homePodMini).last == "hifispeaker.fill")
        #expect(AudioOutputDeviceIcon.symbolCandidates(for: .speaker).last == "hifispeaker")
        #expect(AudioOutputDeviceIcon.symbolCandidates(for: .appleTV).last == "display")
    }

    @Test("CoreAudio transport values map to their families")
    func transportValuesMapToFamilies() {
        let expectedTransports: [(UInt32, AudioOutputTransport)] = [
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

        for (value, expected) in expectedTransports {
            #expect(AudioOutputTransport(coreAudioValue: value) == expected)
        }
        #expect(AudioOutputTransport(coreAudioValue: 0) == .other)
    }

    @Test("CoreAudio data sources map to their kinds")
    func dataSourceValuesMapToKinds() {
        #expect(AudioOutputDataSource(coreAudioValue: fourCharacterCode("ispk")) == .internalSpeaker)
        #expect(AudioOutputDataSource(coreAudioValue: fourCharacterCode("hdpn")) == .headphones)
        #expect(AudioOutputDataSource(coreAudioValue: fourCharacterCode("espk")) == .externalSpeaker)
        #expect(AudioOutputDataSource(coreAudioValue: 0) == .other)
    }

    @Test("A device icon shipped by the driver wins over the symbol")
    func driverIconWinsOverSymbol() throws {
        let iconURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("status-trio-device-icon-\(UUID().uuidString).icns")
        defer { try? FileManager.default.removeItem(at: iconURL) }
        try Data([0x69, 0x63, 0x6E, 0x73]).write(to: iconURL)

        let withIcon = AudioOutputDevice(
            id: 1,
            name: "Background Music",
            isCurrent: false,
            transport: .virtual,
            iconURL: iconURL
        )
        #expect(AudioOutputDeviceIcon.source(for: withIcon) == .image(iconURL))

        // A device whose driver ships no image keeps the class symbol.
        let withoutIcon = AudioOutputDevice(
            id: 2,
            name: "Background Music",
            isCurrent: false,
            transport: .virtual
        )
        #expect(AudioOutputDeviceIcon.source(for: withoutIcon) == .symbol("hifispeaker.fill"))

        // A stale icon path falls back too.
        let missingIcon = AudioOutputDevice(
            id: 3,
            name: "Background Music",
            isCurrent: false,
            transport: .virtual,
            iconURL: iconURL.appendingPathComponent("missing.icns")
        )
        #expect(AudioOutputDeviceIcon.source(for: missingIcon) == .symbol("hifispeaker.fill"))
    }

    private func candidates(
        name: String?,
        transport: AudioOutputTransport?,
        dataSource: AudioOutputDataSource? = nil,
        host: HostMacKind = .laptop
    ) -> [String] {
        AudioOutputDeviceIcon.symbolCandidates(
            for: AudioOutputDeviceIcon.kind(
                for: AudioOutputDevice(
                    id: 1,
                    name: name,
                    isCurrent: false,
                    transport: transport,
                    dataSource: dataSource
                )
            ),
            host: HostMacKind(deviceName: name, host: host)
        )
    }

    private func fourCharacterCode(_ code: String) -> UInt32 {
        code.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
