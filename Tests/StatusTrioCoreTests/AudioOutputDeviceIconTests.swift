import AppKit
import CoreAudio
import Testing
@testable import StatusTrioCore

struct AudioOutputDeviceIconTests {
    @Test("AirPods models use the symbol the system declares for their type")
    func airPodsModelsUseSystemSymbol() {
        #expect(candidates(name: "Wong-Harry的AirPods Pro", transport: .bluetooth).first == "airpods.pro.gen1")
        #expect(candidates(name: "airpods pro 3", transport: .bluetooth).first == "airpods.pro.gen1")
        #expect(candidates(name: "AirPods Max", transport: .bluetooth).first == "airpodsmax")
        #expect(candidates(name: "AirPods", transport: .bluetooth).first == "airpods")
        #expect(candidates(name: "AirPods (3rd generation)", transport: .bluetooth).first == "airpods.gen3")
        #expect(candidates(name: "AirPods 第三代", transport: .bluetooth).first == "airpods.gen3")
    }

    @Test("Beats models use the symbol the system declares for their type")
    func beatsModelsUseSystemSymbol() {
        #expect(candidates(name: "Powerbeats Pro", transport: .bluetooth).first == "beats.powerbeatspro")
        #expect(candidates(name: "Beats Studio Buds", transport: .bluetooth).first == "beats.studiobuds")
        #expect(candidates(name: "Beats Fit Pro", transport: .bluetooth).first == "beats.fit.pro")
        #expect(candidates(name: "BeatsX", transport: .bluetooth).first == "beats.earphones")
        #expect(candidates(name: "Beats Studio3", transport: .bluetooth).first == "beats.headphones")
    }

    @Test("HomePod and Apple TV use the symbol the system declares")
    func homePodAndAppleTVUseSystemSymbol() {
        #expect(candidates(name: "HomePod mini", transport: .airPlay).first == "homepodmini")
        #expect(candidates(name: "客厅 HomePod", transport: .airPlay).first == "homepod")
        #expect(candidates(name: "客厅 Apple TV", transport: .airPlay).first == "appletv")
    }

    @Test("Speaker devices use the system speaker symbol")
    func speakerDevicesUseSystemSymbol() {
        #expect(candidates(name: "MacBook Pro扬声器", transport: .builtIn, dataSource: .internalSpeaker).first == "hifispeaker.fill")
        #expect(candidates(name: "MacBook Pro Speakers", transport: .builtIn, dataSource: .externalSpeaker).first == "hifispeaker.fill")
        #expect(candidates(name: "JBL Flip 6 Speaker", transport: .bluetooth).first == "hifispeaker.fill")
        #expect(candidates(name: "客厅音箱", transport: .bluetooth).first == "hifispeaker.fill")
        #expect(candidates(name: "FiiO K5 Pro", transport: .usb).first == "hifispeaker.fill")
        #expect(candidates(name: "Background Music", transport: .virtual).first == "hifispeaker.fill")
        #expect(candidates(name: nil, transport: nil).first == "hifispeaker.fill")
    }

    @Test("Built-in output follows its live data source")
    func builtInOutputFollowsDataSource() {
        #expect(candidates(name: "MacBook Pro扬声器", transport: .builtIn, dataSource: .headphones).first == "headphones")
        #expect(candidates(name: "External Headphones", transport: .builtIn, dataSource: .other).first == "headphones")
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
        #expect(candidates(name: "EDIFIER LolliPods 2022版", transport: .bluetooth).first == "headphones")
        #expect(candidates(name: "Jabra Evolve2", transport: .bluetoothLowEnergy).first == "headphones")
        #expect(candidates(name: "罗技 USB 耳机", transport: .usb).first == "headphones")
    }

    @Test("Every device class resolves to a symbol the running system ships")
    func everyKindResolvesToAnAvailableSymbol() {
        for kind in AudioOutputDeviceKind.allCases {
            let candidates = AudioOutputDeviceIcon.symbolCandidates(for: kind)
            let resolved = AudioOutputDeviceIcon.symbolName(for: kind)

            #expect(!candidates.isEmpty, "\(kind)")
            #expect(candidates.contains(resolved), "\(kind) resolved \(resolved)")
            #expect(
                NSImage(systemSymbolName: resolved, accessibilityDescription: nil) != nil,
                "\(kind) produced the unavailable symbol \(resolved)"
            )
        }
    }

    @Test("Older releases fall back to a symbol that always exists")
    func olderReleasesFallBackToAvailableSymbols() {
        // `airpods.pro.gen1` only exists on newer macOS releases, so each class
        // keeps an older symbol last in the list.
        #expect(AudioOutputDeviceIcon.symbolCandidates(for: .airPodsPro).last == "headphones")
        #expect(AudioOutputDeviceIcon.symbolCandidates(for: .airPodsGen3).last == "headphones")
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

    private func candidates(
        name: String?,
        transport: AudioOutputTransport?,
        dataSource: AudioOutputDataSource? = nil
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
            )
        )
    }

    private func fourCharacterCode(_ code: String) -> UInt32 {
        code.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
