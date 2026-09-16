import AppKit
import SwiftUI

/// Draws the icon for an output device: the image the driver ships when it has
/// one, otherwise the SF Symbol for the device class. The driver image is drawn
/// as a template so it takes the same tint as the symbol it replaces.
struct AudioOutputDeviceIconView: View {
    let device: AudioOutputDevice
    var glyphSize: CGFloat = 13

    var body: some View {
        switch AudioOutputDeviceIcon.source(for: device) {
        case .image(let url):
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: glyphSize, height: glyphSize)
            } else {
                symbol(AudioOutputDeviceIcon.symbolName(for: device))
            }
        case .symbol(let name):
            symbol(name)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: glyphSize, weight: .semibold))
    }
}
