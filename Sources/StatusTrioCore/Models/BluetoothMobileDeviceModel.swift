import Foundation

/// The class an iOS device's own model string declares.
///
/// A paired-device report describes an iPhone or an iPad by its Continuity
/// advertisement, which carries no class at all: `device_minorType` is absent,
/// so the row has nothing to resolve a glyph from and falls back to the generic
/// radio. The BLE read closes that gap, because the Device Information Service
/// (`180A`) answers with the model — `iPhone14,3`, `iPad11,1`, `Watch6,1` — and
/// that string names the family the report left out.
///
/// The match is on the family prefix rather than on the whole string: the
/// number after it is the hardware revision, which changes every release and
/// maps to no glyph of its own, so only the prefix is read. That is the same
/// reasoning AirBattery's device-type derivation follows.
enum BluetoothMobileDeviceModel {
    /// The class a model string names, or `nil` when it names no family the app
    /// draws.
    ///
    /// An iPod is deliberately absent. It is a media player rather than a phone,
    /// and the app's mobile forms are only phone, tablet and watch, so mapping it
    /// to a phone would draw the wrong glyph for it. `nil` leaves the device with
    /// whatever class it already had.
    static func kind(forModel model: String?) -> BluetoothDeviceKind? {
        guard let model else { return nil }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let families: [(prefix: String, kind: BluetoothDeviceKind)] = [
            ("iPhone", .mobile(.phone)),
            ("iPad", .mobile(.tablet)),
            ("Watch", .mobile(.watch))
        ]
        return families.first {
            trimmed.range(of: $0.prefix, options: [.anchored, .caseInsensitive]) != nil
        }?.kind
    }
}
