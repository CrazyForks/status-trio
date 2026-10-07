import SwiftUI

/// The Bluetooth summary row. It reports live device state — a permission
/// request while the grant is undecided, then the states only the row can
/// explain — and lists available device readings under it. A connected device is marked
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
    @ObservedObject var mobileBatteryController: MobileBatteryController
    @EnvironmentObject private var localization: Localization
    let showsBatteryLevels: Bool
    var showsAppleDevicesAndBattery = false
    var trustedAppleDeviceMetadata: [AppleDeviceCandidate] = []
    var currentTrustedAppleCandidates: [AppleDeviceCandidate] = []
    var trustedDiscoveryGeneration: UInt64 = 0
    var listOptions: BluetoothDeviceListOptions = .standard
    let onRequestAuthorization: () -> Void
    let onOpenBluetoothSettings: () -> Void
    let onOpenBluetoothPermissionSettings: () -> Void

    @State private var visibleTrustedAppleIDs = Set<AppleDeviceID>()

    private var appleProjection: AppleDeviceCatalog.Projection {
        let candidates = showsAppleDevicesAndBattery
            ? AppleDeviceCatalog.candidates(trusted: trustedAppleDeviceMetadata)
            : []
        let knownIDs = Set(candidates.map(\.id))
        let failures = Set(mobileBatteryController.failures.compactMap { failure -> AppleDeviceID? in
            guard let deviceID = failure.deviceID else { return nil }
            let match = candidates.first { candidate in
                switch candidate.id {
                case let .trustedDevice(id): id == deviceID
                case let .trustedWatch(_, id): id == deviceID
                case .ble: false
                }
            }?.id
            return match.flatMap { knownIDs.contains($0) ? $0 : nil }
        })
        return AppleDeviceCatalog.projection(
            candidates: candidates,
            trustedSnapshots: showsAppleDevicesAndBattery && showsMobileBatteryFeature ? mobileBatteryController.snapshots : [],
            failures: showsMobileBatteryFeature ? failures : [],
            options: listOptions
        )
    }

    var body: some View {
        let appleProjection = appleProjection
        let appleRows = appleProjection.rows

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                titleBlock

                Button(action: {
                    controller.refreshFromUser()
                    mobileBatteryController.refresh()
                }) {
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
                // The same weight as the disclosure chevron the other rows end
                // on, so the panel's trailing column reads as one thing. The gear
                // beside it stays `secondary`, exactly as it does next to that
                // chevron in the Wi-Fi and battery rows.
                .foregroundStyle(.tertiary)
                .help(localization.string(.bluetoothRefresh))
                .accessibilityLabel(localization.string(.bluetoothRefresh))

                Button(localization.string(.bluetoothActionOpenSettings), systemImage: "gearshape", action: onOpenBluetoothSettings)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(localization.string(.bluetoothActionOpenSettings))
                    .frame(width: 24, height: 24)
            }

            if listOptions.showsList && (BluetoothPanelListVisibility.showsList(availability: controller.availability, devices: controller.devices, options: listOptions) || !appleRows.isEmpty) {
                BluetoothDeviceList(
                    devices: controller.devices,
                    batteryLevels: controller.batteryLevels.merging(appleProjection.batteryLevels, uniquingKeysWith: { _, apple in apple }),
                    mobileMetadataByDeviceID: appleProjection.mobileMetadataByDeviceID,
                    appleRows: appleRows,
                    onVisibleAppleIDsChanged: { ids in
                        visibleTrustedAppleIDs = ids
                        updateTrustedReadAuthorization()
                    },
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

            if let message = mobileFailureMessage {
                Text(localization.string(message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            controller.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
        }
        .task(id: batteryReadTaskID) {
            // Reading levels launches system_profiler, so the claim is held only
            // while the summary actually wants them. The row stays on screen
            // while the setting changes, so the release has to happen here and
            // not only in `onDisappear`: otherwise switching the setting off
            // leaves the read running and the level it published on screen until
            // the row disappears and comes back. A claim rather than a toggle
            guard showsBatteryLevels, summaryPresentation.hasConnectedDevices else {
                controller.releaseBatteryLevels(Self.summaryBatteryLevelsToken)
                return
            }
            controller.requestBatteryLevels(Self.summaryBatteryLevelsToken)
        }
        .task(id: mobileBatteryClaimTaskID) {
            guard showsMobileBatteryFeature else {
                mobileBatteryController.release(Self.mobileBatteryToken)
                return
            }
            mobileBatteryController.request(Self.mobileBatteryToken)
        }
        .task(id: currentTrustedAppleGeneration) {
            mobileBatteryController.setAuthorizedDeviceIDs([])
        }
        .onChange(of: currentTrustedAppleCandidates) { _, _ in
            updateTrustedReadAuthorization()
        }
        .onDisappear {
            controller.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken)
            controller.releaseBatteryLevels(Self.summaryBatteryLevelsToken)
            mobileBatteryController.release(
                Self.mobileBatteryToken,
                keepingResults: showsMobileBatteryFeature
            )
            mobileBatteryController.setAuthorizedDeviceIDs([])
        }
    }

    /// The title and its subtitle. It is a button only while the state has
    /// somewhere to send the user — asking for the grant, or the pane that gives
    /// a refused one back — which is the same rule the Wi-Fi row follows. A state
    /// with no action stays a plain, non-focusable row.
    @ViewBuilder
    private var titleBlock: some View {
        if let action = summaryPresentation.rowAction {
            Button(action: { perform(action) }) { titleContent }
                .buttonStyle(.plain)
                .accessibilityLabel(rowAccessibilityLabel)
        } else {
            titleContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rowAccessibilityLabel)
        }
    }

    private var titleContent: some View {
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
        .contentShape(Rectangle())
    }

    private func perform(_ action: BluetoothSummaryRowAction) {
        switch action {
        case .requestAuthorization:
            onRequestAuthorization()
        case .openPermissionSettings:
            onOpenBluetoothPermissionSettings()
        }
    }

    private static let summaryBatteryLevelsToken = "bluetooth.summary"
    private static let mobileBatteryToken = "bluetooth.summary.mobileBatteryDevices"

    private var mobileBatteryClaimTaskID: String {
        "\(showsBatteryLevels)-\(showsAppleDevicesAndBattery)-\(listOptions.showsList)"
    }

    private var currentTrustedAppleGeneration: UInt64 {
        showsAppleDevicesAndBattery ? trustedDiscoveryGeneration : 0
    }

    private func updateTrustedReadAuthorization() {
        guard showsMobileBatteryFeature else {
            mobileBatteryController.setAuthorizedDeviceIDs([])
            return
        }
        mobileBatteryController.setAuthorizedDeviceIDs(AppleDeviceCatalog.readAuthorizedIDs(
            visibleIDs: visibleTrustedAppleIDs,
            currentCandidates: currentTrustedAppleCandidates
        ))
    }

    private var showsMobileBatteryFeature: Bool {
        showsBatteryLevels && showsAppleDevicesAndBattery && listOptions.showsList
    }

    private var mobileFailureMessage: LocalizationKey? {
        MobileBatteryFailurePresentation.message(
            isEnabled: showsMobileBatteryFeature,
            snapshots: mobileBatteryController.snapshots,
            failures: mobileBatteryController.failures,
            isRefreshing: mobileBatteryController.isRefreshing
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
            actionLabel(.bluetoothActionRequestAuthorization, action: onRequestAuthorization)
        } else if case .authorizationDenied = summaryPresentation {
            // The row itself performs this, the way the Wi-Fi row's subtitle does
            // for location; the line reads as what tapping does rather than as a
            // statement of fact, and a refused grant is the one state the user can
            // act on from here.
            actionLabel(
                .bluetoothActionOpenPermissionSettings,
                action: onOpenBluetoothPermissionSettings
            )
        } else if hidesSubtitle {
            EmptyView()
        } else if let segments = summaryPresentation.deviceSegments {
            // The same pieces the device rows draw, so the charging case is one
            // glyph on both surfaces rather than a glyph here and a word there.
            // Every other state is one sentence of localized text.
            BluetoothBatteryLevelText.drawn(segments)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func actionLabel(
        _ key: LocalizationKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(localization.string(key), action: action)
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var summaryText: String {
        switch summaryPresentation {
        case .requestAuthorization:
            return localization.string(.bluetoothAuthorizationNotDetermined)
        case .initializing:
            return localization.string(.bluetoothInitializing)
        case .authorizationDenied:
            return localization.string(.bluetoothActionOpenPermissionSettings)
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
        case .devices:
            // The device line is drawn from its pieces; this is its text form,
            // which is what the accessibility label above reads.
            return summaryPresentation.deviceNames ?? ""
        }
    }
}
