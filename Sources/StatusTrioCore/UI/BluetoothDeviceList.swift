import SwiftUI

/// The Bluetooth device list shown under the status row. Paired, trusted-mobile,
/// and selected BLE rows share one order, limit, expansion control, and viewport.
/// Only actionable paired rows connect or disconnect; external reading rows stay
/// read-only.
struct BluetoothDeviceList: View {
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let devices: [BluetoothDevice]
    let batteryLevels: [String: BluetoothBatteryLevel]
    var mobileMetadataByDeviceID: [String: MobileBatterySnapshot] = [:]
    var nearbyRows: [NearbyBLEPanelRow] = []
    var onVisibleNearbyIDsChanged: (Set<UUID>) -> Void = { _ in }
    let actionStates: [String: BluetoothDeviceActionState]
    /// The device whose disconnect is waiting for confirmation, by normalized
    /// address. The controller owns it so that closing the panel cancels it even
    /// though the popover keeps this view alive.
    let confirmingAddress: String?
    let options: BluetoothDeviceListOptions
    let onPerformAction: (BluetoothDevice) -> Void
    let onRequestDisconnect: (BluetoothDevice) -> Void
    let onCancelDisconnect: () -> Void

    @State private var isExpanded = false
    @State private var nearbyRowFrames: [UUID: CGRect] = [:]
    @State private var rowsViewportFrame = CGRect.zero
    @State private var reportedNearbyIDs = Set<UUID>()

    private static let geometryCoordinateSpace = "BluetoothDeviceList"

    /// How tall the rows may grow before they scroll, matching the Wi-Fi list's
    /// own bound so the two lists in the panel stop at the same place.
    static let maximumRowsHeight: CGFloat = 330

    /// The gap between two rows. The rows themselves are not all one height — an
    /// inline row is a single line and a component row adds a second for its
    /// levels — so the list can no longer multiply a fixed pitch by the device
    /// count. `estimatedContentHeight` adds each row's own height up instead.
    private static let rowSpacing: CGFloat = 2

    var body: some View {
        let model = BluetoothDeviceListModel.make(
            devices: devices,
            nearbyRows: nearbyRows,
            order: options.order,
            limit: options.maxVisibleDevices,
            isExpanded: isExpanded,
            options: options
        )

        VStack(spacing: Self.rowSpacing) {
            rows(model.visibleDevices)

            // Deliberately outside the scroll region: collapsing a long list must
            // not require scrolling to the bottom first.
            if model.canToggleExpansion {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))

                        Text(
                            localization.string(
                                isExpanded ? .bluetoothListCollapse : .bluetoothListExpand
                            )
                        )
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
        .coordinateSpace(name: Self.geometryCoordinateSpace)
        .onPreferenceChange(BluetoothDeviceListRowFramesPreferenceKey.self) { frames in
            nearbyRowFrames = frames
            publishVisibleNearbyIDs(in: model.visibleDevices)
        }
        .onPreferenceChange(BluetoothDeviceListViewportPreferenceKey.self) { frame in
            rowsViewportFrame = frame
            publishVisibleNearbyIDs(in: model.visibleDevices)
        }
        .onChange(of: model.visibleDevices) { _, visibleDevices in
            publishVisibleNearbyIDs(in: visibleDevices)
        }
        .onChange(of: nearbyRows) { _, _ in
            publishVisibleNearbyIDs(in: model.visibleDevices)
        }
        .onChange(of: options) { _, _ in
            publishVisibleNearbyIDs(in: model.visibleDevices)
        }
        .onDisappear { reportVisibleNearbyIDs([]) }
    }

