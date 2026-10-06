import SwiftUI

struct AppleDeviceSelectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var discovery: AppleDeviceDiscoveryController
    @ObservedObject var bluetooth: BluetoothDeviceController
    @EnvironmentObject private var localization: Localization

    private static let discoveryToken = "bluetooth.settings.appleDevices"

    private var candidates: [AppleDeviceCandidate] {
        var candidates = AppleDeviceCatalog.candidates(
            ble: bluetooth.nearbyBLECandidates,
            trusted: discovery.candidates,
            selections: store.appleDeviceSelections
        )
        candidates.append(contentsOf: discovery.candidates.filter {
            $0.trustRequired && !$0.isSelectableAppleDevice
        })
        return Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { current, hint in
            current.isSelectableAppleDevice ? current : hint
        }).values.sorted { $0.id.rowID < $1.id.rowID }
    }

    var body: some View {
        SettingsGroup(localization.string(.settingsAppleDeviceSelectionTitle)) {
            SettingsRow(title: localization.string(.settingsAppleDeviceSelectionTitle)) {
                Button {
                    discovery.refresh()
                } label: {
                    HStack(spacing: 6) {
                        if discovery.isDiscovering {
                            ProgressView().controlSize(.small)
                            Text(localization.string(.settingsBluetoothNearbyBLEScanning))
                        } else {
                            Image(systemName: "arrow.clockwise")
                            Text(localization.string(.settingsBluetoothNearbyBLEScan))
                        }
                    }
                }
                .controlSize(.small)
                .disabled(discovery.isDiscovering)
            }

            if candidates.isEmpty {
                SettingsDivider()
                SettingsHintRow(text: localization.string(.settingsBluetoothNearbyBLEEmpty))
            } else {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    SettingsDivider()
                    SettingsRow(
                        "apple.logo",
                        tint: .blue,
                        title: displayName(candidate)
                    ) {
                        HStack(spacing: 8) {
                            if candidate.trustRequired {
                                Text(localization.string(.settingsAppleDeviceTrustRequired))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if candidate.isSelectableAppleDevice {
                                Toggle("", isOn: selectionBinding(for: candidate))
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .labelsHidden()
                                    .accessibilityLabel(displayName(candidate))
                            }
                        }
                    }
                    .accessibilityIdentifier("appleDevice.selection.\(candidate.id.rowID)")
                    if index == candidates.count - 1, store.appleDeviceSelections.isEmpty {
                        SettingsDivider()
                        SettingsHintRow(text: localization.string(.settingsAppleDeviceSelectionRequired))
                    }
                }
            }
        }
        .task {
            discovery.request(Self.discoveryToken)
        }
        .task(id: bleConfiguration) {
            bluetooth.configureNearbyBLEDevices(
                enabled: store.showsAppleDevicesAndBattery,
                selectedIDs: Set(store.appleDeviceSelections.compactMap { id in
                    if case let .ble(uuid) = id.id { return uuid }
                    return nil
                }),
                hiddenIDs: Set(store.bluetoothDeviceListOptions.hiddenDeviceAddresses.compactMap {
                    BluetoothDeviceIdentity.bleUUID(from: $0)
                })
            )
            guard store.showsAppleDevicesAndBattery else {
                bluetooth.releaseNearbyBLEDiscovery(Self.discoveryToken)
                return
            }
            bluetooth.requestNearbyBLEDiscovery(Self.discoveryToken)
        }
        .onChange(of: bluetooth.nearbyBLECandidates) { _, values in
            store.updateNearbyBLECandidateMetadata(values)
        }
        .onChange(of: bluetooth.nearbyBatteryDevices) { _, values in
            store.updateNearbyBLEMetadata(values)
        }
        .onDisappear {
            discovery.release(Self.discoveryToken)
            bluetooth.releaseNearbyBLEDiscovery(Self.discoveryToken)
        }
    }

    private var bleConfiguration: String {
        "\(store.showsAppleDevicesAndBattery)-\(store.appleDeviceSelections.map { $0.id.rowID }.joined(separator: ","))"
    }

    private func displayName(_ candidate: AppleDeviceCandidate) -> String {
        let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(candidate.id.rowID.suffix(4))
        let count = candidates.filter { $0.name.caseInsensitiveCompare(candidate.name) == .orderedSame }.count
        if name.isEmpty { return "Apple device · \(suffix)" }
        return count > 1 ? "\(name) · \(suffix)" : name
    }

    private func selectionBinding(for candidate: AppleDeviceCandidate) -> Binding<Bool> {
        Binding(
            get: { store.appleDeviceSelections.contains { $0.id == candidate.id } },
            set: { store.setAppleDeviceSelected(candidate, selected: $0) }
        )
    }
}
