import XCTest
@testable import StatusTrioCore

/// The centre-slot priority table for the input-source mode, plus proof that
/// `.automatic` keeps the shipped behaviour bit for bit.
final class InputSourceIconPresentationTests: XCTestCase {
    private let iconURL = URL(fileURLWithPath: "/fixture/menu_icon.pdf")

    func testInputSourceIconWinsWhenItCanBeRead() {
        let scene = scene(
            snapshot: snapshot(),
            inputSource: descriptor(iconURL: iconURL),
            configuration: configuration(centerSource: .inputSource)
        )

        XCTAssertEqual(scene.center, .symbol(IconSymbolState(
            source: .image(url: iconURL, fallbackSymbol: "keyboard"),
            color: .primary,
            scale: ConnectionIconOptions.defaultInputSourceScale
        )))
    }

    func testSourceWithoutIconFallsBackToItsShortLabel() {
        let scene = scene(
            snapshot: snapshot(),
            inputSource: descriptor(iconURL: nil, shortLabel: "A"),
            configuration: configuration(centerSource: .inputSource)
        )

        XCTAssertEqual(scene.center, .text(IconTextState(text: "A", color: .primary, scale: 1)))
    }

    func testSourceWithoutIconOrLabelFallsBackToAKeyboardSymbol() {
        let scene = scene(
            snapshot: snapshot(),
            inputSource: descriptor(iconURL: nil, shortLabel: nil),
            configuration: configuration(centerSource: .inputSource)
        )

        XCTAssertEqual(scene.center, .symbol(IconSymbolState(
            source: .symbol(name: "keyboard", variableValue: nil, fallback: nil),
            color: .primary,
            scale: ConnectionIconOptions.defaultInputSourceScale
        )))
    }

    func testBatteryPercentageInTheConnectionSlotStillWins() {
        let scene = scene(
            snapshot: snapshot(batteryPercentage: 68),
            inputSource: descriptor(iconURL: iconURL),
            configuration: configuration(centerSource: .inputSource, showsPercentageInConnectionSlot: true)
        )

        XCTAssertEqual(scene.center, .text(IconTextState(text: "68", color: .primary, scale: 1)))
    }

    func testNetworkOutageOverridesTheInputSourceWhenAskedTo() {
        for wifiState in [WiFiState.off, .notAssociated, .noInternet, .unavailable] {
            let scene = scene(
                snapshot: snapshot(wifi: WiFiStatus(state: wifiState, rssi: nil)),
                inputSource: descriptor(iconURL: iconURL),
                configuration: configuration(centerSource: .inputSource)
            )

            XCTAssertNotEqual(
                scene.center,
                .symbol(IconSymbolState(
                    source: .image(url: iconURL, fallbackSymbol: "keyboard"),
                    color: .primary,
                    scale: ConnectionIconOptions.defaultInputSourceScale
                )),
                "\(wifiState) must keep the genuine network warning"
            )
        }
    }

    func testWiredLinkWithWiFiOffIsNotAnOutage() {
        let scene = scene(
            snapshot: snapshot(
                wifi: WiFiStatus(state: .off, rssi: nil),
                connection: .ethernet
            ),
            inputSource: descriptor(iconURL: iconURL),
            configuration: configuration(centerSource: .inputSource)
        )

        XCTAssertEqual(scene.center, .symbol(IconSymbolState(
            source: .image(url: iconURL, fallbackSymbol: "keyboard"),
            color: .primary,
            scale: ConnectionIconOptions.defaultInputSourceScale
        )))
    }

    func testNetworkOutagePrioritizationCanBeSwitchedOff() {
        let scene = scene(
            snapshot: snapshot(wifi: WiFiStatus(state: .noInternet, rssi: nil)),
            inputSource: descriptor(iconURL: iconURL),
            configuration: configuration(
                centerSource: .inputSource,
                prioritizesNetworkErrors: false
            )
        )

        XCTAssertEqual(scene.center, .symbol(IconSymbolState(
            source: .image(url: iconURL, fallbackSymbol: "keyboard"),
            color: .primary,
            scale: ConnectionIconOptions.defaultInputSourceScale
        )))
    }

