import CoreAudio
import Foundation
import XCTest

@testable import StatusTrioCore

/// The synthetic rows the interface preview injects below the real device list.
///
/// Two properties matter and are easy to regress: a synthetic row must publish its
/// three capsules purely from its preview-prefixed address — the `isAirPods` name
/// heuristic that gates the *real* surface must not silently hide a row the
/// operator renamed — and the language override must resolve to the chosen
/// language without touching the app's own language setting. These live here so
/// they are read next to `BluetoothListeningModePreviewTests`, which covers the
/// interaction; this file covers the row-injection and localization plumbing the
/// preview block sits on.
@MainActor
final class BluetoothListeningModeSyntheticPreviewTests: XCTestCase {
    private func syntheticID(_ index: Int) -> String {
        "\(BluetoothListeningModeController.previewAddressPrefix)\(index)"
    }

    private func key(for id: String) -> String {
        BluetoothBatteryReader.normalizedAddress(id)
    }

    private func makePreviewController() -> BluetoothListeningModeController {
        let hal = BluetoothListeningModeHAL(
            backend: FakeListeningModeBackend(),
            sleeper: ImmediateListeningModeSleeper(),
            retryAttempts: 1,
            retryDelay: .milliseconds(1)
        )
        let controller = BluetoothListeningModeController(
            hal: hal,
            endpointProvider: EmptyListeningModeEndpointProvider(),
            failureClearDelay: .milliseconds(20),
            previewSettleDelay: .milliseconds(10)
        )
        controller.previewMode = true
        return controller
    }

    // MARK: - Name-independent eligibility

    /// A synthetic row whose display name does not contain "AirPods" still gets
    /// the three capsules, because eligibility on the preview path is the address
    /// prefix, not the `isAirPods` name heuristic. This is what lets the operator
    /// type any name — a long truncation stress-test, a foreign word — and still
    /// see the composed layout.
    func testSyntheticRowPublishesThreeCapsulesRegardlessOfName() {
        let controller = makePreviewController()
        let device = BluetoothDevice(
            id: syntheticID(1),
            name: "Long-Name-Test That Would Never Match The AirPods Heuristic",
            kind: .audio,
            isConnected: true
        )
        controller.refresh(devices: [device])

        let presentation = controller.presentations[key(for: syntheticID(1))]
        XCTAssertEqual(presentation?.availableModes, BluetoothListeningModeController.previewAvailableModes)
        XCTAssertEqual(presentation?.availableModes.count, 3)
        XCTAssertEqual(presentation?.isControllable, true)
    }

    /// The prefix branch is the only new door. A plain, preview-unprefixed device
    /// that is not AirPods is still refused on the preview path — preview must not
    /// turn into "show capsules on everything".
    func testNonAirPodsWithoutPrefixIsStillIgnored() {
        let controller = makePreviewController()
        let device = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:00",
            name: "Plain Buds",
            kind: .audio,
            isConnected: true
        )
        controller.refresh(devices: [device])
        XCTAssertTrue(controller.presentations.isEmpty, "only the prefix or a real AirPods name qualifies")
    }

    /// Every synthetic index resolves to its own normalized address, so a
    /// multi-row preview does not collapse several rows onto one presentation.
    func testEachSyntheticIndexGetsItsOwnAddress() {
        let controller = makePreviewController()
        let devices = (1...3).map {
            BluetoothDevice(id: syntheticID($0), name: "AirPods Pro", kind: .audio, isConnected: true)
        }
        controller.refresh(devices: devices)

        XCTAssertEqual(controller.presentations.count, 3)
        for index in 1...3 {
            XCTAssertNotNil(controller.presentations[key(for: syntheticID(index))])
        }
    }

    // MARK: - Language override

    /// The override resolves to the requested language and returns that
    /// language's strings, proving the preview block can render in a tongue other
    /// than the panel's.
    func testPreviewLocalizationResolvesToRequestedLanguage() {
        guard let german = PreviewLocalization.forCode("de") else {
            return XCTFail("expected a German preview localization")
        }
        XCTAssertEqual(german.resolvedLanguage, .german)
        XCTAssertNotEqual(german.resolvedLanguage, .english)
    }

    /// The empty code means "no override", and an unknown code is refused rather
    /// than guessed at — both return nil so the caller falls back to the real
    /// localization.
    func testPreviewLocalizationReturnsNilForEmptyAndUnknown() {
        XCTAssertNil(PreviewLocalization.forCode(""))
        XCTAssertNil(PreviewLocalization.forCode("zz"))
    }

    /// The mode-name string differs between the override and English, and the same
    /// code always hands back the identical cached instance (so a refresh does not
    /// rebuild a Localization, and its locale observer does not multiply).
    func testPreviewLocalizationIsCachedAndLocalizesModeName() {
        let first = PreviewLocalization.forCode("de")
        let second = PreviewLocalization.forCode("de")
        XCTAssertTrue(first === second, "same code must reuse one instance")

        let english = Localization(defaults: UserDefaults(suiteName: "StatusTrio.Test.English")!, preferredLanguages: ["en"])
        english.setPreference(.language(.english))
        let german = PreviewLocalization.forCode("de")!
        XCTAssertNotEqual(
            german.string(.bluetoothListeningModeNoiseCancellation),
            english.string(.bluetoothListeningModeNoiseCancellation),
            "the override should surface a genuinely different translation"
        )
    }

    /// Building an override must not write the app's real language preference. The
    /// preview is display-only; if it shared `.standard` the override would leak
    /// into the user's own setting.
    func testPreviewLocalizationDoesNotTouchTheRealLanguagePreference() {
        let standard = UserDefaults.standard
        let before = standard.string(forKey: Localization.defaultsKey)
        defer {
            // Restore whatever the host process had, so the probe is inert.
            if let before {
                standard.set(before, forKey: Localization.defaultsKey)
            } else {
                standard.removeObject(forKey: Localization.defaultsKey)
            }
        }

        _ = PreviewLocalization.forCode("ja")
        XCTAssertEqual(
            standard.string(forKey: Localization.defaultsKey),
            before,
            "a preview override must never write the standard appLanguage key"
        )
    }
}
