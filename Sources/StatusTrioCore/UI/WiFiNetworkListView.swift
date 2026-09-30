import SwiftUI

struct WiFiNetworkListView: View {
    @EnvironmentObject private var localization: Localization
    let state: WiFiPanelState
    let onBack: () -> Void
    let onRequestNameAccess: () -> Void
    let onOpenWiFiSettings: () -> Void
    let onOpenLocationSettings: () -> Void
    let onSetPower: (Bool) -> Void
    let onRefresh: () -> Void
    let onCopyValue: (String) -> Void
    let showsDetailsInitially: Bool

    @State private var showsDetails = false
    @State private var showsMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Toggle(
                localization.string(.wifiPower),
                isOn: Binding(get: { state.powerIsOn }, set: { onSetPower($0) })
            )
            .disabled(!state.canSetPower)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    knownNetworksSection
                    otherNetworksSection
                    stateMessage
                }
            }
            .frame(maxHeight: 330)

            Divider()
            Text(localization.string(.wifiActionSwitchingHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(localization.string(.wifiActionOpenSettings), action: onOpenWiFiSettings)
                .buttonStyle(.plain)
                .accessibilityLabel(localization.string(.wifiActionOpenSettings))
        }
        .onAppear {
            showsDetails = showsDetails || showsDetailsInitially
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            NavigationBackRow(
                accessibilityLabel: localization.string(.commonBack),
                title: localization.string(.wifiTitle),
                action: onBack
            )
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(!state.canRefresh)
            .accessibilityLabel(localization.string(.wifiRefresh))
        }
    }

    @ViewBuilder
    private var knownNetworksSection: some View {
        if !state.knownRows.isEmpty || state.showsConnectionDetails {
            Text(localization.string(.wifiKnownNetworks))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(state.knownRows, id: \.key) { row in networkRow(row) }

            if state.showsConnectionDetails {
                WiFiDetailsToggleRow(isExpanded: $showsDetails)

                if showsDetails {
                    WiFiDetailsView(
                        state: state,
                        showsMore: $showsMore,
                        onCopyValue: onCopyValue
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var otherNetworksSection: some View {
        if !state.otherRows.isEmpty {
            Text(localization.string(.wifiOtherNetworks))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(state.otherRows, id: \.key) { row in networkRow(row) }
        }
    }

    @ViewBuilder
    private var stateMessage: some View {
        if let message = state.message {
            switch state.messageIntent {
            case .requestWiFiNameAccess:
                Button(message, action: onRequestNameAccess)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .locationSettings:
                Button(message, action: onOpenLocationSettings)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                HStack(spacing: 8) {
                    if state.isScanning { ProgressView().controlSize(.small) }
                    Text(message)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func networkRow(_ row: PanelWiFiNetworkRow) -> some View {
        Button {
            if row.opensSettings { onOpenWiFiSettings() }
        } label: {
            HStack(spacing: 10) {
                if row.selected {
                    Image(systemName: "checkmark")
                        .frame(width: 16)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "wifi")
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                }
                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if let marker = row.securityMarker {
                    Image(systemName: marker)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                PanelSymbolView(source: row.signalSymbol, size: 14, weight: .regular)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!row.opensSettings)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

private struct WiFiDetailsView: View {
    let state: WiFiPanelState
    @Binding var showsMore: Bool
    let onCopyValue: (String) -> Void

    var body: some View {
        VStack(spacing: 5) {
            PanelDetailRowsView(
                detailRows: state.visibleDetailRows(expanded: showsMore),
                onCopyValue: onCopyValue
            )
            Button(showsMore ? state.showLessTitle : state.showMoreTitle) {
                showsMore.toggle()
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 26)
        .font(.caption)
    }
}
