import AppKit

/// The glyph each paired-device row draws.
///
/// The audio row resolves through the same mapping as the popup's output list,
/// so an AirPods draws the AirPods glyph macOS declares for its product ID
/// instead of the generic headphone one, and the two surfaces cannot drift.
///
/// Every other class has a list of candidates rather than one name, because a
/// symbol Apple adds in a later release must not render as a blank row on the
/// oldest macOS the app supports. The list is ordered most faithful first and
/// its last entry is old enough to ship everywhere. This is the same rule
/// `AudioOutputDeviceIcon.symbolCandidates` follows.
enum BluetoothDeviceRowIcon {
    static func symbolName(for device: BluetoothDevice) -> String {
        switch device.kind {
        case .audio:
            AudioOutputDeviceIcon.symbolName(
                for: AudioDeviceIdentity(bluetooth: device.name, model: device.airPodsModel)
            )
        default:
            symbolName(for: device.kind)
        }
    }

    static func symbolName(for kind: BluetoothDeviceKind) -> String {
        let candidates = candidateSymbols(for: kind)
        return candidates.first {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        } ?? candidates.last ?? genericSymbol
    }

    /// What a device whose class the report did not describe draws.
    ///
    /// A radio glyph, not `questionmark.circle`. macOS reserves the question
    /// mark for a page the user has to fix, and an unreported class is not a
    /// fault — it is the ordinary state of a manufacturer that never filled the
    /// field in. Every comparable app draws a generic wireless glyph here, and
    /// the glyph now also covers the devices the previous table sent to the
    /// question mark by classifying nothing.
    static let genericSymbol = "dot.radiowaves.left.and.right"

    /// Kept apart from the availability check so the order is unit-tested on
    /// the strings, rather than on whichever symbols the machine running the
    /// tests happens to ship.
    static func candidateSymbols(for kind: BluetoothDeviceKind) -> [String] {
        switch kind {
        case .computer(.laptop):
            ["laptopcomputer"]
        // A report that names no form leaves the two equally likely, so the
        // generic machine glyph is the honest one; a report that says `Laptop`
        // or `Desktop` is drawn exactly.
        case .computer(.desktop), .computer(.unclassified):
            ["desktopcomputer"]
        case .mobile(.phone):
            ["smartphone", "iphone"]
        case .mobile(.tablet):
            ["ipad"]
        // A wristwatch class covers every brand, so the generic watch leads and
        // the Apple one is only the fallback.
        case .mobile(.watch):
            ["watch.analog", "applewatch"]
        // Reached only when the row draws this class without a device to
        // resolve it by; `symbolName(for:)` sends every real audio device
        // through `AudioOutputDeviceIcon` first.
        case .audio:
            ["headphones"]
        case .peripheral(.keyboard):
            ["keyboard"]
        case .peripheral(.mouse):
            ["computermouse"]
        case .peripheral(.trackpad):
            ["rectangle.and.hand.point.up.left"]
        case .peripheral(.gamepad):
            ["gamecontroller"]
        case .peripheral(.unclassified):
            [genericSymbol]
        case .imaging(.printer):
            ["printer"]
        case .imaging(.scanner):
            ["scanner"]
        case .imaging(.camera):
            ["camera"]
        case .imaging(.display):
            ["tv"]
        case .imaging(.unclassified):
            [genericSymbol]
        case .toy:
            ["gamecontroller"]
        case .health:
            ["heart.text.square", "waveform.path.ecg"]
        case .unknown:
            [genericSymbol]
        }
    }
}
