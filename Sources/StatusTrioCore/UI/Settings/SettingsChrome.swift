import AppKit
import SwiftUI

/// Standard metrics matching macOS System Settings and Reff Mac App design language.
enum SettingsMetrics {
    static let groupSpacing: CGFloat = 20
    static let cardCorner: CGFloat = 10
    static let rowPaddingH: CGFloat = 14
    static let rowPaddingV: CGFloat = 10
    /// Standard icon size matching System Settings.
    static let iconSize: CGFloat = 26
    static let iconCorner: CGFloat = 6.5
    /// Where a divider starts, clearing the icon column.
    static let dividerInset: CGFloat = rowPaddingH + iconSize + 12
}

/// A titled, rounded card group for settings rows.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    var footnote: String? = nil
    @ViewBuilder let content: Content

    init(
        _ title: String? = nil,
        footnote: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
                    .padding(.top, 1)
            }
        }
    }
}

/// The rounded, tinted squircle icon that carries a row's symbol, matching System Settings.
struct SettingsIcon: View {
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        RoundedRectangle(cornerRadius: SettingsMetrics.iconCorner, style: .continuous)
            .fill(tint.gradient)
            .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: SettingsMetrics.iconSize * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// A standardized setting row with an icon, title, optional description, and control.
struct SettingsRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading
                .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
    }
}

extension SettingsRow where Leading == SettingsIcon {
    init(
        _ symbol: String,
        tint: Color = .accentColor,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: { SettingsIcon(symbol: symbol, tint: tint) },
            trailing: trailing
        )
    }
}

extension SettingsRow where Leading == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: { EmptyView() },
            trailing: trailing
        )
    }
}

