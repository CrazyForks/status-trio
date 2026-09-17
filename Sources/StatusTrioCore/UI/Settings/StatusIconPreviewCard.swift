import AppKit
import SwiftUI

/// Live status icon preview shown at the top of the icon-related settings panes.
///
/// The card renders the real menu bar artwork through `StatusIconRenderer`, so
/// every option that feeds the icon — battery, connection, volume — updates it
/// immediately.
struct StatusIconPreviewCard: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var isDarkBackground: Bool
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                backdrop

                HStack(spacing: 14) {
                    leftContext

                    Spacer()

                    // Real-size live icon directly on menu bar (no artificial background box)
                    Image(nsImage: StatusIconRenderer.image(
                        menuBarStatus: MenuBarStatus(snapshot: statusStore.snapshot),
                        size: store.iconSize,
                        options: store.batteryIconOptions,
                        connectionOptions: store.connectionIconOptions,
                        volumeOptions: store.volumeIconOptions,
                        appearance: NSAppearance(named: isDarkBackground ? .darkAqua : .aqua)
                    ))
                    .accessibilityHidden(true)
                    .animation(.easeInOut(duration: 0.15), value: store.iconSize)
                    .animation(.easeInOut(duration: 0.15), value: store.batteryIconOptions)
                    .animation(.easeInOut(duration: 0.15), value: store.connectionIconOptions)
                    .animation(.easeInOut(duration: 0.15), value: store.volumeIconOptions)

                    rightContext

                    appearanceToggle
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 38)

            Text(localization.string(.settingsPreviewHint))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                isDarkBackground
                    ? LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.16, blue: 0.19),
                            Color(red: 0.10, green: 0.10, blue: 0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    : LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.96, blue: 0.98),
                            Color(red: 0.89, green: 0.89, blue: 0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isDarkBackground
                            ? Color.white.opacity(0.12)
                            : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    }

    // MARK: - Menu Bar Context

    private var leftContext: some View {
        HStack(spacing: 6) {
            Image(systemName: "apple.logo")
                .font(.system(size: 12, weight: .medium))
            Text(verbatim: "Finder")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(isDarkBackground ? Color.white.opacity(0.75) : Color.black.opacity(0.75))
    }

    private var rightContext: some View {
        HStack(spacing: 6) {
            Image(systemName: "switch.2")
                .font(.system(size: 10))
            Text(verbatim: "9:41")
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundStyle(isDarkBackground ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
    }

    private var appearanceToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isDarkBackground.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isDarkBackground ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 10))
                Text(localization.string(isDarkBackground ? .settingsPreviewDark : .settingsPreviewLight))
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(isDarkBackground ? Color.white.opacity(0.85) : Color.black.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isDarkBackground ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .help(localization.string(.settingsPreviewToggleHelp))
    }
}

/// Small Dock tile preview that mirrors the live Dock icon.
struct DockIconPreviewTile: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let image = DockIconRenderer.image(
                status: MenuBarStatus(snapshot: statusStore.snapshot),
                options: store.batteryIconOptions,
                connectionOptions: store.connectionIconOptions,
                volumeOptions: store.volumeIconOptions,
                backgroundStyle: resolvedBackgroundStyle
            ) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: size, height: size)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: store.batteryIconOptions)
        .animation(.easeInOut(duration: 0.15), value: store.connectionIconOptions)
        .animation(.easeInOut(duration: 0.15), value: store.volumeIconOptions)
        .accessibilityHidden(true)
    }

    private var resolvedBackgroundStyle: DockIconBackgroundStyle {
        DockIconBackgroundResolver.style(
            for: store.dockIconBackgroundPreference,
            theme: SystemIconAppearanceReader.current(),
            isDarkAppearance: NSApplication.shared.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        )
    }
}
