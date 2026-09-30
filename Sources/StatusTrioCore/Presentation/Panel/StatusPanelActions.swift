import CoreAudio
import Foundation

@MainActor
final class StatusPanelActions {
    private let outputDevices: () -> [AudioOutputDevice]
    private let selectOutputDevice: (AudioOutputDevice) -> Void
    private let inputDevices: () -> [AudioInputDevice]
    private let selectInputDevice: (AudioInputDevice) -> Void
    private let setVolumeCommand: (Double) -> Void
    private let finishVolumeCommand: () -> Void
    private let toggleMuteCommand: () -> Void
    private let setInputScalarCommand: (Double) -> Void
    private let toggleInputMuteCommand: () -> Void
    private let outputPreferences: () -> AudioOutputListPreferences
    private let bluetoothDevices: () -> [BluetoothDevice]
    private let bluetoothListOptions: () -> BluetoothDeviceListOptions
    private let bluetoothAvailability: () -> BluetoothAvailability
    private let refreshBluetoothCommand: () -> Void
    private let requestBluetoothAuthorizationCommand: () -> Void
    private let openBluetoothPermissionSettingsCommand: () -> Void
    private let performBluetoothActionCommand: (BluetoothDevice) -> Void
    private let requestDisconnectCommand: (BluetoothDevice) -> Void
    private let disconnectConfirmationAddress: () -> String?
    private let cancelDisconnectCommand: () -> Void
    private let requestBatteryLevelsCommand: (String) -> Void
    private let releaseBatteryLevelsCommand: (String) -> Void
    private let requestNearbyBatteryDevicesCommand: (String) -> Void
    private let releaseNearbyBatteryDevicesCommand: (String) -> Void
    private let setListeningModeCommand: (BluetoothListeningMode, String) -> Void
    private let listeningModePresentations: () -> [String: BluetoothListeningModePresentation]
    private let listeningModeDevices: () -> [BluetoothDevice]
    private let batteryStatus: () -> BatteryStatus
    private let activateBatteryDetails: (BatteryPowerState) -> Void
    private let closeBatteryDetails: () -> Void
    private let wifiNameAccess: () -> WiFiNameAccess
    private let activateWiFiDetails: (WiFiNameAccess) -> Void
    private let closeWiFiDetails: () -> Void
    private let setWiFiPowerCommand: (Bool) -> Void
    private let refreshWiFiCommand: (WiFiNameAccess) -> Void
    private let openWiredDetails: () -> Void
    private let closeWiredDetails: () -> Void
    private let holdBluetoothSummary: () -> Void
    private let releaseBluetoothSummary: () -> Void
    private let refreshVolumeListeningModes: () -> Void
    private let stopVolumeListeningModes: () -> Void
    private let moveOutputDevicesCommand: (IndexSet, Int) -> Void
    private let moveBluetoothDevicesCommand: (IndexSet, Int, [String]) -> Void

    private static let summaryBatteryLevelsToken = "bluetooth.summary"
    private static let nearbyBatteryDevicesToken = "bluetooth.summary.nearbyBatteryDevices"

    var outputDeviceListPreferences: AudioOutputListPreferences {
        outputPreferences()
    }