    func testMissingSourceFallsBackToTheBluetoothReplacement() {
        let scene = scene(
            snapshot: snapshot(device: PresentationFixtures.bluetoothDevice),
            inputSource: nil,
            configuration: configuration(
                centerSource: .inputSource,
                bluetoothReplacesNetworkIcon: true
            )
        )

        XCTAssertEqual(
            scene.center?.colorRole,
            .bluetooth,
            "a missing input source must fall back to the shipped bluetooth replacement"
        )
    }

    func testInputSourceWinsOverTheBluetoothReplacement() {
        let scene = scene(
            snapshot: snapshot(device: PresentationFixtures.bluetoothDevice),
            inputSource: descriptor(iconURL: iconURL),
            configuration: configuration(
                centerSource: .inputSource,
                bluetoothReplacesNetworkIcon: true
            )
        )

        XCTAssertEqual(scene.center, .symbol(IconSymbolState(
            source: .image(url: iconURL, fallbackSymbol: "keyboard"),
            color: .primary,
            scale: ConnectionIconOptions.defaultInputSourceScale
        )))
    }

    func testAutomaticModeIgnoresTheInputSourceEntirely() {
        let snapshot = snapshot()
        let without = scene(
            snapshot: snapshot,
            inputSource: nil,
            configuration: configuration(centerSource: .automatic)
        )
        let with = scene(
            snapshot: snapshot,
            inputSource: descriptor(iconURL: iconURL),
            configuration: configuration(centerSource: .automatic)
        )

        XCTAssertEqual(with, without)
    }

    func testAutomaticFallbackRendersTheSameSceneAsTheShippedDecision() {
        let snapshot = snapshot(wifi: WiFiStatus(state: .noInternet, rssi: nil))
        let fallback = scene(
            snapshot: snapshot,
            inputSource: nil,
            configuration: configuration(centerSource: .inputSource)
        )
        let automatic = scene(
            snapshot: snapshot,
            inputSource: nil,
            configuration: configuration(centerSource: .automatic)
        )

        XCTAssertEqual(fallback, automatic)
    }

    // MARK: - Fixtures

    private func descriptor(
        iconURL: URL?,
        shortLabel: String? = "拼"
    ) -> InputSourceDescriptor {
        InputSourceDescriptor(
            id: "com.example.pinyin",
            localizedName: "Example 拼音",
            primaryLanguage: "zh-Hans",
            iconURL: iconURL,
            shortLabel: shortLabel
        )
    }

    private func snapshot(
        batteryPercentage: Int = 68,
        wifi: WiFiStatus = WiFiStatus(state: .connected, rssi: -61),
        connection: NetworkConnection = .wifi,
        device: AudioOutputDevice? = nil
    ) -> StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: batteryPercentage,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: wifi,
            connection: connection,
            volume: VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: device?.name,
                currentDevice: device
            )
        )
    }

    private func configuration(
        centerSource: ConnectionCenterSource,
        prioritizesNetworkErrors: Bool = true,
        bluetoothReplacesNetworkIcon: Bool = false,
        showsPercentageInConnectionSlot: Bool = false
    ) -> IconPresentationConfiguration {
        IconPresentationConfiguration(
            battery: .standard,
            connection: ConnectionIconOptions(
                showsBatteryPercentageInConnectionSlot: showsPercentageInConnectionSlot,
                centerSource: centerSource,
                prioritizesNetworkErrorsOverInputSource: prioritizesNetworkErrors,
                wifiScale: 1.6
            ),
            volume: .standard,
            bluetooth: BluetoothAudioIconOptions(
                replacesNetworkIcon: bluetoothReplacesNetworkIcon,
                prioritizesNetworkErrors: true
            )
        )
    }

    private func scene(
        snapshot: StatusSnapshot,
        inputSource: InputSourceDescriptor?,
        configuration: IconPresentationConfiguration
    ) -> IconSceneState {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot,
                audioIcon: nil,
                inputSource: inputSource
            ),
            configuration: configuration
        )
    }
}
