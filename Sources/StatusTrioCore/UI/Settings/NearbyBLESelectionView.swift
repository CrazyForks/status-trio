import SwiftUI

/// Discovers broadcast candidates in Settings. This surface never contributes
/// UUIDs to the panel's visible read permit.
struct NearbyBLESelectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var controller: BluetoothDeviceController
    @EnvironmentObject private var localization: Localization

    private static let discoveryToken = "bluetooth.settings.nearbyBLE"

    private struct Configuration: Equatable {
        let enabled: Bool
        let selectedIDs: Set<UUID>
        let hiddenIDs: Set<UUID>
    }

    private var configuration: Configuration {
        Configuration(
            enabled: store.showsNearbyBluetoothBatteryDevices,
            selectedIDs: Set(store.nearbyBLESelections.map(\.id)),
            hiddenIDs: Set(store.bluetoothDeviceListOptions.hiddenDeviceAddresses.compactMap {
                BluetoothDeviceIdentity.bleUUID(from: $0)
            })
        )
    }

    private var candidates: [NearbyBLEDeviceCandidate] {
        NearbyBLEDeviceCatalog.settingsCandidates(
            selections: store.nearbyBLESelections,
            candidates: controller.nearbyBLECandidates
        )
    }

    var body: some View {
        SettingsGroup(
            localization.string(.settingsBluetoothNearbyBLETitle),
            footnote: localization.string(.settingsBluetoothNearbyBLEDescription)
        ) {
            SettingsRow(title: localization.string(.settingsBluetoothNearbyBLETitle)) {
                Button {
                    controller.refreshNearbyBLEDiscovery(Self.discoveryToken)
                } label: {
                    HStack(spacing: 6) {
                        if controller.isDiscoveringNearbyBLEDevices {
                            ProgressView().controlSize(.small)
                            Text(localization.string(.settingsBluetoothNearbyBLEScanning))
                        } else {
                            Image(systemName: "arrow.clockwise")
                            Text(localization.string(.settingsBluetoothNearbyBLEScan))
                        }
                    }
                }
                .controlSize(.small)
                .disabled(controller.isDiscoveringNearbyBLEDevices)
            }

            if controller.isDiscoveringNearbyBLEDevices {
                SettingsDivider()
                SettingsHintRow(text: localization.string(.settingsBluetoothNearbyBLEScanning))
            }

            if candidates.isEmpty {
                SettingsDivider()
                SettingsHintRow(text: localization.string(.settingsBluetoothNearbyBLEEmpty))
            } else {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    SettingsDivider()
                    SettingsRow(
                        "dot.radiowaves.left.and.right",
                        tint: .blue,
                        title: displayName(candidate)
                    ) {
                        Toggle("", isOn: selectionBinding(for: candidate))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .accessibilityLabel(displayName(candidate))
                    }
                    .accessibilityIdentifier("nearbyBLE.selection.\(candidate.id.uuidString)")
                    if index == candidates.count - 1, store.nearbyBLESelections.isEmpty {
                        SettingsDivider()
                        SettingsHintRow(text: localization.string(.settingsBluetoothNearbyBLENoneSelected))
                    }
                }
            }
        }
        .task(id: configuration) {
            controller.configureNearbyBLEDevices(
                enabled: configuration.enabled,
                selectedIDs: configuration.selectedIDs,
                hiddenIDs: configuration.hiddenIDs
            )
            guard configuration.enabled else {
                controller.releaseNearbyBLEDiscovery(Self.discoveryToken)
                return
            }
            controller.requestNearbyBLEDiscovery(Self.discoveryToken)
        }
        .onChange(of: controller.nearbyBLECandidates) { _, updated in
            store.updateNearbyBLECandidateMetadata(updated)
        }
        .onChange(of: controller.nearbyBatteryDevices) { _, updated in
            store.updateNearbyBLEMetadata(updated)
        }
        .onDisappear {
            controller.releaseNearbyBLEDiscovery(Self.discoveryToken)
        }
    }

    private func displayName(_ candidate: NearbyBLEDeviceCandidate) -> String {
        let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? localization.string(.bluetoothNearbyDeviceFallback) : name
    }

    private func selectionBinding(for candidate: NearbyBLEDeviceCandidate) -> Binding<Bool> {
        Binding(
            get: { store.nearbyBLESelections.contains { $0.id == candidate.id } },
            set: { store.setNearbyBLEDeviceSelected(candidate, selected: $0) }
        )
    }
}