    /// Narrow injection keeps command routing testable without introducing a
    /// second monitor abstraction around the existing store.
    init(
        outputDevices: @escaping () -> [AudioOutputDevice] = { [] },
        selectOutput: @escaping (AudioOutputDevice) -> Void = { _ in },
        inputDevices: @escaping () -> [AudioInputDevice] = { [] },
        selectInput: @escaping (AudioInputDevice) -> Void = { _ in },
        setVolume: @escaping (Double) -> Void = { _ in },
        finishVolumeAdjustment: @escaping () -> Void = {},
        toggleMute: @escaping () -> Void = {},
        setInputScalar: @escaping (Double) -> Void = { _ in },
        toggleInputMute: @escaping () -> Void = {},
        outputPreferences: @escaping () -> AudioOutputListPreferences = { .default },
        bluetoothDevices: @escaping () -> [BluetoothDevice] = { [] },
        bluetoothListOptions: @escaping () -> BluetoothDeviceListOptions = { .standard },
        bluetoothAvailability: @escaping () -> BluetoothAvailability = { .idle },
        refreshBluetooth: @escaping () -> Void = {},
        requestBluetoothAuthorization: @escaping () -> Void = {},
        openBluetoothPermissionSettings: @escaping () -> Void = {},
        performBluetoothAction: @escaping (BluetoothDevice) -> Void = { _ in },
        requestDisconnect: @escaping (BluetoothDevice) -> Void = { _ in },
        disconnectConfirmationAddress: @escaping () -> String? = { nil },
        cancelDisconnect: @escaping () -> Void = {},
        requestBatteryLevels: @escaping (String) -> Void = { _ in },
        releaseBatteryLevels: @escaping (String) -> Void = { _ in },
        requestNearbyBatteryDevices: @escaping (String) -> Void = { _ in },
        releaseNearbyBatteryDevices: @escaping (String) -> Void = { _ in },
        setListeningMode: @escaping (BluetoothListeningMode, String) -> Void = { _, _ in },
        listeningModePresentations: @escaping () -> [String: BluetoothListeningModePresentation] = { [:] },
        listeningModeDevices: (() -> [BluetoothDevice])? = nil,
        batteryStatus: @escaping () -> BatteryStatus = { .placeholder },
        activateBatteryDetails: @escaping (BatteryPowerState) -> Void = { _ in },
        closeBatteryDetails: @escaping () -> Void = {},
        wifiNameAccess: @escaping () -> WiFiNameAccess = { .notDetermined },
        activateWiFiDetails: @escaping (WiFiNameAccess) -> Void = { _ in },
        closeWiFiDetails: @escaping () -> Void = {},
        setWiFiPower: @escaping (Bool) -> Void = { _ in },
        refreshWiFi: @escaping (WiFiNameAccess) -> Void = { _ in },
        openWiredDetails: @escaping () -> Void = {},
        closeWiredDetails: @escaping () -> Void = {},
        holdBluetoothSummary: @escaping () -> Void = {},
        releaseBluetoothSummary: @escaping () -> Void = {},
        refreshVolumeListeningModes: @escaping () -> Void = {},
        stopVolumeListeningModes: @escaping () -> Void = {},
        moveOutputDevices: @escaping (IndexSet, Int) -> Void = { _, _ in },
        moveBluetoothDevices: @escaping (IndexSet, Int) -> Void = { _, _ in },
        moveResolvedBluetoothDevices: ((IndexSet, Int, [String]) -> Void)? = nil
    ) {
        self.outputDevices = outputDevices
        self.selectOutputDevice = selectOutput
        self.inputDevices = inputDevices
        self.selectInputDevice = selectInput
        self.setVolumeCommand = setVolume
        self.finishVolumeCommand = finishVolumeAdjustment
        self.toggleMuteCommand = toggleMute
        self.setInputScalarCommand = setInputScalar
        self.toggleInputMuteCommand = toggleInputMute
        self.outputPreferences = outputPreferences
        self.bluetoothDevices = bluetoothDevices
        self.bluetoothListOptions = bluetoothListOptions
        self.bluetoothAvailability = bluetoothAvailability
        self.refreshBluetoothCommand = refreshBluetooth
        self.requestBluetoothAuthorizationCommand = requestBluetoothAuthorization
        self.openBluetoothPermissionSettingsCommand = openBluetoothPermissionSettings
        self.performBluetoothActionCommand = performBluetoothAction
        self.requestDisconnectCommand = requestDisconnect
        self.disconnectConfirmationAddress = disconnectConfirmationAddress
        self.cancelDisconnectCommand = cancelDisconnect
        self.requestBatteryLevelsCommand = requestBatteryLevels
        self.releaseBatteryLevelsCommand = releaseBatteryLevels
        self.requestNearbyBatteryDevicesCommand = requestNearbyBatteryDevices
        self.releaseNearbyBatteryDevicesCommand = releaseNearbyBatteryDevices
        self.setListeningModeCommand = setListeningMode
        self.listeningModePresentations = listeningModePresentations
        self.listeningModeDevices = listeningModeDevices ?? bluetoothDevices
        self.batteryStatus = batteryStatus
        self.activateBatteryDetails = activateBatteryDetails
        self.closeBatteryDetails = closeBatteryDetails
        self.wifiNameAccess = wifiNameAccess
        self.activateWiFiDetails = activateWiFiDetails
        self.closeWiFiDetails = closeWiFiDetails
        self.setWiFiPowerCommand = setWiFiPower
        self.refreshWiFiCommand = refreshWiFi
        self.openWiredDetails = openWiredDetails
        self.closeWiredDetails = closeWiredDetails
        self.holdBluetoothSummary = holdBluetoothSummary
        self.releaseBluetoothSummary = releaseBluetoothSummary
        self.refreshVolumeListeningModes = refreshVolumeListeningModes
        self.stopVolumeListeningModes = stopVolumeListeningModes
        self.moveOutputDevicesCommand = moveOutputDevices
        self.moveBluetoothDevicesCommand = moveResolvedBluetoothDevices ?? { offsets, destination, _ in
            moveBluetoothDevices(offsets, destination)
        }
    }

