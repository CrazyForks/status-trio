import SwiftUI

struct PopoverFooterView: View {
    @EnvironmentObject private var localization: Localization
    let openSettings: () -> Void
    let quit: () -> Void

    private var settingsTitle: String {
        let title = localization.string(.menuSettings)
        guard let codename = AppMetadata.developmentCodename else {
            return title
        }
        return "\(title) · \(localization.format(.menuSettingsDevelopment, codename))"
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: openSettings) {
                Label(settingsTitle, systemImage: "gearshape")
                    .lineLimit(1)
                    .truncationMode(.tail)
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