/// A convenient row with an SF symbol, title, and a switch toggle.
struct SettingsToggleRow: View {
    let symbol: String
    var tint: Color = .accentColor
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(symbol, tint: tint, title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

/// A row whose choice is made from a pop-up menu on the right.
struct SettingsMenuRow<T: Hashable & Identifiable>: View {
    var symbol: String? = nil
    var tint: Color = .accentColor
    let title: String
    var subtitle: String? = nil
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    var body: some View {
        SettingsRow(
            title: title,
            subtitle: subtitle,
            leading: {
                if let symbol {
                    SettingsIcon(symbol: symbol, tint: tint)
                }
            },
            trailing: {
                Picker("", selection: $selection) {
                    ForEach(options) { option in
                        Text(label(option)).tag(option)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        )
    }
}

/// Extension for concentric Apple-style selection rings around preview cards.
extension View {
    /// Concentric with the picture card: the ring's inner corner is the card's
    /// own corner plus the gap, matching macOS System Settings Appearance selection ring.
    ///
    /// Keyboard focus is deliberately left to the system focus effect: the option
    /// buttons are focusable but no longer disable it, so this ring communicates
    /// selection and is never the only indicator of where focus is.
    func selectionRing(
        _ isOn: Bool,
        cornerRadius: CGFloat = 6,
        style: RoundedCornerStyle = .continuous
    ) -> some View {
        let gap: CGFloat = 2.5
        let width: CGFloat = 2.5
        return padding(gap + width)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius + gap + width, style: style)
                    .strokeBorder(isOn ? Color.accentColor : Color.clear, lineWidth: width)
            )
    }
}

/// A row whose choices are visual preview cards matching macOS System Settings Appearance and Icon style pickers.
struct SettingsPictureRow<T: Hashable & Identifiable, Leading: View, Preview: View>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var selection: T
    let options: [T]
    var previewSize: CGSize = CGSize(width: 68, height: 44)
    @ViewBuilder var leading: Leading
    let caption: (T) -> String
    @ViewBuilder let preview: (T) -> Preview

    @FocusState private var focusedOption: T?
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if !(Leading.self == EmptyView.self) {
                    leading
                        .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                HStack(alignment: .top, spacing: 10) {
                    ForEach(options) { option in
                        let isSelected = selection == option
                        Button {
                            selectOption(option)
                        } label: {
                            VStack(spacing: 5) {
                                preview(option)
                                    .frame(width: previewSize.width, height: previewSize.height)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                    )
                                    .selectionRing(isSelected, cornerRadius: 6)

                                // The caption is capped to the card width and may
                                // wrap to two lines, so a long translation cannot
                                // stretch the row or push the cards out of the group.
                                Text(caption(option))
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(width: previewSize.width)
                            }
                        }
                        .buttonStyle(.plain)
                        .focusable()
                        .focused($focusedOption, equals: option)
                        .onKeyPress(.leftArrow) {
                            selectRelative(offset: backwardStep)
                            return .handled
                        }
                        .onKeyPress(.rightArrow) {
                            selectRelative(offset: forwardStep)
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            selectRelative(offset: -1)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            selectRelative(offset: 1)
                            return .handled
                        }
                        .onKeyPress(.space) {
                            selectOption(option)
                            return .handled
                        }
                        .onKeyPress(.return) {
                            selectOption(option)
                            return .handled
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(caption(option))
                        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
            }
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
    }

    /// Left and right follow the reading direction: the option row mirrors in a
    /// right-to-left layout, so an unconditional -1/+1 would move the selection
    /// the wrong way on screen in Arabic.
    private var backwardStep: Int { layoutDirection == .rightToLeft ? 1 : -1 }
    private var forwardStep: Int { -backwardStep }

    private func selectOption(_ target: T) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            selection = target
            focusedOption = target
        }
    }

    /// Wraps at both ends so repeated presses keep cycling through the options.
    private func selectRelative(offset: Int) {
        guard !options.isEmpty else { return }
        let current = focusedOption ?? selection
        guard let currentIndex = options.firstIndex(of: current) else { return }
        let count = options.count
        let newIndex = ((currentIndex + offset) % count + count) % count
        selectOption(options[newIndex])
    }
}

extension SettingsPictureRow where Leading == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        selection: Binding<T>,
        options: [T],
        previewSize: CGSize = CGSize(width: 68, height: 44),
        caption: @escaping (T) -> String,
        @ViewBuilder preview: @escaping (T) -> Preview
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            selection: selection,
            options: options,
            previewSize: previewSize,
            leading: { EmptyView() },
            caption: caption,
            preview: preview
        )
    }
}

extension SettingsPictureRow where Leading == SettingsIcon {
    init(
        _ symbol: String,
        tint: Color = .accentColor,
        title: String,
        subtitle: String? = nil,
        selection: Binding<T>,
        options: [T],
        previewSize: CGSize = CGSize(width: 68, height: 44),
        caption: @escaping (T) -> String,
        @ViewBuilder preview: @escaping (T) -> Preview
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            selection: selection,
            options: options,
            previewSize: previewSize,
            leading: { SettingsIcon(symbol: symbol, tint: tint) },
            caption: caption,
            preview: preview
        )
    }
}


/// A full-width custom row, useful for sliders and embedded views.
struct SettingsCustomRow<Leading: View, Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(alignment: .center, spacing: 12) {
                    leading
                        .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .regular))
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            content
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
    }
}

extension SettingsCustomRow where Leading == SettingsIcon {
    init(
        _ symbol: String,
        tint: Color = .accentColor,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: { SettingsIcon(symbol: symbol, tint: tint) },
            content: content
        )
    }
}

extension SettingsCustomRow where Leading == EmptyView {
    init(
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: { EmptyView() },
            content: content
        )
    }
}

/// Inset divider between rows in a SettingsGroup card.
struct SettingsDivider: View {
    var inset: CGFloat = SettingsMetrics.dividerInset

    var body: some View {
        Divider()
            .opacity(0.4)
            .padding(.leading, inset)
    }
}

/// A scrolling page container with standard macOS settings padding and background.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
                content
            }
            .padding(EdgeInsets(top: 20, leading: 24, bottom: 24, trailing: 24))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Standard background material for sidebar views.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
