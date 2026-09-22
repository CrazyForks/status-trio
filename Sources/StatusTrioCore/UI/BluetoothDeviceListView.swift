import SwiftUI

/// The Bluetooth summary row. It reports live device state: a permission
/// request while the grant is undecided, then the connected device names, each
/// with the level the report carries for it.
struct BluetoothStatusView: View {
    @ObservedObject var controller: BluetoothDeviceController
    @EnvironmentObject private var localization: Localization
    let showsBatteryLevels: Bool
    var listOptions: BluetoothDeviceListOptions = .standard
    let onOpenDetails: () -> Void
    let onRequestAuthorization: () -> Void
    let onOpenBluetoothSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: onOpenDetails) {
                    HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
                        BluetoothIcon(size: BluetoothPanelMetrics.iconColumnWidth)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localization.string(.bluetoothTitle))
                                .font(.headline)
                            subtitle
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rowAccessibilityLabel)

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
                    options: listOptions
                )
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
            // keeps this correct whichever order SwiftUI runs it in against the
            // detail page's own claim.
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

struct BluetoothDeviceListView: View {
    @ObservedObject var controller: BluetoothDeviceController
    @EnvironmentObject private var localization: Localization
    let showsBatteryLevels: Bool
    let onBack: () -> Void
    let onRequestAuthorization: () -> Void
    let onOpenBluetoothSettings: () -> Void

    var body: some View {
        let groups = BluetoothDevicePresentation.grouped(controller.devices)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                NavigationBackRow(
                    accessibilityLabel: localization.string(.commonBack),
                    title: localization.string(.bluetoothTitle),
                    action: onBack
                )
                Button(action: { controller.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localization.string(.bluetoothRefresh))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if controller.availability == .available {
                        if !groups.connected.isEmpty {
                            section(localization.string(.bluetoothConnected), devices: groups.connected)
                        }
                        if !groups.disconnected.isEmpty {
                            section(localization.string(.bluetoothNotConnected), devices: groups.disconnected)
                        }
                    }
                    message
                    if controller.batteryLevelsReadFailed {
                        // One line for the whole list: a report that could not be
                        // read is not the same as "no device has a level".
                        Text(localization.string(.bluetoothBatteryUnavailable))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(localization.string(.bluetoothPairedDeviceLimit))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: 330)

            Divider()
            Button(localization.string(.bluetoothActionOpenSettings), action: onOpenBluetoothSettings)
                .buttonStyle(.plain)
        }
        .onAppear {
            updateBatteryLevelClaim()
            controller.activate()
            controller.holdVisibleSurface(Self.detailSurfaceToken)
        }
        .onChange(of: showsBatteryLevels) { _, _ in
            updateBatteryLevelClaim()
        }
        .onDisappear {
            controller.releaseVisibleSurface(Self.detailSurfaceToken)
            controller.releaseBatteryLevels(Self.detailBatteryLevelsToken)
        }
    }

    private static let detailBatteryLevelsToken = "bluetooth.detail"
    private static let detailSurfaceToken = "bluetooth.detail.surface"

    /// The detail page is the only surface that reports levels for every
    /// device, so it claims the read directly from the setting.
    private func updateBatteryLevelClaim() {
        if showsBatteryLevels {
            controller.requestBatteryLevels(Self.detailBatteryLevelsToken)
        } else {
            controller.releaseBatteryLevels(Self.detailBatteryLevelsToken)
        }
    }

    private func section(_ title: String, devices: [BluetoothDevice]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(devices) { device in
                BluetoothDeviceRow(device: device, batteryLevels: controller.batteryLevels)
            }
        }
    }

    @ViewBuilder
    private var message: some View {
        switch controller.availability {
        case .idle, .initializing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(localization.string(.bluetoothInitializing))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .authorizationNotDetermined:
            Button(
                localization.string(.bluetoothActionRequestAuthorization),
                action: onRequestAuthorization
            )
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        case .authorizationDenied:
            Button(localization.string(.bluetoothAuthorizationDenied), action: onOpenBluetoothSettings)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .authorizationRestricted:
            Text(localization.string(.bluetoothAuthorizationRestricted))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .available where controller.devices.isEmpty:
            Text(localization.string(.bluetoothNoDevices))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .poweredOff:
            Text(localization.string(.bluetoothOff))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unavailable:
            Text(localization.string(.bluetoothUnavailable))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Text(localization.string(.bluetoothReadFailed))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .available:
            EmptyView()
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
