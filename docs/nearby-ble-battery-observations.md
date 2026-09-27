# Nearby BLE battery hardware observations

This document records device-level observations separately from code and
simulator tests. Hardware results must come from a short, explicit probe; an
empty scan is evidence only for the tested device and conditions.

## Environment and permission

- Observation date: 2026-09-27
- Host: macOS 27.0, build 26A428; Apple Silicon
- Xcode: 27.0, build 27A266a
- Swift: 6.4 (swiftlang-6.4.0.34.1)
- Bluetooth authorization: `.allowedAlways` before the probe.
- Baseline automated checks: `BluetoothPermissionTimingTests` (11 tests) and
  `BluetoothPollingLifetimeTests` (23 tests) passed before implementation.
- Probe: temporary CoreBluetooth diagnostic, one five-second `180F`-filtered
  scan. It matched only the two requested device categories in memory; raw
  advertised names and identifiers were not printed or retained.

## Device matrix

The mouse and keyboard were present in the host's paired-device inventory.
Neither was observed advertising `180F` during the single five-second probe.
No GATT connection was attempted, so the service table and `2A19` readability
remain untested. This is evidence only for that scan window, not proof that a
device never exposes the service.

| Device category | Radio / lock condition | Discovered with `180F` filter | GATT connected | `180F` found | `2A19` readable | Result |
| --- | --- | --- | --- | --- | --- | --- |
| HECATE G3M Pro mouse | Present in paired inventory; one five-second scan | No | No attempt | Not tested | Not tested | Does not validate standard BLE Battery Service. Paired `pmset` telemetry reports 95/100; `system_profiler` has no battery field. |
| MX Keys keyboard | Present in paired inventory; one five-second scan | No | No attempt | Not tested | Not tested | Does not validate standard BLE Battery Service. Paired `system_profiler` and `pmset` telemetry report 100%; this probe provides no contradictory GATT reading. |
| iPhone | Not tested | — | — | — | — | Unverified; no iPhone support claim |
| Cellular iPad | Not available; user has a Wi-Fi-only iPad | — | — | — | — | Unverified; cellular model not available |
| Wi-Fi-only iPad | Not included in this mouse/keyboard probe | — | — | — | — | Unverified |
| Standard BLE Battery Service peripheral | Not tested | — | — | — | — | Unverified; no known test peripheral was available for this record |
| AirPods | Not tested for Nearby BLE | — | — | — | — | Paired-device path is separate and unchanged |

## Probe record

The diagnostic matched only the HECATE G3M Pro mouse and MX Keys keyboard by
their transient advertised/CoreBluetooth names in memory. It observed zero
matching target advertisements and zero unclassified `180F` advertisements.
It therefore made no connection attempt; neither `180F` service discovery nor
`2A19` characteristic readability/value was tested.

After the five-second window, `stopScan()` completed and CoreBluetooth reported
`isScanning == false`; there were zero target GATT sessions to cancel. This
confirms radio-scan teardown for the probe, but does not validate disconnecting
an active GATT session or closing the product popover during a real connection.
No identifiers, addresses, advertisement payloads, or raw advertised names were
printed or stored in this document; only the user-supplied target categories
are named.

The host's paired battery telemetry is recorded separately from BLE GATT:
`pmset` reports 95/100 for the mouse, while the keyboard reads 100% through both
`system_profiler` and `pmset`. Since no `2A19` value was read from the keyboard,
the 100% paired reading is not evidence of a Nearby parsing bug.

To complete the hardware matrix, repeat the bounded probe when a device
advertises `180F`; record whether connection succeeds, whether `180F` and `2A19`
are present/readable, and whether a valid percentage is read. Keep identifiers
and raw advertisement data out of this document.

The implementation supports standard BLE peripherals that advertise `180F` and
expose a readable `2A19`; it does not use an Apple-specific manufacturer-data
parser. A future probe that finds no iPhone or iPad result must be reported as
“not observed under these conditions,” not as proof that the device can never
provide a Battery Service.
