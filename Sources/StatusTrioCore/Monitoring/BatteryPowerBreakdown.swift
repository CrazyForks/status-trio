import Foundation

/// The adapter budget split into the branches the Mac can measure itself.
///
/// Only produced when the readings share one measurement window and the
/// residual stays physically plausible. A breakdown that cannot be computed
/// honestly is `nil`, and the panel keeps the legacy input/battery/system
/// diagram instead of relabelling the system total as "other".
struct BatteryPowerBreakdown: Equatable, Sendable {
    struct Component: Equatable, Sendable {
        let watts: Double
        let readAt: Date
    }

    let inputWatts: Double
    /// Built-in display backlight (`PDBR`). Nil when this Mac does not expose it.
    let display: Component?
    /// Chip package power (`PHPC`).
    let soc: Component
    /// Power sourced to accessories over USB / Thunderbolt.
    let usb: Component?
    /// What is left of the adapter input after the measured branches.
    let other: Component
    let readAt: Date

    var components: [Component] { [display, usb, soc, other].compactMap { $0 } }

    /// Residual tolerance: sensor rails are sampled by one overall refresh but
    /// the SMC updates each rail on its own cadence, so a rail can be one tick
    /// ahead of the adapter total. Small negatives are rounding, not a
    /// measurement that justifies a fake branch.
    static let residualTolerance = 0.75

    static func resolve(
        input: SystemPowerSample?,
        charging: Double?,
        display: SystemPowerSample?,
        soc: SystemPowerSample?,
        usb: USBOutputSample?,
        now: Date = Date()
    ) -> BatteryPowerBreakdown? {
        // The adapter total is the branch's own numerator, so an unknown input
        // has no budget to split. Unknown charge is enough to make the residual
        // wrong, and the chip rail is the anchor every other branch depends on.
        guard let input, input.isFresh(at: now), input.watts > 0 else { return nil }
        guard let soc, soc.isFresh(at: now), soc.watts >= 0 else { return nil }
        guard let charging, charging.isFinite, charging >= 0 else { return nil }
        if let display, !display.isFresh(at: now) { return nil }
        if let usb, !usb.isFresh(at: now) { return nil }

        let displayWatts = display?.watts ?? 0
        let usbWatts = usb?.watts ?? 0
        let residual = input.watts - charging - displayWatts - soc.watts - usbWatts
        if residual < -residualTolerance { return nil }
        let other = max(0, residual)
        return BatteryPowerBreakdown(
            inputWatts: input.watts,
            display: display.map { Component(watts: $0.watts, readAt: $0.readAt) },
            soc: Component(watts: soc.watts, readAt: soc.readAt),
            usb: usb.map { Component(watts: $0.watts, readAt: $0.readAt) },
            other: Component(watts: other, readAt: input.readAt),
            readAt: input.readAt
        )
    }
}
