import CoreGraphics

/// Layout the status panel's Bluetooth section shares between its own row and
/// the device rows underneath it. Both reserve the same icon column, so the
/// device glyphs and their names line up under the section's icon — the same
/// 24-point column the volume output list and its rows use.
enum BluetoothPanelMetrics {
    /// The width the section icon and every device glyph are centred in.
    static let iconColumnWidth: CGFloat = 24

    /// The gap between that column and the text that follows it.
    static let iconTextSpacing: CGFloat = 10
}
