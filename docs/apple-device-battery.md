# Apple device battery rows

Enable **Show Apple devices and battery** in **Settings → Bluetooth**. Status
Trio automatically discovers and adds verified iPhone and iPad routes already
trusted by this Mac, plus Apple Watch devices verified through a trusted paired
iPhone. There is no per-device picker. The rows share the Bluetooth list's
ordering, hidden-device rules, visible limit, expansion, and viewport.

Discovery reads device model/name and companion metadata only. It does not read
battery values or connect to arbitrary nearby Apple advertisements. A nearby
Apple company identifier, a device name, and an untrusted USB/network route do
not prove that a device belongs to this user. Eligible phone/tablet reads require
a verified iPhone/iPad model on USB or network transport. Watch rows require a
verified Watch model or trusted companion provenance and a trusted parent route.

The global Bluetooth battery setting still controls reads. A read additionally
requires the Apple master toggle, a visible row in the viewport, and current
verified discovery evidence. Reads use the helper's exact trusted IDs. Starting
a new discovery generation revokes old read permits until that generation
re-verifies the candidate. Turning either battery setting off cancels reads.

Verified metadata is retained by typed stable identity during the current app
session so a temporarily offline device can keep its row and retain its
order/hide preference. A later verified name refresh updates that same row. USB
and network observations for one UDID deduplicate. Legacy nearby BLE selections
are archived and cleared; they never become trusted identities or read permits.

The trusted helper is passive and does not invoke BLE GATT operations or
pairing-producing Bluetooth connect/read calls. Phone/iPad battery values use
already trusted USB or previously configured Wi-Fi routes. A Watch battery is
read through its already trusted paired iPhone. Status Trio does not pair devices
or change trust/Wi-Fi-sync settings.

Classic Bluetooth addresses and trusted helper UDIDs/Watch IDs are different
identity namespaces. When no stable cross-provider mapping exists, Status Trio
keeps same-named rows separate rather than guessing ownership or transferring a
battery value. The classic row retains its normal connect/disconnect actions;
the trusted helper row is read-only. Ordinary paired Bluetooth devices are
unaffected by the Apple master toggle.

Automated tests cover metadata-only discovery, unowned nearby broadcasts,
strict trust/model/transport eligibility, stable-ID rename and transport
deduplication, hidden/order behavior, viewport permits, master-off revocation,
and separation of ambiguous provider identities. The helper on this machine
currently lists zero trusted devices. USB/Wi-Fi/Watch battery behavior on
physical hardware remains unverified; automated tests do not establish hardware
acceptance.
