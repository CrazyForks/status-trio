import CoreAudio
import Testing
@testable import StatusTrioCore

struct AudioOutputDeviceIconTests {
    @Test("AirPods models use the matching AirPods symbol")
    func airPodsModelsUseMatchingSymbol() {
        #expect(
            symbol(name: "Wong-Harry的AirPods Pro", transport: .bluetooth)
                == "airpodspro"
        )
        #expect(symbol(name: "AirPods Max", transport: .bluetooth) == "airpodsmax")
        #expect(symbol(name: "AirPods", transport: .bluetooth) == "airpods")
        #expect(symbol(name: "airpods pro 3", transport: .bluetooth) == "airpodspro")
    }

    @Test("AirPods keep their symbol regardless of the reported transport")
    func airPodsSymbolIgnoresTransport() {
        #expect(symbol(name: "AirPods Pro", transport: nil) == "airpodspro")
        #expect(symbol(name: "AirPods Pro", transport: .other) == "airpodspro")
    }

    @Test("Built-in output follows its live data source")
    func builtInOutputFollowsDataSource() {
        #expect(
            symbol(name: "MacBook Pro扬声器", transport: .builtIn, dataSource: .internalSpeaker)
                == "hifispeaker"
        )
        #expect(
            symbol(name: "MacBook Pro扬声器", transport: .builtIn, dataSource: .headphones)
                == "headphones"
        )
        #expect(
            symbol(name: "MacBook Pro Speakers", transport: .builtIn, dataSource: .externalSpeaker)
                == "hifispeaker"
        )
    }

    @Test("Display transports use the display symbol")
    func displayTransportsUseDisplaySymbol() {
        #expect(symbol(name: "XV272U", transport: .hdmi) == "display")
        #expect(symbol(name: "DELL U2720Q", transport: .displayPort) == "display")
        #expect(symbol(name: "客厅电视", transport: .hdmi) == "tv")
        #expect(symbol(name: "Living Room TV", transport: .usb) == "tv")
    }

    @Test("Bluetooth audio defaults to headphones but honors speaker names")
    func bluetoothAudioClassification() {
        #expect(symbol(name: "EDIFIER LolliPods 2022版", transport: .bluetooth) == "headphones")
        #expect(symbol(name: "Jabra Evolve2", transport: .bluetoothLowEnergy) == "headphones")
        #expect(symbol(name: "JBL Flip 6 Speaker", transport: .bluetooth) == "hifispeaker")
        #expect(symbol(name: "客厅音箱", transport: .bluetooth) == "hifispeaker")
    }

    @Test("Wired and USB audio hardware follows its name")
    func wiredHardwareClassification() {
        #expect(symbol(name: "External Headphones", transport: .builtIn, dataSource: .other) == "headphones")
        #expect(symbol(name: "罗技 USB 耳机", transport: .usb) == "headphones")
        #expect(symbol(name: "FiiO K5 Pro", transport: .usb) == "hifispeaker")
        #expect(symbol(name: "Aggregate Device", transport: .aggregate) == "hifispeaker")
    }

    @Test("AirPlay and HomePod use their own symbols")
    func airPlayAndHomePodSymbols() {
        #expect(symbol(name: "客厅", transport: .airPlay) == "airplayaudio")
        #expect(symbol(name: "客厅 HomePod", transport: .airPlay) == "homepod")
    }

    @Test("Current devices use the filled symbol when one exists")
    func currentDevicesUseFilledSymbol() {
        #expect(symbol(name: "MacBook Pro扬声器", transport: .builtIn, isCurrent: true) == "hifispeaker.fill")
        #expect(symbol(name: "HomePod", transport: .airPlay, isCurrent: true) == "homepod.fill")
        #expect(symbol(name: "AirPods Pro", transport: .bluetooth, isCurrent: true) == "airpodspro")
    }

    @Test("Devices without a known type keep the speaker symbol")
    func unknownDevicesKeepSpeakerSymbol() {
        #expect(symbol(name: "Background Music", transport: .virtual) == "hifispeaker")
        #expect(symbol(name: nil, transport: nil) == "hifispeaker")
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

    private func symbol(
        name: String?,
        transport: AudioOutputTransport?,
        dataSource: AudioOutputDataSource? = nil,
        isCurrent: Bool = false
    ) -> String {
        AudioOutputDeviceIcon.symbolName(
            for: AudioOutputDevice(
                id: 1,
                name: name,
                isCurrent: isCurrent,
                transport: transport,
                dataSource: dataSource
            )
        )
    }

    private func fourCharacterCode(_ code: String) -> UInt32 {
        code.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
