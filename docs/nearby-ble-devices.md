# Apple device selection and battery verification

Bluetooth settings has one opt-in, **Show Apple devices and battery**, and one
explicit Apple-device selection list. New devices are never selected
automatically. A selected device keeps its row when it is offline or has no
readable battery value. The global Bluetooth battery-level setting still
controls battery reads and percentage display; turning it off does not remove
selected rows.

The picker combines two metadata-only discovery paths:

- Nearby Bluetooth advertisements with the recognized Apple company identifier.
  This identifies Apple broadcast evidence, not device ownership or battery
  support. Nearby Bluetooth battery reads do not require USB trust.
- Existing trusted USB or network device routes verified by Apple product
  metadata. Reading iPhone and iPad through USB or Wi-Fi requires the device to
  be unlocked and trusted. The first setup requires a USB connection and the
  Trust confirmation. Wireless reads also require Wi-Fi syncing to be set up.
  Apple Watch discovery and reads may use its trusted paired iPhone as a parent
  session; the parent phone is not selected or read for battery unless the user
  selects it separately. Watch support depends on the paired device and helper
  capabilities.

Discovery does not request battery values. A device name such as “iPhone” or
“Apple Watch” is never proof of Apple identity. An untrusted route can show a
trust hint, but cannot be selected as an Apple device until its model or Watch
companion provenance is verified. Helper failures are scoped to the relevant
device and do not hide another device's successful level.

BLE UUIDs and trusted UDIDs/Watch identifiers use separate typed identities.
Same-named rows are not merged and never share battery values. If an identifier
changes, select the newly discovered identity. Existing paired Bluetooth rows,
including AirPods, keep their normal path and are not gated by this opt-in.

## Migration

On first launch after the change, the new master switch is initialized to the
logical OR of the previous nearby-Bluetooth and trusted-mobile battery toggles.
Previous Apple BLE selections retain their UUID and hide/order preferences.
Other-vendor and unknown-vendor BLE selections are archived and are neither
shown nor read. The old trusted-mobile toggle migrates only the master enabled
state; it does not select any trusted device. The migration marker prevents a
deselected device from being imported again after restart. Disabling the new
master switch preserves selections.

## Read authorization

Battery access requires the new master switch and global battery setting to be
on, the device to be selected, its row to be unhidden, and the row to intersect
the actual visible list viewport. Collapsed, hidden, scrolled-offscreen,
deselected, or closed rows lose their read permits; stale callbacks from an old
permit generation are rejected. The helper receives the exact trusted IDs.
When only a Watch is selected, it may establish the paired iPhone session and
query Watch metadata to validate the route, but it does not query the parent's
battery key or any other Watch battery key.

Missing, expired, unavailable, and zero-percent readings remain distinct. A
read failure does not replace a successful value from another selected Apple
device. Nearby Bluetooth rows are read-only and do not change macOS connection
state or offer connect/disconnect controls.

## Verification limits

Automated tests cover source-qualified identities, legacy migration, metadata
discovery without battery queries, iPad product decoding, Watch-only helper
commands, total candidate bounds, visible-row authorization, permit revocation,
late-result rejection, selected rows without readings, and preservation of
ordinary paired-device rows.

The native helper's USB trust flow and battery APIs require a real paired Apple
device to verify end-to-end. This implementation pass has not yet completed a
physical iPhone, iPad, or Apple Watch smoke test. In particular, iPad battery
reading and Watch-only behavior on hardware are unverified. A successful local
build or fake-native test must not be reported as radio or hardware validation.
