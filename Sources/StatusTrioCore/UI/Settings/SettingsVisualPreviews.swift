import AppKit
import SwiftUI

// MARK: - Volume Indicator Preview

struct VolumeIndicatorPreview: View {
    let style: VolumeDisplayStyle
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.65)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Image(nsImage: StatusIconRenderer.image(
                menuBarStatus: previewStatus,
                size: 28,
                options: store.batteryIconOptions,
                connectionOptions: store.connectionIconOptions,
                volumeOptions: VolumeIconOptions(
                    displayStyle: style,
                    ringStrokeScale: store.ringStrokeStyle.scale
                ),
                appearance: NSApp.effectiveAppearance
            ))
            .accessibilityHidden(true)
        }
    }

    private var previewStatus: MenuBarStatus {
        let base = MenuBarStatus(snapshot: statusStore.snapshot)
        let volume = MenuBarVolumeStatus(
            scalar: (base.volume.scalar ?? 0) > 0 && !base.volume.isMuted ? base.volume.scalar : 0.75,
            isMuted: false,
            deviceName: base.volume.deviceName
        )
        return MenuBarStatus(
            battery: base.battery,
            wifi: base.wifi,
            connection: base.connection,
            volume: volume
        )
    }
}

// MARK: - App Icon Placement Preview

struct AppIconPlacementPreview: View {
    let placement: AppIconPlacement

    var body: some View {
        ZStack {
            // Mini screen body
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                // Mini Menu Bar at top
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.primary.opacity(0.25))
                        .frame(width: 2.5, height: 2.5)
                        .padding(.leading, 3.5)
                    Spacer()
                    if placement == .menuBar || placement == .both {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.accentColor)
                            .frame(width: 14, height: 3.5)
                            .padding(.trailing, 3.5)
                    } else {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.primary.opacity(0.18))
                            .frame(width: 9, height: 2.5)
                            .padding(.trailing, 3.5)
                    }
                }
                .frame(height: 7)
                .background(Color.primary.opacity(placement == .menuBar || placement == .both ? 0.12 : 0.05))

                Spacer()

                // Mini Dock at bottom
                if placement == .dock || placement == .both {
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.primary.opacity(0.2))
                            .frame(width: 4, height: 4)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.primary.opacity(0.2))
                            .frame(width: 4, height: 4)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                    )
                    .padding(.bottom, 3)
                } else {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 20, height: 2.5)
                        .padding(.bottom, 3)
                }
            }
        }
    }
}

// MARK: - Dock Background Preview

struct DockBackgroundPreview: View {
    let preference: DockIconBackgroundPreference
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.65)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            switch preference {
            case .system:
                // Split light/dark macOS Dock tile
                ZStack {
                    DockIconPreviewTile(
                        store: store,
                        statusStore: statusStore,
                        size: 30,
                        overrideStyle: .light
                    )

                    DockIconPreviewTile(
                        store: store,
                        statusStore: statusStore,
                        size: 30,
                        overrideStyle: .dark
                    )
                    .clipShape(HalfSplitShape(isRight: true))

                    // Hairline divider down the middle
                    Rectangle()
                        .fill(Color.primary.opacity(0.16))
                        .frame(width: 0.5, height: 28)
                }
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)

            case .dark:
                DockIconPreviewTile(
                    store: store,
                    statusStore: statusStore,
                    size: 30,
                    overrideStyle: .dark
                )
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)

            case .light:
                DockIconPreviewTile(
                    store: store,
                    statusStore: statusStore,
                    size: 30,
                    overrideStyle: .light
                )
                .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
            }
        }
    }
}

private struct HalfSplitShape: Shape {
    let isRight: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isRight {
            path.addRect(CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height))
        } else {
            path.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height))
        }
        return path
    }
}

// MARK: - Ring Stroke Style Preview

struct RingStrokeStylePreview: View {
    let style: RingStrokeStyle
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.65)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Image(nsImage: StatusIconRenderer.image(
                menuBarStatus: previewStatus,
                size: 28,
                options: BatteryIconOptions(
                    showsPercentage: store.showsBatteryPercentage,
                    showsChargingIndicator: store.showsChargingIndicator,
                    usesStatusColors: store.usesBatteryStatusColors,
                    criticalThreshold: Int(store.batteryCriticalThreshold.rounded()),
                    showsPercentageWhenConnected: store.showsPercentageWhenConnected,
                    textScale: store.batterySymbolScale * BatteryIconOptions.defaultTextScale,
                    ringStrokeScale: style.scale
                ),
                connectionOptions: store.connectionIconOptions,
                volumeOptions: VolumeIconOptions(
                    displayStyle: store.volumeDisplayStyle,
                    ringStrokeScale: style.scale
                ),
                appearance: NSApp.effectiveAppearance
            ))
            .accessibilityHidden(true)
        }
    }

    private var previewStatus: MenuBarStatus {
        let base = MenuBarStatus(snapshot: statusStore.snapshot)
        let volume = MenuBarVolumeStatus(
            scalar: (base.volume.scalar ?? 0) > 0 && !base.volume.isMuted ? base.volume.scalar : 0.75,
            isMuted: false,
            deviceName: base.volume.deviceName
        )
        return MenuBarStatus(
            battery: base.battery,
            wifi: base.wifi,
            connection: base.connection,
            volume: volume
        )
    }
}

