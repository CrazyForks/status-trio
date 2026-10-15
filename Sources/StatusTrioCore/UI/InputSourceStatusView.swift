import AppKit
import SwiftUI

/// The status panel's input-source section.
struct InputSourceStatusView: View {
    @EnvironmentObject private var localization: Localization

    let state: InputSourcePanelState
    let onSelect: (String) -> Void
    let onOpenKeyboardSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let emptyMessage = state.emptyMessage {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                rows
            }

            if let failure = state.failureText {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(state.currentName ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(state.currentName ?? "")
                    .accessibilityHidden(state.currentName == nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onOpenKeyboardSettings) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(state.openSettingsLabel)
            .accessibilityLabel(state.openSettingsLabel)
            .frame(width: 24, height: 24)
        }
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(state.rows, id: \.id) { row in
                Button {
                    onSelect(row.id)
                } label: {
                    HStack(spacing: 8) {
                        rowMarker(row)
                            .frame(width: 20, height: 16)
                            .accessibilityHidden(true)

                        Text(row.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(row.name)

                        Spacer(minLength: 0)

                        if row.isCurrent {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.name)
                .accessibilityAddTraits(row.isCurrent ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func rowMarker(_ row: InputSourcePanelState.Row) -> some View {
        if let iconURL = row.iconURL,
           let image = IconImageDecodeCache.shared.decodedImage(for: iconURL) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else if let marker = row.marker {
            Text(marker)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "keyboard")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
