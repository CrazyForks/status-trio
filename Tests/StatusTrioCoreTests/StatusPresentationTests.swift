import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusPresentationTests: XCTestCase {
    func testBatteryTitleAndSubtitlePriority() {
        let localization = makeLocalization(.simplifiedChinese)

        XCTAssertEqual(
            StatusPresentation.batteryTitle(
                makeBattery(percentage: 68),
                localization: localization
            ),
            "电池 · 68%"
        )
        XCTAssertEqual(
            StatusPresentation.batterySubtitle(
                makeBattery(
                    isPresent: false,
                    isCharging: true,
                    isCharged: true,
                    isLowPowerMode: true,
                    isConnectedToPower: true
                ),
                localization: localization
            ),
            "无电池设备"
        )
        XCTAssertEqual(
            StatusPresentation.batterySubtitle(
                makeBattery(
                    isCharging: true,
                    isCharged: true,
                    isLowPowerMode: true,
                    isConnectedToPower: true
                ),
                localization: localization
            ),
            "已充满"
        )
        XCTAssertEqual(
            StatusPresentation.batterySubtitle(
                makeBattery(
                    isCharging: true,
                    isLowPowerMode: true,
                    isConnectedToPower: true,
                    timeToFullChargeMinutes: 85
                ),
                localization: localization
            ),
            "预计 1 小时 25 分钟充满"
        )
        XCTAssertEqual(
            StatusPresentation.batterySubtitle(
                makeBattery(isCharging: true, isConnectedToPower: true),
                localization: localization
            ),
            "正在计算充满时间"
        )
        XCTAssertEqual(
            StatusPresentation.batterySubtitle(
                makeBattery(isLowPowerMode: true, isConnectedToPower: true),
                localization: localization
            ),
            "低电量模式"
        )
        XCTAssertEqual(
            StatusPresentation.batterySubtitle(
                makeBattery(isConnectedToPower: true),
                localization: localization
            ),
            "已连接电源"
        )
        XCTAssertEqual(
            StatusPresentation.batterySubtitle(
                makeBattery(),
                localization: localization
            ),
            "电池供电"
        )
    }

    func testBatteryTimeToFullFormatting() {
        let localization = makeLocalization(.simplifiedChinese)
        let cases: [(Int?, String)] = [
            (1, "预计 1 分钟充满"),
            (59, "预计 59 分钟充满"),
            (60, "预计 1 小时充满"),
            (85, "预计 1 小时 25 分钟充满"),
            (120, "预计 2 小时充满"),
            (nil, "正在计算充满时间"),
            (0, "正在计算充满时间"),
            (-1, "正在计算充满时间")
        ]

        for (minutes, expected) in cases {
            XCTAssertEqual(
                StatusPresentation.batteryTimeToFullText(
                    minutes: minutes,
                    localization: localization
                ),
                expected,
                "minutes: \(String(describing: minutes))"
            )
        }
    }

    func testWiFiValueAndSubtitleForEveryState() {
        let localization = makeLocalization(.simplifiedChinese)
        let cases: [(WiFiStatus, String, String)] = [
            (WiFiStatus(state: .connected, rssi: -55), "3 格", "已连接"),
            (WiFiStatus(state: .notAssociated, rssi: nil), "未关联", "Wi-Fi 开启，未关联"),
            (WiFiStatus(state: .off, rssi: nil), "关闭", "Wi-Fi 关闭或不可用"),
            (WiFiStatus(state: .noInternet, rssi: nil), "无互联网", "网络可达性检查失败"),
            (WiFiStatus(state: .hotspot, rssi: nil), "iPhone 热点", "使用 iPhone 热点"),
            (WiFiStatus(state: .temporary, rssi: nil), "临时连接", "临时 Wi-Fi 连接"),
            (WiFiStatus(state: .shared, rssi: nil), "正在共享", "正在共享互联网"),
            (WiFiStatus(state: .unavailable, rssi: nil), "不可用", "无法读取网络状态")
        ]

        for (wifi, expectedValue, expectedSubtitle) in cases {
            XCTAssertEqual(
                StatusPresentation.wifiValue(wifi, localization: localization),
                expectedValue,
                "value for \(wifi.state)"
            )
            XCTAssertEqual(
                StatusPresentation.wifiSubtitle(wifi, localization: localization),
                expectedSubtitle,
                "subtitle for \(wifi.state)"
            )
        }
    }

    func testActionKeysUseSelectedLanguage() {
        let localization = makeLocalization(.simplifiedChinese)

        XCTAssertEqual(localization.string(.menuSettings), "设置…")
        XCTAssertEqual(localization.string(.wifiActionRequestNameAccess), "允许定位以显示 Wi-Fi 名称")
        XCTAssertEqual(localization.string(.wifiActionOpenLocationSettings), "去设置中允许定位")
        XCTAssertEqual(localization.string(.wifiActionOpenSettings), "打开 Wi-Fi 设置")
        XCTAssertEqual(localization.string(.batteryActionOpenSettings), "打开电源设置")
        XCTAssertEqual(localization.string(.volumeActionOpenSettings), "打开声音设置")
    }

    func testWiFiSubtitlePrefersSSID() {
        let localization = makeLocalization(.simplifiedChinese)

        XCTAssertEqual(
            StatusPresentation.wifiSubtitle(
                WiFiStatus(
                    state: .connected,
                    rssi: -55,
                    ssid: "Studio Wi-Fi",
                    nameAccess: .authorized
                ),
                localization: localization
            ),
            "Studio Wi-Fi"
        )
    }

    func testStatusItemAccessibilitySummaryIncludesAllThreeStatuses() {
        let localization = makeLocalization(.simplifiedChinese)
        let snapshot = StatusSnapshot(
            battery: makeBattery(
                isCharging: true,
                isConnectedToPower: true,
                percentage: 73,
                timeToFullChargeMinutes: 85
            ),
            wifi: WiFiStatus(state: .connected, rssi: -55),
            volume: VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: "MacBook Pro Speakers"
            )
        )

        XCTAssertEqual(
            StatusPresentation.statusItemAccessibilityValue(
                snapshot,
                localization: localization
            ),
            "电池 73%（预计 1 小时 25 分钟充满），Wi-Fi 3 格，音量 50% · 2 格"
        )
    }

    func testStatusItemAccessibilitySummaryIncludesWiFiNameWhenAvailable() {
        let localization = makeLocalization(.simplifiedChinese)
        let snapshot = StatusSnapshot(
            battery: makeBattery(percentage: 73),
            wifi: WiFiStatus(
                state: .connected,
                rssi: -55,
                ssid: "Office",
                nameAccess: .authorized
            ),
            volume: VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: "MacBook Pro Speakers"
            )
        )

        XCTAssertEqual(
            StatusPresentation.statusItemAccessibilityValue(
                snapshot,
                localization: localization
            ),
            "电池 73%，Wi-Fi Office，3 格，音量 50% · 2 格"
        )
    }

    func testStatusItemAccessibilitySummaryUsesEthernetWhenWired() {
        let localization = makeLocalization(.simplifiedChinese)
        let snapshot = StatusSnapshot(
            battery: makeBattery(percentage: 73),
            wifi: WiFiStatus(state: .connected, rssi: -55),
            connection: .ethernet,
            volume: VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: "MacBook Pro Speakers"
            )
        )

        XCTAssertEqual(
            StatusPresentation.statusItemAccessibilityValue(
                snapshot,
                localization: localization
            ),
            "电池 73%，以太网已连接，音量 50% · 2 格"
        )
    }

    func testEnglishStatusPresentation() {
        let localization = makeLocalization(.english)

        XCTAssertEqual(
            StatusPresentation.batteryTitle(
                makeBattery(percentage: 68),
                localization: localization
            ),
            "Battery · 68%"
        )
        XCTAssertEqual(
            StatusPresentation.volumeValue(
                VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Speaker"),
                localization: localization
            ),
            "50% · 2 bars"
        )
    }

    func testVolumeTitleUsesClampedPercentage() {
        let localization = makeLocalization(.simplifiedChinese)

        XCTAssertEqual(
            StatusPresentation.volumeTitle(
                VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Speaker"),
                localization: localization
            ),
            "音量 · 50%"
        )
        XCTAssertEqual(
            StatusPresentation.volumeTitle(
                VolumeStatus(scalar: 0.62, isMuted: true, deviceName: "Speaker"),
                localization: localization
            ),
            "音量 · 62%"
        )
        XCTAssertEqual(
            StatusPresentation.volumeTitle(
                VolumeStatus(scalar: nil, isMuted: false, deviceName: nil),
                localization: localization
            ),
            "音量 · —"
        )
    }

    func testVolumeValueForNilMutedAndNormalStates() {
        let localization = makeLocalization(.simplifiedChinese)

        XCTAssertEqual(
            StatusPresentation.volumeValue(
                VolumeStatus(scalar: nil, isMuted: false, deviceName: nil),
                localization: localization
            ),
            "—"
        )
        XCTAssertEqual(
            StatusPresentation.volumeValue(
                VolumeStatus(scalar: 0.62, isMuted: true, deviceName: "Speaker"),
                localization: localization
            ),
            "静音"
        )
        XCTAssertEqual(
            StatusPresentation.volumeValue(
                VolumeStatus(scalar: 0.62, isMuted: false, deviceName: "Speaker"),
                localization: localization
            ),
            "62% · 3 格"
        )
        XCTAssertEqual(
            StatusPresentation.volumeValue(
                VolumeStatus(scalar: 0.625, isMuted: false, deviceName: "Speaker"),
                localization: localization
            ),
            "63% · 3 格"
        )
    }

    func testVolumeValueRejectsNonFiniteScalars() {
        let localization = makeLocalization(.simplifiedChinese)

        for scalar in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(
                StatusPresentation.volumeValue(
                    VolumeStatus(scalar: scalar, isMuted: false, deviceName: "Speaker"),
                    localization: localization
                ),
                "—",
                "value for \(scalar)"
            )
        }
    }

    func testVolumeValueClampsFiniteScalars() {
        let localization = makeLocalization(.simplifiedChinese)

        XCTAssertEqual(
            StatusPresentation.volumeValue(
                VolumeStatus(scalar: -0.5, isMuted: false, deviceName: "Speaker"),
                localization: localization
            ),
            "0% · 0 格"
        )
        XCTAssertEqual(
            StatusPresentation.volumeValue(
                VolumeStatus(scalar: 1.5, isMuted: false, deviceName: "Speaker"),
                localization: localization
            ),
            "100% · 4 格"
        )
    }

    func testVolumeValueStepMapping() {
        let localization = makeLocalization(.simplifiedChinese)
        let cases: [(Double, Int)] = [
            (0.00, 0),
            (0.01, 1),
            (0.25, 1),
            (0.26, 2),
            (0.50, 2),
            (0.51, 3),
            (0.75, 3),
            (0.76, 4),
            (1.00, 4)
        ]

        for (scalar, steps) in cases {
            XCTAssertEqual(
                StatusPresentation.volumeValue(
                    VolumeStatus(scalar: scalar, isMuted: false, deviceName: "Speaker"),
                    localization: localization
                ),
                "\(Int((scalar * 100).rounded()))% · \(steps) 格"
            )
        }
    }

    func testVolumeSubtitleUsesDeviceNameOrFallback() {
        let localization = makeLocalization(.simplifiedChinese)

        XCTAssertEqual(
            StatusPresentation.volumeSubtitle(
                VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "MacBook Speakers"),
                localization: localization
            ),
            "MacBook Speakers"
        )
        XCTAssertEqual(
            StatusPresentation.volumeSubtitle(
                VolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil),
                localization: localization
            ),
            "无默认输出设备"
        )
    }

    private func makeLocalization(_ language: AppLanguage) -> Localization {
        let suiteName = "StatusTrioCoreTests.StatusPresentation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        return localization
    }

    private func makeBattery(
        isPresent: Bool = true,
        isCharging: Bool = false,
        isCharged: Bool = false,
        isLowPowerMode: Bool = false,
        isConnectedToPower: Bool = false,
        percentage: Int = 100,
        timeToFullChargeMinutes: Int? = nil
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: isPresent,
            isCharging: isCharging,
            isCharged: isCharged,
            timeToFullChargeMinutes: timeToFullChargeMinutes,
            isLowPowerMode: isLowPowerMode,
            isConnectedToPower: isConnectedToPower
        )
    }
}
