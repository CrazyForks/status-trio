import Foundation

@MainActor
enum BluetoothPanelMapper {
    static func map(
        availability: BluetoothAvailability,
        devices: [BluetoothDevice],
        batteryLevels: [String: BluetoothBatteryLevel],
        actionStates: [String: BluetoothDeviceActionState],
        nearbyDevices: [NearbyBluetoothBatteryDevice],
        batteryLevelsReadFailed: Bool,
        isExpanded: Bool,
        options: BluetoothDeviceListOptions,
        showsBatteryLevels: Bool,
        showsNearbyBatteryDevices: Bool,
        confirmingAddress: String?,
        localization: Localization
    ) -> BluetoothPanelState {
        let visibleNearby = BluetoothNearbyBatteryListPresentation.visibleDevices(
            from: nearbyDevices,
            enabled: showsBatteryLevels && showsNearbyBatteryDevices
        )
        let listIsVisible = BluetoothPanelListVisibility.showsList(
            availability: availability,
            devices: devices,
            options: options
        )
        let list = BluetoothDeviceListModel.make(
            devices: devices,
            order: options.order,
            limit: options.maxVisibleDevices,
            isExpanded: isExpanded,
            options: options
        )
        let pairedRows = listIsVisible
            ? list.visibleDevices.map {
                pairedRow(
                    $0,
                    batteryLevels: showsBatteryLevels ? batteryLevels : [:],
                    actionStates: actionStates,
                    localization: localization
                )
            }
            : []
        let nearbyRows = visibleNearby.map { device in
            nearbyRow(device, localization: localization)
        }
        let summary = BluetoothSummary.presentation(
            availability: availability,
            devices: devices,
            batteryLevels: showsBatteryLevels ? batteryLevels : [:]
        )
        let hideSubtitle = BluetoothPanelListVisibility.hidesRowSubtitle(
            availability: availability,
            devices: devices,
            options: options
        )
        let summaryText = summaryText(summary, localization: localization)
        let accessibilitySummary = summary == .requestAuthorization
            ? localization.string(.bluetoothAuthorizationNotDetermined)
            : summaryText
        let title = localization.string(.bluetoothTitle)
        let summaryState = PanelSummaryState(
            title: title,
            subtitle: hideSubtitle ? "" : summaryText,
            measurements: nil,
            symbol: .symbol(name: "bluetooth", variableValue: nil, fallback: "antenna.radiowaves.left.and.right"),
            tint: .secondary,
            accessibilityLabel: hideSubtitle ? title : "\(title), \(accessibilitySummary)",
            accessibilityValue: accessibilitySummary,
            showsSettings: true,
            intent: .none
        )
        let normalizedConfirmation = confirmingAddress.map { BluetoothBatteryReader.normalizedAddress($0) }

        return BluetoothPanelState(
            summary: summaryState,
            pairedRows: pairedRows,
            nearbyRows: nearbyRows,
            errorText: listIsVisible && batteryLevelsReadFailed
                ? localization.string(.bluetoothBatteryUnavailable)
                : nil,
            showsPairedHeading: !pairedRows.isEmpty && !nearbyRows.isEmpty,
            canExpand: listIsVisible && list.canToggleExpansion,
            confirmationAddress: normalizedConfirmation
        )
    }

    private static func pairedRow(
        _ device: BluetoothDevice,
        batteryLevels: [String: BluetoothBatteryLevel],
        actionStates: [String: BluetoothDeviceActionState],
        localization: Localization
    ) -> PanelBluetoothDeviceRow {
        let address = BluetoothBatteryReader.normalizedAddress(device.id)
        let actionState = actionStates[address]
        let status = BluetoothDeviceActionPolicy.status(for: device, actionState: actionState)
        let batterySegments = BluetoothDevicePresentation.batteryLevelSegments(
            for: device,
            batteryLevels: batteryLevels
        )
        let stateText: String
        switch status {
        case .connected: stateText = localization.string(.bluetoothConnected)
        case .notConnected: stateText = localization.string(.bluetoothNotConnected)
        case .connecting: stateText = localization.string(.bluetoothStateConnecting)
        case .disconnecting: stateText = localization.string(.bluetoothStateDisconnecting)
        case .connectFailed: stateText = localization.string(.bluetoothStateConnectFailed)
        case .disconnectFailed: stateText = localization.string(.bluetoothStateDisconnectFailed)
        }
        let action = BluetoothDeviceActionPolicy.action(for: device)
        let isBusy: Bool
        switch actionState {
        case .connecting, .disconnecting: isBusy = true
        case .failed, .none: isBusy = false
        }
        let subtitle: String?
        switch status {
        case .connecting: subtitle = localization.string(.bluetoothStateConnecting)
        case .disconnecting: subtitle = localization.string(.bluetoothStateDisconnecting)
        case .connectFailed: subtitle = localization.string(.bluetoothStateConnectFailed)
        case .disconnectFailed: subtitle = localization.string(.bluetoothStateDisconnectFailed)
        case .connected, .notConnected: subtitle = nil
        }
        return PanelBluetoothDeviceRow(
            address: address,
            title: device.name,
            subtitle: subtitle,
            icon: .symbol(name: BluetoothDeviceRowIcon.symbolName(for: device), variableValue: nil, fallback: "dot.radiowaves.left.and.right"),
            batteryText: batterySegments?.plainText,
            actionTitle: localization.string(action == .connect ? .bluetoothActionConnect : .bluetoothActionDisconnect),
            actionEnabled: !isBusy,
            isBusy: isBusy,
            accessibilityLabel: device.name,
            accessibilityValue: [stateText, batterySegments?.plainText].compactMap { $0 }.joined(separator: ", ")
        )
    }

    private static func nearbyRow(
        _ device: NearbyBluetoothBatteryDevice,
        localization: Localization
    ) -> PanelBluetoothDeviceRow {
        let title = device.displayName(fallback: localization.string(.bluetoothNearbyDeviceFallback))
        let value = localization.format(.batteryAccessibilityValue, device.batteryLevel)
        return PanelBluetoothDeviceRow(
            address: device.id.uuidString,
            title: title,
            subtitle: nil,
            icon: .symbol(name: "dot.radiowaves.left.and.right", variableValue: nil, fallback: nil),
            batteryText: "\(device.batteryLevel)%",
            actionTitle: "",
            actionEnabled: false,
            isBusy: false,
            accessibilityLabel: title,
            accessibilityValue: value
        )
    }

    private static func summaryText(_ summary: BluetoothSummary, localization: Localization) -> String {
        switch summary {
        case .requestAuthorization: localization.string(.bluetoothAuthorizationNotDetermined)
        case .initializing: localization.string(.bluetoothInitializing)
        case .authorizationDenied: localization.string(.bluetoothActionOpenPermissionSettings)
        case .authorizationRestricted: localization.string(.bluetoothAuthorizationRestricted)
        case .poweredOff: localization.string(.bluetoothOff)
        case .unavailable: localization.string(.bluetoothUnavailable)
        case .readFailed: localization.string(.bluetoothReadFailed)
        case .noConnectedDevices: localization.string(.bluetoothNoConnectedDevices)
        case .devices: summary.deviceNames ?? ""
        }
    }
}
