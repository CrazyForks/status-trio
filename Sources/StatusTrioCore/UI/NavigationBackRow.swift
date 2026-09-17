import SwiftUI

struct NavigationBackRow: View {
    let accessibilityLabel: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.backward")
                    .frame(width: 32, height: 32)
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
