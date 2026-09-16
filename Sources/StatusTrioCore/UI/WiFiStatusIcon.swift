import SwiftUI

struct WiFiStatusIcon: View {
    @EnvironmentObject private var localization: Localization
    let wifi: WiFiStatus

    var body: some View {
        Image(nsImage: StatusIconRenderer.wifiImage(wifi: wifi, size: 16))
            .renderingMode(.template)
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .accessibilityLabel(localization.format(.commonLabelValue, localization.string(.networkTitle), StatusPresentation.wifiValue(wifi, localization: localization)))
    }
}
