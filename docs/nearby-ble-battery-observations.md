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
That advertisement scan alone made no GATT connection attempts, so its service
and characteristic results are untested. The separate system-connected query
below tested the keyboard through a different route. The scan result is evidence
only for that window, not proof that a device never advertises the service.

| Device category | Radio / lock condition | `180F` advertising scan | GATT connection | `180F` service | `2A19` readable | Result |
| --- | --- | --- | --- | --- | --- | --- |
| HECATE G3M Pro mouse | Present in paired inventory; one five-second scan | No | No attempt | Not tested | Not tested | Does not validate standard BLE Battery Service. Paired `pmset` telemetry reports 95/100; `system_profiler` has no battery field. |
| MX Keys keyboard | Present in paired inventory; one five-second scan | No | Scan: none; retrieval: connected locally | Scan: not tested; retrieval: found | Scan: not tested; retrieval: readable (100%) | The system-connected retrieval path yielded a readable standard value matching paired telemetry. The production scanner still requires an advertising match. |
| iPhone | Not tested | — | — | — | — | Unverified; no iPhone support claim |
| Cellular iPad | Not available; user has a Wi-Fi-only iPad | — | — | — | — | Unverified; cellular model not available |
| Wi-Fi-only iPad | Not included in this mouse/keyboard probe | — | — | — | — | Unverified |
| Standard BLE Battery Service peripheral | Not tested | — | — | — | — | Unverified; no known test peripheral was available for this record |
| AirPods | Not tested for Nearby BLE | — | — | — | — | Paired-device path is separate and unchanged |

## Probe record

The diagnostic matched only the HECATE G3M Pro mouse and MX Keys keyboard by
their transient advertised/CoreBluetooth names in memory. It observed zero
matching target advertisements and zero unclassified `180F` advertisements.
It therefore made no connection attempt for either device; this scan alone did
not test `180F` service discovery or `2A19` characteristic readability/value.

After the five-second window, `stopScan()` completed and CoreBluetooth reported
`isScanning == false`; there were zero target GATT sessions to cancel. This
confirms radio-scan teardown for the probe, but does not validate disconnecting
an active GATT session or closing the product popover during a real connection.
No identifiers, addresses, advertisement payloads, or raw advertised names were
printed or stored in this document; only the user-supplied target categories
are named.

The host's paired battery telemetry is recorded separately from BLE GATT:
`pmset` reports 95/100 for the mouse, while the keyboard reads 100% through both
`system_profiler` and `pmset`.

A separate, scan-free query used
`retrieveConnectedPeripherals(withServices: [180F])`. It returned one
MX-Keys-matched peripheral. Its `CBPeripheral.state` was `.disconnected` for
the new central, so the diagnostic established one local CoreBluetooth
connection as Apple documents before accessing GATT. Within the four-second
deadline it found `180F`, found a readable `2A19`, and read a valid `100%` once.
It then canceled only that local connection and observed the local disconnect
callback. No fresh scan or pairing API was used, and no prompt was observed. A
sanitized post-probe `system_profiler` check still placed the keyboard in the
connected-device section. The paired `100%` reading is corroborated by an
independent standard GATT read; there is no evidence of a parsing bug. A single
GATT reading still cannot establish the keyboard's actual physical charge if
its own battery gauge is stale.

This connected-peripheral route is not implemented by the Nearby scanner, which
currently requires a matching `180F` advertisement. The read validates this
keyboard's standard service through system-connected retrieval, but does not
validate the product scanner's advertisement-discovery path or popover teardown
during a live GATT session. Supporting already system-connected devices that
do not advertise `180F` would be a separate feature-scope change.

Apple documents that system-connected retrieval can include peripherals
connected by other apps and that an app must connect locally before using them;
cancelling the app-local connection does not guarantee the physical link ends
while other system connections remain ([retrieval API](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveconnectedperipherals%28withservices%3A%29), [local cancellation API](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/cancelperipheralconnection%28_%3A%29)).

To complete the hardware matrix, repeat the bounded probe when a device
advertises `180F`; record whether connection succeeds, whether `180F` and `2A19`
are present/readable, and whether a valid percentage is read. Keep identifiers
and raw advertisement data out of this document.

The implementation supports standard BLE peripherals that advertise `180F` and
expose a readable `2A19`; it does not use an Apple-specific manufacturer-data
parser. A future probe that finds no iPhone or iPad result must be reported as
“not observed under these conditions,” not as proof that the device can never
provide a Battery Service.
