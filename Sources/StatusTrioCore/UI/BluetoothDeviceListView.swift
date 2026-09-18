import SwiftUI

/// The Bluetooth summary row. It reports live device state: a permission
/// request while the grant is undecided, then the connected device names, with
/// battery levels only for connected AirPods.
struct BluetoothStatusView: View {
    @ObservedObject var controller: BluetoothDeviceController
    @EnvironmentObject private var localization: Localization
    let showsBatteryLevels: Bool
    let onOpenDetails: () -> Void
    let onRequestAuthorization: () -> Void
    let onOpenBluetoothSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenDetails) {
                HStack(spacing: 10) {
                    BluetoothIcon(size: 24)
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
            .accessibilityLabel("\(localization.string(.bluetoothTitle)), \(accessibilitySummary)")

            Button(localization.string(.bluetoothActionOpenSettings), systemImage: "gearshape", action: onOpenBluetoothSettings)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(localization.string(.bluetoothActionOpenSettings))
                .frame(width: 24, height: 24)
        }
        .task(id: batteryReadTaskID) {
            // Reading levels launches system_profiler, so it runs only for the
            // AirPods the summary actually reports.
            controller.setBatteryLevelsEnabled(
                showsBatteryLevels && summaryPresentation.hasConnectedAirPods
            )
        }
        .onDisappear {
            controller.setBatteryLevelsEnabled(false)
        }
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
        case .devices(let names, _):
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
            controller.setBatteryLevelsEnabled(showsBatteryLevels)
            controller.activate()
        }
        .onChange(of: showsBatteryLevels) { _, enabled in
            controller.setBatteryLevelsEnabled(enabled)
        }
        .onDisappear {
            controller.setBatteryLevelsEnabled(false)
        }
    }

    private func section(_ title: String, devices: [BluetoothDevice]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(devices) { device in
                HStack(spacing: 10) {
                    Image(systemName: icon(for: device.kind))
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                    Text(device.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    if showsBatteryLevels {
                        Text(batterySummary(for: device))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(device.isConnected ? localization.string(.bluetoothConnected) : localization.string(.bluetoothNotConnected))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
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

    private func batterySummary(for device: BluetoothDevice) -> String {
        let address = BluetoothBatteryReader.normalizedAddress(device.id)
        return controller.batteryLevels[address]?.summary
            ?? localization.string(.bluetoothBatteryUnavailable)
    }

    private func icon(for kind: BluetoothDeviceKind) -> String {
        switch kind {
        case .computer: "laptopcomputer"
        case .phone: "iphone"
        case .audio: "headphones"
        case .peripheral: "computermouse"
        case .unknown: "questionmark.circle"
        }
    }
}
