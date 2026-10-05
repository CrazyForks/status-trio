import SwiftUI

struct NearbyBluetoothBatteryRows: View {
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let rows: [NearbyBLEPanelRow]
    let options: BluetoothDeviceListOptions
    let onVisibleIDsChanged: (Set<UUID>) -> Void

    static let maximumRowsHeight: CGFloat = 168
    private static let rowSpacing: CGFloat = 2
    private static let coordinateSpace = "nearbyBLEBatteryRows"

    @State private var isExpanded = false
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var viewportFrame = CGRect.zero
    @State private var reportedIDs = Set<UUID>()

    private var eligibleIDs: Set<UUID> {
        NearbyBLEPanelVisibility.eligibleIDs(
            rows: rows,
            showsList: options.showsList,
            limit: options.maxVisibleDevices,
            expanded: isExpanded
        )
    }

    var body: some View {
        VStack(spacing: Self.rowSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    ForEach(visibleRows) { row in
                        rowView(row)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: NearbyBLERowFramesPreferenceKey.self,
                                        value: [row.id: proxy.frame(in: .named(Self.coordinateSpace))]
                                    )
                                }
                            }
                    }
                }
            }
            .frame(maxHeight: Self.maximumRowsHeight)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: NearbyBLEViewportPreferenceKey.self,
                        value: proxy.frame(in: .named(Self.coordinateSpace))
                    )
                }
            }

            if options.maxVisibleDevices > 0, rows.count > options.maxVisibleDevices {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        Text(localization.string(isExpanded ? .bluetoothListCollapse : .bluetoothListExpand))
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .onPreferenceChange(NearbyBLERowFramesPreferenceKey.self) { rowFrames = $0; publishVisibleIDs() }
        .onPreferenceChange(NearbyBLEViewportPreferenceKey.self) { viewportFrame = $0; publishVisibleIDs() }
        .onChange(of: rows) { _, _ in publishVisibleIDs() }
        .onChange(of: options) { _, _ in publishVisibleIDs() }
        .onDisappear { report([]) }
    }

    private var visibleRows: [NearbyBLEPanelRow] {
        isExpanded ? rows : Array(rows.prefix(max(0, options.maxVisibleDevices)))
    }

    @ViewBuilder
    private func rowView(_ row: NearbyBLEPanelRow) -> some View {
        let trimmedName = row.device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty
            ? localization.string(.bluetoothNearbyDeviceFallback)
            : trimmedName
        let status: String = if let level = row.batteryLevel {
            "\(level)%"
        } else if row.readFailed {
            localization.string(.bluetoothNearbyBLEUnavailable)
        } else if !row.wasSeenRecently {
            localization.string(.bluetoothNearbyBLENotNearby)
        } else {
            "—"
        }

        HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .frame(width: BluetoothPanelMetrics.iconColumnWidth, height: BluetoothPanelMetrics.iconColumnWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(localization.string(.bluetoothNearbyBLESource))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(status)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(row.batteryLevel.map {
            localization.format(.batteryAccessibilityValue, $0)
        } ?? (row.readFailed
            ? localization.string(.bluetoothNearbyBLEUnavailable)
            : localization.string(.bluetoothNearbyBLENotNearby)))
    }

    private func publishVisibleIDs() {
        let intersecting = NearbyBLEPanelVisibility.intersectingIDs(frames: rowFrames, viewport: viewportFrame)
        report(eligibleIDs.intersection(intersecting))
    }

    private func report(_ ids: Set<UUID>) {
        guard reportedIDs != ids else { return }
        reportedIDs = ids
        onVisibleIDsChanged(ids)
    }
}

private struct NearbyBLERowFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct NearbyBLEViewportPreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
