import SwiftUI

struct BasicsSettingsPane: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var localization: Localization
    @ObservedObject private var launchAtLogin: LaunchAtLoginManager

    init(
        store: SettingsStore,
        localization: Localization,
        launchAtLogin: LaunchAtLoginManager = .shared
    ) {
        self.store = store
        self.localization = localization
        self._launchAtLogin = ObservedObject(wrappedValue: launchAtLogin)
    }

    var body: some View {
        PreferencesPane {
            launchAtLoginSection

            Divider()

            appIconPlacementSection

            Divider()

            dockIconBackgroundSection

            Divider()

            PreferenceRow(
                label: .settingsLanguage,
                description: .settingsLanguageDescription,
                placesControlInline: true
            ) {
                Picker(
                    localization.string(.settingsLanguage),
                    selection: Binding(
                        get: { localization.preference },
                        set: { newPreference in
                            localization.setPreference(newPreference)
                        }
                    )
                ) {
                    Text(localization.string(.settingsLanguageFollowSystem))
                        .tag(LanguagePreference.system)

                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName)
                            .tag(LanguagePreference.language(language))
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            Divider()

            refreshIntervalSection

            Divider()

            popupOrderSection
        }
    }

    private var refreshIntervalSection: some View {
        PreferenceRow(
            label: .settingsRefreshInterval,
            description: .settingsRefreshIntervalDescription
        ) {
            HStack(spacing: 12) {
                Slider(
                    value: $store.refreshIntervalSeconds,
                    in: SettingsStore.refreshIntervalRange,
                    step: 5
                )
                .accessibilityLabel(localization.string(.settingsRefreshInterval))
                .accessibilityValue(
                    localization.format(
                        .settingsRefreshIntervalValue,
                        Int(store.refreshIntervalSeconds)
                    )
                )

                Text(
                    localization.format(
                        .settingsRefreshIntervalValue,
                        Int(store.refreshIntervalSeconds)
                    )
                )
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .trailing)
            }
        }
    }

    private var appIconPlacementSection: some View {
        PreferenceRow(
            label: .settingsAppIconPlacement,
            description: .settingsAppIconPlacementDescription
        ) {
            Picker(
                localization.string(.settingsAppIconPlacement),
                selection: $store.appIconPlacement
            ) {
                Text(localization.string(.settingsAppIconPlacementMenuBar))
                    .tag(AppIconPlacement.menuBar)
                Text(localization.string(.settingsAppIconPlacementDock))
                    .tag(AppIconPlacement.dock)
                Text(localization.string(.settingsAppIconPlacementBoth))
                    .tag(AppIconPlacement.both)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }

    private var dockIconBackgroundSection: some View {
        PreferenceRow(
            label: .settingsDockIconBackground,
            description: .settingsDockIconBackgroundDescription
        ) {
            Picker(
                localization.string(.settingsDockIconBackground),
                selection: $store.dockIconBackgroundPreference
            ) {
                Text(localization.string(.settingsDockIconBackgroundSystem))
                    .tag(DockIconBackgroundPreference.system)
                Text(localization.string(.settingsDockIconBackgroundDark))
                    .tag(DockIconBackgroundPreference.dark)
                Text(localization.string(.settingsDockIconBackgroundLight))
                    .tag(DockIconBackgroundPreference.light)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }

    private var popupOrderSection: some View {
        PreferenceRow(
            label: .settingsPopupOrder,
            description: .settingsPopupOrderDescription
        ) {
            List {
                ForEach(store.popupSectionOrder) { section in
                    HStack(spacing: 8) {
                        popupSectionIcon(section)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        Text(localization.string(section.titleKey))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "line.3.horizontal")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { source, destination in
                    store.movePopupSections(
                        fromOffsets: source,
                        toOffset: destination
                    )
                }
            }
            .listStyle(.inset)
            .frame(height: popupOrderListHeight)
        }
    }

    @ViewBuilder
    private func popupSectionIcon(_ section: PopupSection) -> some View {
        if section == .bluetooth {
            BluetoothIcon(size: 18)
        } else {
            Image(systemName: section.systemImage)
        }
    }

    private var popupOrderListHeight: CGFloat {
        min(max(CGFloat(store.popupSectionOrder.count) * 28 + 8, 44), 168)
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PreferenceCheckboxRow(
                label: .settingsLaunchAtLogin,
                description: .settingsLaunchAtLoginDescription,
                isOn: launchAtLogin.isEnabledBinding
            )
            .disabled(!launchAtLogin.isAvailable)

            if launchAtLogin.status == .requiresApproval {
                notice(
                    .settingsLaunchAtLoginRequiresApproval,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )

                Button(localization.string(.settingsLaunchAtLoginOpenLoginItems)) {
                    launchAtLogin.openLoginItemsSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.leading, 18)
            }

            if launchAtLogin.didFailLastOperation {
                notice(
                    .settingsLaunchAtLoginFailure,
                    systemImage: "exclamationmark.octagon.fill",
                    tint: .red
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The user may change the login item in System Settings while we're not
        // looking, so re-read the system state whenever the pane appears.
        .onAppear { launchAtLogin.refresh() }
    }

    private func notice(
        _ key: LocalizationKey,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)

            Text(localization.string(key))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
