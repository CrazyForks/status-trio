import SwiftUI

/// A static flow diagram: sampling changes the numbers and ribbon widths, with
/// no animation clock, Canvas loop, or work while the panel is closed.
struct BatteryPowerFlowView: View {
    let state: BatteryPowerFlowState

    private var destinations: [BatteryPowerFlowState.Metric] { state.destinations }
    private var isCompact: Bool { destinations.count > 2 }
    private var nodeHeight: CGFloat { isCompact ? 44 : 60 }
    private var pitch: CGFloat { isCompact ? 50 : 70 }
    private var topPadding: CGFloat { isCompact ? 2 : 1 }
    /// Thickness of a ribbon carrying the whole budget. The compact diagram
    /// packs more branches into the same column, so each one gets less width.
    private var ribbonScale: CGFloat { isCompact ? 120 : 46 }

    private var height: CGFloat {
        switch destinations.count {
        case 0, 1: return 76
        case 2: return 132
        default: return topPadding * 2 + nodeHeight + CGFloat(destinations.count - 1) * pitch
        }
    }

    private func centerY(_ index: Int) -> CGFloat {
        destinations.count == 1 ? height / 2 : topPadding + nodeHeight / 2 + CGFloat(index) * pitch
    }

    private struct Ribbon: Identifiable {
        let id: Int
        let startY: CGFloat
        let endY: CGFloat
        let thickness: CGFloat
        let color: Color
    }

    /// Ribbons leave the input card stacked by their share of the budget, so
    /// five branches still read as one bundle instead of overlapping.
    private func ribbons(center: CGFloat) -> [Ribbon] {
        let fractions = destinations.map { state.flowFraction(for: $0).map { CGFloat($0) } }
        let requested = fractions.map { ($0 ?? 0) * ribbonScale }
        // Independent sensors can add up past the input; shrink the whole
        // bundle instead of letting it spill outside the card.
        let available = height - 12
        let excess = requested.reduce(0, +)
        let scale = excess > available && excess > 0 ? available / excess : 1
        let thicknesses = requested.map { $0 * scale }
        var offset = center - min(available, excess) / 2
        return destinations.enumerated().map { index, metric in
            let thickness = thicknesses[index]
            defer { offset += thickness }
            return Ribbon(id: index, startY: offset + thickness / 2,
                          endY: centerY(index), thickness: thickness,
                          color: Self.color(for: metric.kind))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let left: CGFloat = state.input == nil ? 0 : 66
            let right = width - 98
            let center = height / 2
            if state.input != nil, !destinations.isEmpty {
                ForEach(ribbons(center: center)) { item in
                    ribbon(from: left, to: right, startY: item.startY, endY: item.endY,
                           thickness: item.thickness, color: item.color)
                }
            }
            if let input = state.input {
                metric(input, symbol: "powerplug.fill", color: .primary, height: height - 8)
                    .frame(width: destinations.isEmpty ? width : 62)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                    .position(x: destinations.isEmpty ? width / 2 : 31, y: center)
            }
            ForEach(Array(destinations.enumerated()), id: \.offset) { index, item in
                metric(item, symbol: Self.symbol(for: item.kind),
                       color: Self.color(for: item.kind), height: nodeHeight)
                    .frame(width: state.input == nil ? width : 94)
                    .background(Self.color(for: item.kind).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .position(x: state.input == nil ? width / 2 : width - 47, y: centerY(index))
            }
        }
        .frame(height: height)
    }

    private static func symbol(for kind: BatteryPowerFlowState.Kind) -> String {
        switch kind {
        case .charging: return "battery.100.bolt"
        case .display: return "display"
        case .usb: return "cable.connector"
        case .soc: return "cpu"
        case .other: return "ellipsis"
        case .system: return "laptopcomputer"
        }
    }

    private static func color(for kind: BatteryPowerFlowState.Kind) -> Color {
        switch kind {
        case .charging: return .green
        case .display: return .indigo
        case .usb: return .orange
        case .soc: return .blue
        case .other: return .gray
        case .system: return .blue
        }
    }

    private func metric(_ value: BatteryPowerFlowState.Metric, symbol: String,
                        color: Color, height: CGFloat) -> some View {
        VStack(spacing: isCompact ? 1 : 3) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .imageScale(isCompact ? .small : .medium)
                .accessibilityHidden(true)
            Text(value.value)
                .font(.system(size: isCompact ? 12 : 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value.label)
                .font(.system(size: isCompact ? 9 : 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 3)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.label + ": " + value.value)
    }

    private func ribbon(from start: CGFloat, to end: CGFloat, startY: CGFloat,
                        endY: CGFloat, thickness: CGFloat?, color: Color) -> some View {
        let thickness = max(0, thickness ?? 0)
        return Path { path in
            let control = (end - start) * 0.5
            path.move(to: CGPoint(x: start, y: startY - thickness / 2))
            path.addCurve(to: CGPoint(x: end, y: endY - thickness / 2),
                control1: CGPoint(x: start + control, y: startY - thickness / 2),
                control2: CGPoint(x: end - control, y: endY - thickness / 2))
            path.addLine(to: CGPoint(x: end, y: endY + thickness / 2))
            path.addCurve(to: CGPoint(x: start, y: startY + thickness / 2),
                control1: CGPoint(x: end - control, y: endY + thickness / 2),
                control2: CGPoint(x: start + control, y: startY + thickness / 2))
            path.closeSubpath()
        }
        .fill(LinearGradient(colors: [color.opacity(0.08), color.opacity(0.3)],
            startPoint: .leading, endPoint: .trailing))
        .accessibilityHidden(true)
    }
}
