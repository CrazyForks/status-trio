# On-demand battery details

Expand **Battery Details** in the popover to view additional battery information.
Collection runs on a serial utility queue only while the details are visible,
refreshing every 15 seconds with 3 seconds of scheduling tolerance. Repeated
requests coalesce into one follow-up read. Closing the details discards outstanding
results and cancels the collector's refresh loop; it adds no permanent polling timer.
The store explicitly deactivates collection when the popover closes, even while
its hosting view is retained. Expired power is also removed on refresh requests
while an earlier read is blocked.
The existing battery icon monitoring is unchanged.

## Meaning and sources

- **Adapter rating** comes from `IOPSCopyExternalPowerAdapterDetails` and
  `kIOPSPowerAdapterWattsKey`. It is not measured charging power.
- **Time remaining** uses `IOPSGetTimeRemainingEstimate`, only on battery power.
  Unknown/unlimited estimates remain unavailable; private `TimeRemaining` values
  are deliberately not used as a fallback.
- **Low Power Mode** uses the existing `ProcessInfo`-backed battery status.
- **Battery power** is an estimate of net power entering/leaving the battery,
  computed from `Voltage` (mV) and signed `Amperage` (mA) from one
  `AppleSmartBattery` registry snapshot. It is not total Mac power consumption.
  Charging is labeled and green; normal discharge uses the default text color.
- **Voltage**, **current**, **sample time**, and **cycle count** are best-effort
  registry diagnostics. No battery health percentage is inferred from capacity
  ratios, and no `system_profiler`/`ioreg` subprocess is launched.

IORegistry access is a public API, but these specific registry properties are not
an Apple-supported cross-model data contract. Unsupported machines omit the
additional values. A sample is rejected if fields are missing/implausible,
its charge state disagrees with the current battery state, its timestamp is more
than 90 seconds old or over 5 seconds in the future, or it predates an observed
power-state transition. Zero current is treated as unavailable because it can be
a transitional reading. Negative 64-bit integer current is supported, including
unsigned NSNumber representations of the same bit pattern.

The hardware's sampling interval can be about a minute; the interface shows the
sample time rather than promising live per-second watts. Hardware validation so
far covers one Apple silicon Mac on battery. Charging transitions and other Mac
models still need field validation before making broad accuracy claims.

Apple references:
- [IOPSCopyExternalPowerAdapterDetails](https://developer.apple.com/documentation/iokit/1523866-iopscopyexternalpoweradapterdeta)
- [IOPSGetTimeRemainingEstimate](https://developer.apple.com/documentation/iokit/iopsgettimeremainingestimate())
- [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
