import SwiftUI

/// Provisional power info bar under the panel's battery module. It draws one
/// card per rail (input, battery, system); each number is its own reading and
/// the cards are never summed into a whole-machine total.
struct PowerInfoBarView: View {
    @EnvironmentObject private var localization: Localization
    let state: PowerInfoBarState

    var body: some View {
        HStack(spacing: 8) {
            ForEach(state.items) { item in
                card(item)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func card(_ item: PowerInfoBarItem) -> some View {
        let tint = Self.tint(for: item.kind)
        return HStack(spacing: 9) {
            Image(systemName: Self.symbolName(for: item.kind))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(localization.string(item.title))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(item.value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private static func symbolName(for kind: PowerInfoBarKind) -> String {
        switch kind {
        case .input: return "powerplug.fill"
        case .battery: return "battery.100.bolt"
        case .system: return "laptopcomputer"
        }
    }

    private static func tint(for kind: PowerInfoBarKind) -> Color {
        switch kind {
        case .input: return .primary
        case .battery: return .green
        case .system: return .blue
        }
    }
}
