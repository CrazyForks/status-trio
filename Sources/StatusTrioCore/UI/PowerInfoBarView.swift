import SwiftUI

/// Provisional single-line power info bar under the panel's battery module.
/// Each item is its own rail; the bar never presents their sum as the machine
/// total.
struct PowerInfoBarView: View {
    @EnvironmentObject private var localization: Localization
    let state: PowerInfoBarState

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 3) {
                    Text(localization.string(item.title))
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }
}
