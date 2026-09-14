import AppKit
import SwiftUI

struct IconSizePreview: View {
    let size: Double
    let options: BatteryIconOptions

    var body: some View {
        Image(nsImage: StatusIconRenderer.image(
            snapshot: .placeholder,
            size: size,
            options: options
        ))
        .frame(width: CGFloat(SettingsStore.iconSizeRange.upperBound))
        .accessibilityHidden(true)
    }
}
