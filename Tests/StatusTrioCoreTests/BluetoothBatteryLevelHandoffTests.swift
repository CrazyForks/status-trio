import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The summary row and the detail list share one "read battery levels" flag.
/// SwiftUI runs the outgoing summary's `onDisappear` *after* the incoming
/// detail page's `onAppear`, so a summary that released the flag on disappear
/// switched off the read the detail page had just asked for. The detail page
/// showed "Unavailable" for every device while the summary still showed the
/// AirPods level it had read a moment earlier. The detail page is the owner
/// that releases the flag.
@MainActor
final class BluetoothBatteryLevelHandoffTests: XCTestCase {
    func testDetailPageKeepsReadingLevelsAfterLeavingTheSummary() async {
        let batteryReader = HandoffBatteryReader()
        let controller = BluetoothDeviceController(
            worker: HandoffDeviceReader(),
            stateMonitor: HandoffStateMonitor(),
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let model = HandoffModel()
        controller.activate()
        await settle()

        let hosting = NSHostingView(rootView: HandoffRoot(
            controller: controller,
            localization: makeLocalization(),
            model: model,
            showsBatteryLevels: true
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 200)
        hosting.layoutSubtreeIfNeeded()
        await settle()
        XCTAssertTrue(controller.isBatteryLevelsRequested, "the summary needs the AirPods level")

        // Tap the Bluetooth row. The state change happens inside the view, which
        // is what makes SwiftUI run the outgoing summary's hook last.
        model.showsDetail = true
        await settle()

        XCTAssertTrue(
            controller.isBatteryLevelsRequested,
            "the outgoing summary must not release the read the detail page asked for"
        )
        XCTAssertEqual(
            controller.batteryLevels[BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F")]?.summary,
            "L 81% · R 79%",
            "the detail page must receive the levels it reads"
        )

        // Leaving the detail page is what releases the read.
        model.showsDetail = false
        await settle()
        XCTAssertFalse(controller.isBatteryLevelsRequested)
    }

    /// The regression test above only means something because the outgoing
    /// summary's hook really does run last. This pins that ordering, so it can
    /// never silently stop covering the bug.
    func testSwiftUIRunsTheOutgoingSummaryHookLast() async {
        let order = HandoffOrderRecorder()
        let model = HandoffModel()
        let hosting = NSHostingView(rootView: HandoffOrderProbe(order: order, model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
        hosting.layoutSubtreeIfNeeded()
        await settle()

        model.showsDetail = true
        await settle()

        let entries = order.entries
        guard let detailAppear = entries.firstIndex(of: "detail.appear"),
              let summaryDisappear = entries.firstIndex(of: "summary.disappear") else {
            XCTFail("expected both hooks to run, got \(entries)")
            return
        }
        XCTAssertLessThan(
            detailAppear, summaryDisappear,
            "the outgoing summary runs last, which is why it cannot own the flag"
        )
    }

    private func makeLocalization() -> Localization {
        let suite = "StatusTrioCoreTests.BluetoothHandoff.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(150))
    }
}

@MainActor
final class HandoffModel: ObservableObject {
    @Published var showsDetail = false
}

/// Holds both panels, so switching between them is one SwiftUI update rather
/// than a root-view replacement.
private struct HandoffRoot: View {
    let controller: BluetoothDeviceController
    let localization: Localization
    @ObservedObject var model: HandoffModel
    let showsBatteryLevels: Bool

    var body: some View {
        Group {
            if model.showsDetail {
                BluetoothDeviceListView(
                    controller: controller,
                    showsBatteryLevels: showsBatteryLevels,
                    onBack: {}, onRequestAuthorization: {}, onOpenBluetoothSettings: {}
                )
                .id("detail")
            } else {
                BluetoothStatusView(
                    controller: controller,
                    showsBatteryLevels: showsBatteryLevels,
                    onOpenDetails: {}, onRequestAuthorization: {}, onOpenBluetoothSettings: {}
                )
                .id("summary")
            }
        }
        .environmentObject(localization)
    }
}

@MainActor
private final class HandoffOrderRecorder {
    private(set) var entries: [String] = []
    func record(_ entry: String) { entries.append(entry) }
}

private struct HandoffOrderProbe: View {
    let order: HandoffOrderRecorder
    @ObservedObject var model: HandoffModel

    var body: some View {
        Group {
            if model.showsDetail {
                Text("detail")
                    .id("detail")
                    .onAppear { order.record("detail.appear") }
                    .onDisappear { order.record("detail.disappear") }
            } else {
                Text("summary")
                    .id("summary")
                    .onAppear { order.record("summary.appear") }
                    .onDisappear { order.record("summary.disappear") }
            }
        }
    }
}

private final class HandoffDeviceReader: BluetoothPairedDeviceReading {
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(.success([
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true)
        ]))
    }
}

@MainActor
private final class HandoffStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() { onStateChange?(.allowed, .poweredOn) }
    func stop() {}
}

private final class HandoffBatteryReader: BluetoothBatteryReading {
    private(set) var readCount = 0

    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]) -> Void) {
        readCount += 1
        completion([
            BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): BluetoothBatteryLevel(
                deviceAddress: "AC:90:85:C2:9C:1F", main: nil, left: 81, right: 79, caseLevel: nil)
        ])
    }
}