    /// The rows, bounded.
    ///
    /// The scroll view appears only once the rows outgrow the panel. The summary
    /// popover has no scroll view of its own, so without a bound a long list — an
    /// expanded one, or a limit the user raised — would keep growing the popover
    /// past the screen. A scroll view that is not needed is not free either: its
    /// scroller flashes while an expansion animates through the moment where the
    /// content is taller than the shrinking frame, which a list of six devices
    /// should never show. Below the bound the rows are laid out directly, so
    /// there is nothing to flash. The panel's scroll-wheel handling already
    /// leaves a pointer over an `NSScrollView` to that view instead of adjusting
    /// the volume.
    @ViewBuilder
    private func rows(_ visibleDevices: [BluetoothDevice]) -> some View {
        if estimatedContentHeight(for: visibleDevices) > Self.maximumRowsHeight {
            ScrollView { rowStack(visibleDevices) }
                .frame(maxHeight: Self.maximumRowsHeight)
                .background(viewportFrameReader)
        } else {
            rowStack(visibleDevices)
                .background(viewportFrameReader)
        }
    }

    /// How tall the given rows come to: each row's own estimated height, plus the
    /// spacing between them. This is what decides whether the list scrolls, so a
    /// device set of component rows — taller than the count-based model assumed —
    /// reaches the bound at the right row, not several rows too late.
    private func estimatedContentHeight(for visibleDevices: [BluetoothDevice]) -> CGFloat {
        guard !visibleDevices.isEmpty else { return 0 }
        let rowHeights = visibleDevices.reduce(CGFloat(0)) { total, device in
            total + BluetoothDeviceRowMetrics.estimatedHeight(
                for: device,
                batteryLevels: batteryLevels,
                hasMobileDetails: mobileMetadataByDeviceID[device.id] != nil,
                hasNearbyDetails: nearbyRowByDeviceID[device.id] != nil
            )
        }
        return rowHeights + Self.rowSpacing * CGFloat(visibleDevices.count - 1)
    }

    private func rowStack(_ visibleDevices: [BluetoothDevice]) -> some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(visibleDevices) { device in
                let address = BluetoothBatteryReader.normalizedAddress(device.id)
                BluetoothDeviceRow(
                    device: device,
                    batteryLevels: batteryLevels,
                    mobileMetadataByDeviceID: mobileMetadataByDeviceID,
                    nearbyMetadataByDeviceID: nearbyRowByDeviceID,
                    actionState: actionStates[address],
                    isConfirmingDisconnect: confirmingAddress == address
                        && BluetoothDeviceActionPolicy.requiresConfirmation(for: device),
                    onPerformAction: { onPerformAction(device) },
                    onRequestDisconnect: { onRequestDisconnect(device) },
                    onCancelDisconnect: onCancelDisconnect
                )
                .background {
                    if let id = BluetoothDeviceIdentity.bleUUID(from: device.id), device.isReadOverTheAir {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: BluetoothDeviceListRowFramesPreferenceKey.self,
                                value: [id: proxy.frame(in: .named(Self.geometryCoordinateSpace))]
                            )
                        }
                    }
                }
            }
        }
    }

    private var nearbyRowByDeviceID: [String: NearbyBLEPanelRow] {
        Dictionary(nearbyRows.map { ($0.device.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    private var viewportFrameReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: BluetoothDeviceListViewportPreferenceKey.self,
                value: proxy.frame(in: .named(Self.geometryCoordinateSpace))
            )
        }
    }

    private func publishVisibleNearbyIDs(in visibleDevices: [BluetoothDevice]) {
        reportVisibleNearbyIDs(NearbyBLEPanelVisibility.visibleSelectedIDs(
            in: visibleDevices,
            frames: nearbyRowFrames,
            viewport: rowsViewportFrame
        ))
    }

    private func reportVisibleNearbyIDs(_ ids: Set<UUID>) {
        guard reportedNearbyIDs != ids else { return }
        reportedNearbyIDs = ids
        onVisibleNearbyIDsChanged(ids)
    }
}

private struct BluetoothDeviceListRowFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct BluetoothDeviceListViewportPreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        guard next.width > 0, next.height > 0 else { return }
        value = next
    }
}
