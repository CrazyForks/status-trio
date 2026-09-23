import AppKit
import Foundation
import Testing
@testable import StatusTrioCore

/// The glyph table, and the availability rule that keeps a symbol Apple added
/// in a later release from rendering as a blank row.
struct BluetoothDeviceRowIconTests {
    @Test(arguments: [
        (BluetoothDeviceKind.computer(.laptop), "laptopcomputer"),
        (.computer(.desktop), "desktopcomputer"),
        (.computer(.unclassified), "desktopcomputer"),
        (.mobile(.phone), "smartphone"),
        (.mobile(.tablet), "ipad"),
        (.mobile(.watch), "watch.analog"),
        (.peripheral(.keyboard), "keyboard"),
        (.peripheral(.mouse), "computermouse"),
        (.peripheral(.trackpad), "rectangle.and.hand.point.up.left"),
        (.peripheral(.gamepad), "gamecontroller"),
        (.imaging(.printer), "printer"),
        (.imaging(.scanner), "scanner"),
        (.imaging(.camera), "camera"),
        (.imaging(.display), "tv"),
        (.toy, "gamecontroller"),
        (.health, "heart.text.square"),
    ])
    func everyClassLeadsWithItsOwnGlyph(kind: BluetoothDeviceKind, expected: String) {
        #expect(BluetoothDeviceRowIcon.candidateSymbols(for: kind).first == expected)
    }

    /// Every class with no glyph of its own draws the same radio, not a
    /// question mark: an unreported class is not a fault.
    @Test func classesWithNoGlyphDrawTheGenericRadio() {
        #expect(BluetoothDeviceRowIcon.candidateSymbols(for: .unknown) == [BluetoothDeviceRowIcon.genericSymbol])
        #expect(BluetoothDeviceRowIcon.candidateSymbols(for: .peripheral(.unclassified)) == [BluetoothDeviceRowIcon.genericSymbol])
        #expect(BluetoothDeviceRowIcon.candidateSymbols(for: .imaging(.unclassified)) == [BluetoothDeviceRowIcon.genericSymbol])
        #expect(BluetoothDeviceRowIcon.symbolName(for: .unknown) == BluetoothDeviceRowIcon.genericSymbol)
    }

    /// The rule the audio icon table already follows: the running system
    /// resolves the list, so the last entry is what a macOS too old to ship any
    /// of the others falls back to and must never be blank.
    @Test func theLastCandidateIsTheOneEverySupportedMacHas() {
        let kinds: [BluetoothDeviceKind] = [
            .computer(.laptop), .computer(.desktop), .computer(.unclassified),
            .mobile(.phone), .mobile(.tablet), .mobile(.watch), .audio,
            .peripheral(.keyboard), .peripheral(.mouse), .peripheral(.trackpad),
            .peripheral(.gamepad), .peripheral(.unclassified),
            .imaging(.printer), .imaging(.scanner), .imaging(.camera),
            .imaging(.display), .imaging(.unclassified),
            .toy, .health, .unknown,
        ]

        for kind in kinds {
            guard let last = BluetoothDeviceRowIcon.candidateSymbols(for: kind).last else {
                Issue.record("\(kind) has no glyph candidates at all")
                continue
            }
            #expect(
                NSImage(systemSymbolName: last, accessibilityDescription: nil) != nil,
                "the fallback glyph \(last) for \(kind) does not exist on this macOS"
            )
        }
    }

    /// Whatever the running system ships, the row never resolves to a name it
    /// cannot draw.
    @Test func everyClassResolvesToASymbolThisMachineShips() {
        let kinds: [BluetoothDeviceKind] = [
            .computer(.laptop), .computer(.desktop), .computer(.unclassified),
            .mobile(.phone), .mobile(.tablet), .mobile(.watch), .audio,
            .peripheral(.keyboard), .peripheral(.mouse), .peripheral(.trackpad),
            .peripheral(.gamepad), .peripheral(.unclassified),
            .imaging(.printer), .imaging(.scanner), .imaging(.camera),
            .imaging(.display), .imaging(.unclassified),
            .toy, .health, .unknown,
        ]

        for kind in kinds {
            let name = BluetoothDeviceRowIcon.symbolName(for: kind)
            #expect(
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "\(kind) resolved to \(name), which this macOS does not ship"
            )
        }
    }

    /// An audio row still resolves through the output list's table, so an
    /// AirPods keeps the glyph macOS declares for its product ID.
    @Test func audioRowsResolveThroughTheOutputListTable() {
        let airPods = BluetoothDevice(
            id: "AC:90:85:C2:9C:1F",
            name: "机灵的耳机",
            kind: .audio,
            isConnected: true,
            airPodsModel: .airPods
        )

        #expect(BluetoothDeviceRowIcon.symbolName(for: airPods) == "airpods")
        // The class on its own has no device to resolve by, so it draws the
        // generic headphone glyph rather than nothing.
        #expect(BluetoothDeviceRowIcon.symbolName(for: .audio) != "")
    }
}
