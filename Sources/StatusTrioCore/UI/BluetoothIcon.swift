import AppKit
import SwiftUI

struct BluetoothIcon: View {
    static var templateImage: NSImage? {
        NSImage(named: NSImage.bluetoothTemplateName)
    }

    let size: CGFloat

    init(size: CGFloat = 24) {
        self.size = size
    }

    var body: some View {
        Image(nsImage: Self.templateImage ?? Self.fallbackImage)
            .renderingMode(.template)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private static var fallbackImage: NSImage {
        NSImage(
            systemSymbolName: "antenna.radiowaves.left.and.right",
            accessibilityDescription: nil
        ) ?? NSImage()
    }
}