    convenience init(store: SystemStatusStore, settings: SettingsStore) {
        self.init(
            outputDevices: { store.liveVolume.outputDevices },
            selectOutput: { device in store.selectOutputDevice(device) },
            inputDevices: { store.liveInput.devices },
            selectInput: { device in store.selectInputDevice(device.id) },
            setVolume: { scalar in store.setVolume(scalar) },
            finishVolumeAdjustment: { store.finishVolumeAdjustment() },
            toggleMute: { store.toggleMute() },
            setInputScalar: { scalar in store.setInputScalar(scalar) },
            toggleInputMute: { store.toggleInputMute() },
            outputPreferences: {
                AudioOutputListPreferences(
                    order: settings.outputDeviceOrder,
                    visibleLimit: settings.visibleOutputDeviceLimit
                )
            },
            bluetoothDevices: { store.bluetoothDevices.devices },
            bluetoothListOptions: { settings.bluetoothDeviceListOptions },
            bluetoothAvailability: { store.bluetoothDevices.availability },
            refreshBluetooth: { store.bluetoothDevices.refreshFromUser() },
            requestBluetoothAuthorization: { store.requestBluetoothAuthorization() },
            openBluetoothPermissionSettings: { store.openBluetoothPermissionSettings() },
            performBluetoothAction: { store.bluetoothDevices.performDeviceAction(for: $0) },
            requestDisconnect: { store.bluetoothDevices.requestDisconnectConfirmation(for: $0) },
            disconnectConfirmationAddress: { store.bluetoothDevices.pendingDisconnectConfirmation },
            cancelDisconnect: { store.bluetoothDevices.cancelDisconnectConfirmation() },
            requestBatteryLevels: { store.bluetoothDevices.requestBatteryLevels($0) },
            releaseBatteryLevels: { store.bluetoothDevices.releaseBatteryLevels($0) },
            requestNearbyBatteryDevices: { store.bluetoothDevices.requestNearbyBatteryDevices($0) },
            releaseNearbyBatteryDevices: { store.bluetoothDevices.releaseNearbyBatteryDevices($0) },
            setListeningMode: { store.bluetoothListeningModes.setMode($0, forAddress: $1) },
            listeningModePresentations: { store.bluetoothListeningModes.presentations },
            listeningModeDevices: {
                let config = ListeningModePreview.Configuration(
                    isEnabled: settings.previewsBluetoothListeningMode,
                    deviceName: settings.bluetoothListeningModePreviewDeviceName,
                    deviceCount: settings.bluetoothListeningModePreviewDeviceCount,
                    languageCode: settings.bluetoothListeningModePreviewLanguage
                )
                return store.bluetoothDevices.devices + ListeningModePreview.devices(for: config)
            },
            batteryStatus: { store.popupSnapshot.battery },
            activateBatteryDetails: { store.batteryDetails.activate(state: $0) },
            closeBatteryDetails: { store.batteryDetails.deactivate() },
            wifiNameAccess: { store.popupSnapshot.wifi.nameAccess },
            activateWiFiDetails: { store.wifiNetworks.activate(nameAccess: $0) },
            closeWiFiDetails: { store.wifiNetworks.deactivate() },
            setWiFiPower: { store.wifiNetworks.setPower($0) },
            refreshWiFi: { store.wifiNetworks.refreshNow(nameAccess: $0) },
            openWiredDetails: { store.activatePrimaryLinkPanel() },
            closeWiredDetails: { store.closePrimaryLinkPanel() },
            holdBluetoothSummary: { store.bluetoothDevices.holdVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken) },
            releaseBluetoothSummary: { store.bluetoothDevices.releaseVisibleSurface(BluetoothDeviceController.bluetoothSummarySurfaceToken) },
            refreshVolumeListeningModes: {
                let config = ListeningModePreview.Configuration(
                    isEnabled: settings.previewsBluetoothListeningMode,
                    deviceName: settings.bluetoothListeningModePreviewDeviceName,
                    deviceCount: settings.bluetoothListeningModePreviewDeviceCount,
                    languageCode: settings.bluetoothListeningModePreviewLanguage
                )
                store.bluetoothListeningModes.previewMode = config.isEnabled
                store.bluetoothListeningModes.refresh(
                    devices: store.bluetoothDevices.devices + ListeningModePreview.devices(for: config)
                )
            },
            stopVolumeListeningModes: { store.bluetoothListeningModes.stop() },
            moveOutputDevices: { offsets, destination in
                settings.moveOutputDevices(
                    fromOffsets: offsets,
                    toOffset: destination,
                    in: settings.orderedOutputDevices(store.liveVolume.outputDevices)
                )
            },
            moveResolvedBluetoothDevices: { offsets, destination, displayedAddresses in
                Self.movePanelBluetoothDevices(
                    fromOffsets: offsets,
                    toOffset: destination,
                    displayedAddresses: displayedAddresses,
                    devices: store.bluetoothDevices.devices,
                    options: settings.bluetoothDeviceListOptions,
                    settings: settings
                )
            }
        )
    }

    func setVolume(_ scalar: Double) {
        guard scalar.isFinite else { return }
        setVolumeCommand(min(1, max(0, scalar)))
    }

    func finishVolumeAdjustment() {
        finishVolumeCommand()
    }

    func toggleMute() {
        toggleMuteCommand()
    }

    func selectOutput(_ key: PanelAudioDeviceID) {
        guard let device = outputDevices().first(where: {
            $0.id == key.id && (key.uid == nil || $0.uid == key.uid)
        }) else { return }
        selectOutputDevice(device)
    }

    func setInputScalar(_ scalar: Double) {
        guard scalar.isFinite else { return }
        setInputScalarCommand(min(1, max(0, scalar)))
    }

    func toggleInputMute() {
        toggleInputMuteCommand()
    }

    func selectInput(_ key: PanelAudioDeviceID) {
        guard let device = inputDevices().first(where: {
            $0.id == key.id && (key.uid == nil || $0.uid == key.uid)
        }) else { return }
        selectInputDevice(device)
    }

    func refreshBluetooth() { refreshBluetoothCommand() }
    func requestBluetoothAuthorization() { requestBluetoothAuthorizationCommand() }
    func openBluetoothPermissionSettings() { openBluetoothPermissionSettingsCommand() }

    func performBluetoothAction(address: String) {
        guard let device = bluetoothDevice(address: address),
              !BluetoothDeviceActionPolicy.requiresConfirmation(for: device) else { return }
        performBluetoothActionCommand(device)
    }

    func rowTapped(address: String) {
        guard let device = bluetoothDevice(address: address) else { return }
        if BluetoothDeviceActionPolicy.requiresConfirmation(for: device) {
            requestDisconnectCommand(device)
        } else {
            performBluetoothActionCommand(device)
        }
    }

    func confirmBluetoothDisconnect(address: String) {
        let key = BluetoothBatteryReader.normalizedAddress(address)
        guard !key.isEmpty,
              BluetoothBatteryReader.normalizedAddress(disconnectConfirmationAddress() ?? "") == key,
              let device = bluetoothDevice(address: key),
              BluetoothDeviceActionPolicy.requiresConfirmation(for: device) else { return }
        performBluetoothActionCommand(device)
    }

    func requestDisconnect(address: String) {
        guard let device = bluetoothDevice(address: address),
              BluetoothDeviceActionPolicy.requiresConfirmation(for: device) else { return }
        requestDisconnectCommand(device)
    }

    func cancelDisconnect() { cancelDisconnectCommand() }

    func updateBluetoothBatteryLevelsClaim(enabled: Bool) {
        guard enabled,
              BluetoothSummary.presentation(
                availability: bluetoothAvailability(),
                devices: bluetoothDevices(),
                batteryLevels: [:]
              ).hasConnectedDevices else {
            releaseBatteryLevelsCommand(Self.summaryBatteryLevelsToken)
            return
        }
        requestBatteryLevelsCommand(Self.summaryBatteryLevelsToken)
    }

    func updateBluetoothNearbyBatteryClaim(enabled: Bool) {
        if enabled {
            requestNearbyBatteryDevicesCommand(Self.nearbyBatteryDevicesToken)
        } else {
            releaseNearbyBatteryDevicesCommand(Self.nearbyBatteryDevicesToken)
        }
    }

    func setListeningMode(address: String, mode: BluetoothListeningMode) {
        let key = BluetoothBatteryReader.normalizedAddress(address)
        guard !key.isEmpty,
              listeningModeDevices().contains(where: { BluetoothBatteryReader.normalizedAddress($0.id) == key }),
              let presentation = listeningModePresentations()[key],
              presentation.availableModes.contains(mode) else { return }
        setListeningModeCommand(mode, key)
    }

    func batteryDetailsAppeared() { activateBatteryDetails(BatteryPowerState(batteryStatus())) }
    func batteryDetailsClosed() { closeBatteryDetails() }
    func wifiDetailsOpened() { activateWiFiDetails(wifiNameAccess()) }
    func wifiDetailsClosed() { closeWiFiDetails() }
    func wiredDetailsOpened() { openWiredDetails() }
    func wiredDetailsClosed() { closeWiredDetails() }
    func bluetoothSummaryAppeared() { holdBluetoothSummary() }

    func bluetoothSummaryDisappeared() {
        releaseBluetoothSummary()
        releaseBatteryLevelsCommand(Self.summaryBatteryLevelsToken)
    }

    func volumeListAppeared() { refreshVolumeListeningModes() }

    /// Called by the list task when connected-device membership or preview
    /// configuration changes; listening-mode discovery has no timer.
    func volumeListChanged() { refreshVolumeListeningModes() }
    func volumeListDisappeared() { stopVolumeListeningModes() }
    func setWiFiPower(_ enabled: Bool) { setWiFiPowerCommand(enabled) }
    func refreshWiFi() { refreshWiFiCommand(wifiNameAccess()) }
    func moveOutputDevices(from offsets: IndexSet, to destination: Int) { moveOutputDevicesCommand(offsets, destination) }
    func moveBluetoothDevices(from offsets: IndexSet, to destination: Int) {
        let options = bluetoothListOptions()
        let rows = BluetoothDeviceListPresentation.orderedDevices(
            BluetoothDeviceListPresentation.filteredDevices(bluetoothDevices(), options: options),
            using: options.order
        )
        moveBluetoothDevicesCommand(offsets, destination, rows.map(\.id))
    }

    func moveBluetoothDevices(from offsets: IndexSet, to destination: Int, displayedAddresses: [String]) {
        moveBluetoothDevicesCommand(offsets, destination, displayedAddresses)
    }

    private func bluetoothDevice(address: String) -> BluetoothDevice? {
        let key = BluetoothBatteryReader.normalizedAddress(address)
        guard !key.isEmpty else { return nil }
        return bluetoothDevices().first { BluetoothBatteryReader.normalizedAddress($0.id) == key }
    }

    private static func movePanelBluetoothDevices(
        fromOffsets offsets: IndexSet,
        toOffset destination: Int,
        displayedAddresses: [String],
        devices: [BluetoothDevice],
        options: BluetoothDeviceListOptions,
        settings: SettingsStore
    ) {
        let displayedKeys = displayedAddresses.map { BluetoothBatteryReader.normalizedAddress($0) }
        guard !displayedKeys.isEmpty,
              Set(displayedKeys).count == displayedKeys.count,
              !displayedKeys.contains(where: \.isEmpty),
              offsets.allSatisfy({ displayedKeys.indices.contains($0) }),
              (0...displayedKeys.count).contains(destination) else { return }

        let resolved = BluetoothDeviceListPresentation.orderedDevices(
            BluetoothDeviceListPresentation.filteredDevices(devices, options: options),
            using: options.order
        )
        let resolvedPrefix = Array(resolved.prefix(displayedKeys.count)).map {
            BluetoothBatteryReader.normalizedAddress($0.id)
        }
        guard displayedKeys == resolvedPrefix else { return }

        let movedKeys = offsets.map { displayedKeys[$0] }
        let remainingKeys = displayedKeys.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        let insertionOffset = destination - offsets.filter { $0 < destination }.count
        var reorderedKeys = remainingKeys
        reorderedKeys.insert(contentsOf: movedKeys, at: min(insertionOffset, remainingKeys.count))

        let rawOrdered = BluetoothDeviceListPresentation.orderedDevices(devices, using: options.order)
        let deviceByKey = Dictionary(
            devices.map { (BluetoothBatteryReader.normalizedAddress($0.id), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let movedSet = Set(displayedKeys)
        var reorderedIterator = reorderedKeys.makeIterator()
        let merged = rawOrdered.map { device in
            let key = BluetoothBatteryReader.normalizedAddress(device.id)
            guard movedSet.contains(key), let replacementKey = reorderedIterator.next(),
                  let replacement = deviceByKey[replacementKey] else { return device }
            return replacement
        }
        guard !merged.isEmpty else { return }
        settings.moveBluetoothDevices(
            fromOffsets: IndexSet(integersIn: merged.indices),
            toOffset: merged.count,
            in: merged
        )
    }
}
