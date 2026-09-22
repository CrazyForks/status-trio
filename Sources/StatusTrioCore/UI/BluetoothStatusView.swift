import SwiftUI

/// The Bluetooth summary row. It reports live device state — a permission
/// request while the grant is undecided, then the states only the row can
/// explain — and lists the paired devices under it. A connected device is marked
/// the way the volume output list marks the device in use, and a device the
/// report carries a level for shows it.
///
/// The row is no longer a way into a detail page: the list below it already
/// shows every paired device, with an expansion control when they do not all
/// fit, so a second page only repeated it. What that page offered besides is
/// here instead: the refresh button beside the gear, and the one-line report of
/// a level read that failed.
struct BluetoothStatusView: View {
    @ObservedObject var controller: BluetoothDeviceController
    @EnvironmentObject private var localization: Localization
    let showsBatteryLevels: Bool
    var listOptions: BluetoothDeviceListOptions = .standard
    let onRequestAuthorization: () -> Void
    let onOpenBluetoothSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
                    BluetoothIcon(size: BluetoothPanelMetrics.iconColumnWidth)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.string(.bluetoothTitle))
                            .font(.headline)
                        subtitle
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rowAccessibilityLabel)

                Button(action: { controller.refresh() }) {
                    // Trailing-aligned inside the button's own box: the other
                    // rows end on their disclosure chevron itself, so its right
                    // edge is what sits ten points before the gear. A glyph
                    // centred in this 24-point box would land about seven points
                    // to the left of that column. The whole box stays clickable.
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 24, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(localization.string(.bluetoothRefresh))
                .accessibilityLabel(localization.string(.bluetoothRefresh))

                Button(localization.string(.bluetoothActionOpenSettings), systemImage: "gearshape", action: onOpenBluetoothSettings)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(localization.string(.bluetoothActionOpenSettings))
                    .frame(width: 24, height: 24)
            }

            if showsDeviceList {
                BluetoothDeviceList(
                    devices: controller.devices,
                    batteryLevels: controller.batteryLevels,
                    actionStates: controller.deviceActionStates,
                    confirmingAddress: controller.pendingDisconnectConfirmation,
                    options: listOptions,
                    onPerformAction: { controller.performDeviceAction(for: $0) },
                    onRequestDisconnect: { controller.requestDisconnectConfirmation(for: $0) },
                    onCancelDisconnect: { controller.cancelDisconnectConfirmation() }
                )

                if controller.batteryLevelsReadFailed {
                    // The list is where the levels are, so this is where a report
                    // that could not be read is reported: one line for the whole
                    // list, never a placeholder on every row.
                    Text(localization.string(.bluetoothBatteryUnavailable))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            controller.holdVisibleSurface(Self.summarySurfaceToken)
        }
        .task(id: batteryReadTaskID) {
            // Reading levels launches system_profiler, so the claim is held only
            // while the summary actually wants them. The row stays on screen
            // while the setting changes, so the release has to happen here and
            // not only in `onDisappear`: otherwise switching the setting off
            // leaves the read running and the level it published on screen until
            // the row disappears and comes back. A claim rather than a toggle
            // keeps this correct whichever order SwiftUI runs it in.
            guard showsBatteryLevels, summaryPresentation.hasConnectedDevices else {
                controller.releaseBatteryLevels(Self.summaryBatteryLevelsToken)
                return
            }
            controller.requestBatteryLevels(Self.summaryBatteryLevelsToken)
        }
        .onDisappear {
            controller.releaseVisibleSurface(Self.summarySurfaceToken)
            controller.releaseBatteryLevels(Self.summaryBatteryLevelsToken)
        }
    }

    private static let summaryBatteryLevelsToken = "bluetooth.summary"
    private static let summarySurfaceToken = "bluetooth.summary.surface"

    private var showsDeviceList: Bool {
        BluetoothPanelListVisibility.showsList(
            availability: controller.availability,
            devices: controller.devices,
            options: listOptions
        )
    }

    private var hidesSubtitle: Bool {
        BluetoothPanelListVisibility.hidesRowSubtitle(
            availability: controller.availability,
            devices: controller.devices,
            options: listOptions
        )
    }

    /// The task re-runs when the level setting or one of the device names
    /// changes. The name also covers an AirPods swapping to another device at
    /// the same address.
    private var batteryReadTaskID: String {
        let names = BluetoothDevicePresentation.grouped(controller.devices).connected
            .map(\.name)
            .joined(separator: "、")
        return "\(showsBatteryLevels)-\(names)"
    }

    private var summaryPresentation: BluetoothSummary {
        BluetoothSummary.presentation(
            availability: controller.availability,
            devices: controller.devices,
            batteryLevels: controller.batteryLevels
        )
    }

    /// The list carries the connected names, so the label that would repeat them
    /// is dropped for the same reason the visible subtitle is: every row below is
    /// already its own combined accessibility element, and announcing the names
    /// twice makes VoiceOver read each device twice. The decision stays inside
    /// the one tested rule.
    private var rowAccessibilityLabel: String {
        guard !hidesSubtitle else { return localization.string(.bluetoothTitle) }
        return "\(localization.string(.bluetoothTitle)), \(accessibilitySummary)"
    }

    private var accessibilitySummary: String {
        switch summaryPresentation {
        case .requestAuthorization:
            return localization.string(.bluetoothAuthorizationNotDetermined)
        default:
            return summaryText
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if case .requestAuthorization = summaryPresentation {
            Button(
                localization.string(.bluetoothActionRequestAuthorization),
                action: onRequestAuthorization
            )
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else if hidesSubtitle {
            EmptyView()
        } else {
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var summaryText: String {
        switch summaryPresentation {
        case .requestAuthorization:
            return localization.string(.bluetoothAuthorizationNotDetermined)
        case .initializing:
            return localization.string(.bluetoothInitializing)
        case .authorizationDenied:
            return localization.string(.bluetoothAuthorizationDenied)
        case .authorizationRestricted:
            return localization.string(.bluetoothAuthorizationRestricted)
        case .poweredOff:
            return localization.string(.bluetoothOff)
        case .unavailable:
            return localization.string(.bluetoothUnavailable)
        case .readFailed:
            return localization.string(.bluetoothReadFailed)
        case .noConnectedDevices:
            return localization.string(.bluetoothNoConnectedDevices)
        case .devices(let names):
            return names
        }
    }
}

/// The glyph each paired-device row draws.
///
/// The audio row resolves through the same mapping as the popup's output list,
/// so an AirPods draws the AirPods glyph macOS declares for its product ID
/// instead of the generic headphone one, and the two surfaces cannot drift.
enum BluetoothDeviceRowIcon {
    static func symbolName(for device: BluetoothDevice) -> String {
        switch device.kind {
        case .computer:
            "laptopcomputer"
        case .phone:
            "iphone"
        case .audio:
            AudioOutputDeviceIcon.symbolName(
                for: AudioDeviceIdentity(bluetooth: device.name, model: device.airPodsModel)
            )
        case .peripheral:
            "computermouse"
        case .unknown:
            "questionmark.circle"
        }
    }
}
