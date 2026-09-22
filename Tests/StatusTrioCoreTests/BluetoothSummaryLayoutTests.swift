import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The Bluetooth row mixes device names and AirPods levels in one line inside
/// a 330-point popover, so its longest states have to be rendered, not assumed.
@MainActor
final class BluetoothSummaryLayoutTests: XCTestCase {
    func testSummaryStatesFitThePopover() async throws {
        let states: [(name: String, authorization: BluetoothAuthorizationStatus, devices: [BluetoothDevice])] = [
            ("permission", .notDetermined, []),
            ("airpods", .allowed, [
                BluetoothDevice(id: "AA", name: "AirPods Pro", kind: .audio, isConnected: true)
            ]),
            ("mixed", .allowed, [
                BluetoothDevice(id: "AA", name: "AirPods Pro", kind: .audio, isConnected: true),
                BluetoothDevice(id: "BB", name: "MX Master 3", kind: .peripheral, isConnected: true),
                BluetoothDevice(id: "CC", name: "Magic Keyboard", kind: .peripheral, isConnected: true)
            ]),
            ("none", .allowed, [])
        ]

        let airPodsLevels: [String: BluetoothBatteryLevel] = [
            BluetoothBatteryReader.normalizedAddress("AA"): BluetoothBatteryLevel(
                deviceAddress: "AA", main: nil, left: 80, right: 75, caseLevel: 60)
        ]
        // The longest state the row can draw now that every connected device
        // reports the level the report carries for it: the line has to truncate
        // rather than grow the two-line layout.
        let mixedLevels: [String: BluetoothBatteryLevel] = [
            BluetoothBatteryReader.normalizedAddress("AA"): BluetoothBatteryLevel(
                deviceAddress: "AA", main: nil, left: 80, right: 75, caseLevel: 60),
            BluetoothBatteryReader.normalizedAddress("BB"): BluetoothBatteryLevel(
                deviceAddress: "BB", main: 45, left: nil, right: nil, caseLevel: nil),
            BluetoothBatteryReader.normalizedAddress("CC"): BluetoothBatteryLevel(
                deviceAddress: "CC", main: 90, left: nil, right: nil, caseLevel: nil)
        ]
        let levelsByState: [String: [String: BluetoothBatteryLevel]] = [
            "airpods": airPodsLevels,
            "mixed": mixedLevels
        ]

        for state in states {
            for language in [AppLanguage.english, .simplifiedChinese] {
                let size = try await render(
                    language: language,
                    authorization: state.authorization,
                    devices: state.devices,
                    batteryLevels: levelsByState[state.name] ?? [:],
                    listOptions: BluetoothDeviceListOptions(showsList: false, maxVisibleDevices: 5, order: []),
                    named: "bluetooth-\(language.rawValue)-\(state.name)"
                )
                XCTAssertEqual(size.width, 330, accuracy: 0.5)
                // One summary row: the two-line layout must not grow.
                XCTAssertLessThan(size.height, 120)
            }
        }
    }

    /// With the list on, the row grows by the visible device rows and the
    /// expansion control — in both a narrow-glyph and a wide-glyph language.
    func testDeviceListGrowsTheRowWithoutWideningIt() async throws {
        let devices = (1...6).map { index in
            BluetoothDevice(
                id: "AA:00:00:00:00:0\(index)",
                name: "Device \(index)",
                kind: .audio,
                isConnected: index <= 2
            )
        }
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 3, order: [])

        for language in [AppLanguage.english, .simplifiedChinese] {
            let withList = try await render(
                language: language,
                authorization: .allowed,
                devices: devices,
                listOptions: options,
                named: "bluetooth-list-\(language.rawValue)"
            )
            let withoutList = try await render(
                language: language,
                authorization: .allowed,
                devices: devices,
                listOptions: BluetoothDeviceListOptions(showsList: false, maxVisibleDevices: 3, order: []),
                named: "bluetooth-nolist-\(language.rawValue)"
            )

            XCTAssertEqual(withList.width, 330, accuracy: 0.5)
            XCTAssertGreaterThan(
                withList.height,
                withoutList.height,
                "the list must add the device rows in \(language.rawValue)"
            )
        }
    }

    /// No paired devices means no list: the row keeps its own message and its
    /// original height.
    func testEmptyDeviceListDoesNotChangeTheRow() async throws {
        let options = BluetoothDeviceListOptions(showsList: true, maxVisibleDevices: 3, order: [])

        let withSettingOn = try await render(
            language: .english,
            authorization: .allowed,
            devices: [],
            listOptions: options,
            named: "bluetooth-list-empty"
        )

        XCTAssertEqual(withSettingOn.width, 330, accuracy: 0.5)
        XCTAssertLessThan(withSettingOn.height, 120)
    }

    private func render(
        language: AppLanguage,
        authorization: BluetoothAuthorizationStatus,
        devices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel] = [:],
        listOptions: BluetoothDeviceListOptions = .standard,
        named name: String
    ) async throws -> NSSize {
        let suite = "StatusTrioCoreTests.BluetoothSummary.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))

        let notifications = NotificationCenter()
        let controller = BluetoothDeviceController(
            worker: SummaryBluetoothDeviceReader(result: .success(devices)),
            stateMonitor: SummaryBluetoothStateMonitor(
                authorization: authorization,
                managerState: authorization == .allowed ? .poweredOn : .unknown
            ),
            batteryReader: SummaryBluetoothBatteryReader(result: batteryLevels),
            notificationCenter: notifications,
            workspaceNotificationCenter: notifications
        )
        if authorization == .allowed {
            controller.activate()
        } else {
            controller.prepareForPresentation()
        }

        let view = BluetoothStatusView(
            controller: controller,
            showsBatteryLevels: true,
            listOptions: listOptions,
            onOpenDetails: {},
            onRequestAuthorization: {},
            onOpenBluetoothSettings: {}
        )
        .padding(14)
        .frame(width: 330)
        .background(Color(white: 0.96))
        .environmentObject(localization)
        .environment(\.colorScheme, .light)

        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        // Let the controller publish the fixture and the row settle.
        try await Task.sleep(for: .milliseconds(50))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        if let directory = ProcessInfo.processInfo.environment["STATUS_TRIO_BLUETOOTH_SNAPSHOTS"] {
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try png.write(to: url.appendingPathComponent("\(name).png"))
        }
        controller.deactivate()
        return size
    }
}

private final class SummaryBluetoothDeviceReader: BluetoothPairedDeviceReading {
    private let result: BluetoothWorkerResult

    init(result: BluetoothWorkerResult) {
        self.result = result
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(result)
    }
}

private final class SummaryBluetoothBatteryReader: BluetoothBatteryReading {
    private let result: [String: BluetoothBatteryLevel]

    init(result: [String: BluetoothBatteryLevel]) {
        self.result = result
    }

    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion(result)
    }
}

@MainActor
private final class SummaryBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus
    private let managerState: BluetoothManagerState

    init(authorization: BluetoothAuthorizationStatus, managerState: BluetoothManagerState) {
        self.authorization = authorization
        self.managerState = managerState
    }

    func start() {
        onStateChange?(authorization, managerState)
    }

    func stop() {}
}
