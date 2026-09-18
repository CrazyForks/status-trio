import Foundation
@testable import StatusTrioCore

/// Example values shared by the generated sheets, so the menu bar sheet and the
/// Dock sheet document the same hardware.
enum SheetFixtures {
    static let bluetoothDeviceName = "AirPods Pro"

    /// `StatusIconRenderer` and `DockIconRenderer` resolve the glyph from the
    /// device, so every sheet shows the symbol the app draws for this output.
    static var bluetoothDevice: AudioOutputDevice {
        AudioOutputDevice(
            id: 42,
            name: bluetoothDeviceName,
            uid: "sheet-bluetooth-output",
            isCurrent: true,
            volume: 0.6,
            transport: .bluetooth
        )
    }
}
