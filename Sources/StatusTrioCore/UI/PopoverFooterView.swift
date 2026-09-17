import SwiftUI

struct PopoverFooterView: View {
    @EnvironmentObject private var localization: Localization
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: openSettings) {
                Label(localization.string(.menuSettings), systemImage: "gearshape")
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)

            Menu {
                Button(localization.string(.menuQuit), action: quit)
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Label(localization.string(.menuMore), systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(localization.string(.menuMore))
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
