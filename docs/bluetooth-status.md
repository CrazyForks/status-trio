# Bluetooth popover summary

The popover's Bluetooth row reports live device state instead of a generic
prompt. What it shows is derived by `BluetoothSummary.presentation(availability:
devices:batteryLevels:)`, so the text is testable without rendering SwiftUI:

| Availability | Row |
| --- | --- |
| `authorizationNotDetermined` | A tappable **Allow Bluetooth to show device status** action |
| `idle`, `initializing` | Initializing Bluetooth… |
| `available` | The connected device names, joined with `、` |
| `available`, nothing connected | No connected devices |
| `poweredOff`, `unavailable`, `failed` | Their own existing messages |
| `authorizationDenied`, `authorizationRestricted` | Their own existing messages |

Device names are joined with the ideographic comma `、`. A connected battery
reading is joined to its device with the existing ` · ` separator, so the level
reads as a property of that device rather than another entry in the list:
`AirPods Pro · L 80% · R 75% · Case 60%、MX Master 3`.

## Device names come from the system profiler

The paired-device list, including each device's name, is read from
`system_profiler SPBluetoothDataType` — the same report the battery levels come
from. `IOBluetoothDevice.nameOrAddress` is deliberately not used: it returns a
cached name that kept reporting the old value after the device was renamed in
System Settings, so a renamed AirPods stayed on its previous name indefinitely.
The profiler reports what the system currently uses. Reading it takes well under
a second and reuses the existing refresh cadence, so it adds no timer.

The parser separates "the report could not be read" (a read failure) from "the
machine has no paired devices" (an empty list), so a malformed report is never
displayed as an empty device list. It accepts the profiler's wrapped
`SPBluetoothDataType` list and a bare section, and reads the device kind from
`device_minorType` with `device_majorType` as the fallback, because the major
type alone classifies every headphone, speaker, and wearable alike. Unknown
wording stays generic rather than being guessed as audio, which would make the
device eligible for a battery level.

## AirPods only

Only connected AirPods report a battery level. The rule is
`kind == .audio && name contains "airpods"` (`BluetoothDevice.isAirPods`); the
audio class alone would also match speakers and other headphones, and macOS
exposes no reliable model table for registry product IDs. Every other connected
accessory stays name-only — its detail belongs on the device page.

Battery levels come from the same `system_profiler SPBluetoothDataType` report.
Two surfaces share that read — the summary row (for the AirPods it reports) and
the detail page (for every device) — so the controller tracks them as *claims*
keyed by token rather than one boolean. SwiftUI may run the outgoing surface's
disappear hook either before or after the incoming surface's appear hook, and a
boolean let the last writer win: leaving the summary switched the read off right
after the detail page had asked for it, so every device row showed "Unavailable"
while the summary still showed the level it had just read. A claim count makes
the outcome the same in either order; the read runs while any claim is held and
stops when the last is released. The summary claims only while the setting is on
and a connected AirPods is present — the name is the gate, not the presence of a
readable level, so a just-connected AirPods still triggers the first read. The
detail page claims from the setting alone. Closing the popover drops every claim.

## Activation and permission

Reading the paired-device database needs no CoreBluetooth grant, but starting
the state monitor is what raises the system prompt. So
`BluetoothPanelActivation.shouldActivate(authorization:)` allows the popover to
activate the monitor on its own only when the grant is already `allowed`, which
refreshes the names the row reports. Every other grant state is only observed.

The popover re-evaluates this on each open, which is what replaced the previous
"open details to view device status" placeholder: the monitor is enabled by an
in-memory flag that a fresh launch does not restore, so the row used to start on
that placeholder every time. Permission is still only requested by the user's
tap, never by the popover appearing; that contract is covered by
`BluetoothPermissionTimingTests`.
