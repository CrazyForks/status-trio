# Nearby BLE battery hardware observations

This document records device-level observations separately from code and
simulator tests. Hardware results must come from a short, explicit probe; an
empty scan is evidence only for the tested device and conditions.

## Environment and permission

- Observation date: 2026-09-27
- Host: macOS 27.0, build 26A428; Apple Silicon
- Xcode: 27.0, build 27A266a
- Swift: 6.4 (swiftlang-6.4.0.34.1)
- Bluetooth authorization: `.allowedAlways` was read without creating a central
  manager or starting a scan.
- Baseline automated checks: `BluetoothPermissionTimingTests` (11 tests) and
  `BluetoothPollingLifetimeTests` (23 tests) passed before implementation.

## Device matrix

No hardware probe has been run for this implementation. Device access has not
been confirmed, so every device row remains **unverified**; no device-specific
support or lack of support is inferred.

| Device category | Radio / lock condition | Discovered with `180F` filter | GATT connected | `180F` found | `2A19` readable | Result |
| --- | --- | --- | --- | --- | --- | --- |
| iPhone | Not tested | — | — | — | — | Unverified; no iPhone support claim |
| Cellular iPad | Not tested | — | — | — | — | Unverified; test if a device is available |
| Standard BLE Battery Service peripheral | Not tested | — | — | — | — | Unverified; no known test peripheral was available for this record |
| AirPods | Not tested for Nearby BLE | — | — | — | — | Paired-device path is separate and unchanged |

## Probe record

No device names, UUIDs, addresses, or advertisement payloads were collected. No
connection was attempted. To complete this matrix, record the device class,
system version, Wi-Fi / hotspot / lock condition where relevant, whether the
five-second scan discovered it, whether a connection succeeded, whether service
`180F` and characteristic `2A19` were present, and whether a valid percentage
was readable. Keep identifiers and raw advertisement data out of this document.

The implementation supports standard BLE peripherals that advertise `180F` and
expose a readable `2A19`; it does not use an Apple-specific manufacturer-data
parser. A future probe that finds no iPhone or iPad result must be reported as
“not observed under these conditions,” not as proof that the device can never
provide a Battery Service.
