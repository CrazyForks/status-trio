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

## AirPods only

Only connected AirPods report a battery level. The rule is
`kind == .audio && name contains "airpods"` (`BluetoothDevice.isAirPods`); the
audio class alone would also match speakers and other headphones, and macOS
exposes no reliable model table for registry product IDs. Every other connected
accessory stays name-only — its detail belongs on the device page.

Battery levels come from the existing `system_profiler SPBluetoothDataType`
reader, which is a subprocess. The summary therefore enables the reader only
when a connected AirPods is present and the **Show Bluetooth battery levels**
setting is on. The name is the gate, not the presence of a readable level, so a
just-connected AirPods still triggers the first read.

## Activation and permission

Reading the paired-device database through IOBluetooth needs no CoreBluetooth
grant, but starting the state monitor is what raises the system prompt. So
`BluetoothPanelActivation.shouldActivate(authorization:)` allows the popover to
activate the monitor on its own only when the grant is already `allowed`, which
refreshes the names the row reports. Every other grant state is only observed.

The popover re-evaluates this on each open, which is what replaced the previous
"open details to view device status" placeholder: the monitor is enabled by an
in-memory flag that a fresh launch does not restore, so the row used to start on
that placeholder every time. Permission is still only requested by the user's
tap, never by the popover appearing; that contract is covered by
`BluetoothPermissionTimingTests`.
