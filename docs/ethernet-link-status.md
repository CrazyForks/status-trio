# Wired link status

The popover's network section is one row whose subject is whatever carries the
primary connection. While Wi-Fi is primary it is the Wi-Fi row; while a cable is
it is the wired row, titled with the port's own name and subtitled with its BSD
name. Either row opens a panel with the same five technical rows.

## What the row says, and what it does not

The row names the link:

| | source | example |
|---|---|---|
| title | the interface's localized display name | `iPhone USB` |
| subtitle | the interface's BSD name | `en9` |

It deliberately says nothing about the address. The popover is a panel that can
be read over the reader's shoulder, and a LAN address — let alone the router and
the DNS servers beside it — is the reader's own business. The addresses live in
the panel, one deliberate tap away, where the five rows have always put them.
`WiredLinkPresentation` is the single place that decides this, so the row and the
panel's back row cannot drift apart, and `WiredLinkPresentationTests` asserts the
address never appears in either line.

The title falls back to the generic localized "Ethernet" when macOS reports no
display name for the interface, and the subtitle falls back to the connected
state when the read has not named the interface yet. A blank heading is never
drawn.

## What the section is called in Settings

The popup section was Wi-Fi only, so it was named for the radio — in the
settings list, and in the icon guide that labels the middle of the menu bar
icon. It now covers whichever link carries the connection, so both name it
`settings.popup.order.network` ("Network") rather than `wifi.title`. The new key
reuses the wording every language already uses for the Network settings tab, so
the terms stay consistent without inventing a translation.

The section's icon stays `wifi`. That is now the last Wi-Fi-only thing about this
row: the menu bar draws a distinct Ethernet glyph for a cable, so the settings
list shows a Wi-Fi symbol against a row that may be reporting one. Changing the
icon is a visual decision of its own and is left out of this change.

## Which interface is reported

`NetworkConnection` already separates a wired primary path from a wireless one:
`NWPathMonitor` reports `usesInterfaceType(.wiredEthernet)`, and
[`NetworkConnection.resolve`](../Sources/StatusTrioCore/Models/NetworkConnection.swift)
prefers the wired path when both are usable. That answers *that* the connection is
a cable, not *which* interface carries it or what address it has, so the address
comes from the system configuration store instead:

1. `SystemWiredInterfaceProvider` asks `SCNetworkInterfaceCopyAll()` which
   interfaces this Mac reports as `kSCNetworkInterfaceTypeEthernet`. Each one
   arrives as a `WiredInterface`: the BSD name the store is keyed by, plus the
   display name `SCNetworkInterfaceGetLocalizedDisplayName` gives it — the
   driver's own name for the port, localized by the system.
2. `SystemPrimaryLinkReader` reads one `SCDynamicStore` snapshot — `State:/Network/Global/IPv4`
   plus every `State:/Network/Service/*` — on its own serial queue.
3. [`PrimaryLinkResolver`](../Sources/StatusTrioCore/Models/PrimaryLinkDetails.swift)
   picks the wired service out of it: the primary service when it is one of the
   wired interfaces, otherwise the first wired interface that has a service. The
   display name of whichever interface it resolved travels with the result.

The third step is what keeps a VPN honest. A tunnel claims the primary service
while it is up, so reading "whatever is primary" would print the tunnel's address
under an Ethernet title. The wired interface's own service is reported instead,
and the tunnel stays out of this row.

Two cases resolve to nothing on purpose:

- the interface is wired but the snapshot holds no service for it, and
- several services carry it and none of them is the primary one.

In both the panel reports its rows as Unavailable. A wrong address is worse than
no address, and the ambiguity is real: it is what a stale service looks like
between a cable moving networks and macOS cleaning up.

## Where the interface name comes from

The name a service carries is **not** in the domain this feature reads. On macOS 27
no service publishes a `State:/Network/Service/<id>/Interface` dictionary at all —
verified on a live system, where all five services (Wi-Fi and four VPN tunnels) had
`State:` entries without it, while the mapping sat under
`Setup:/Network/Service/<id>/Interface`, a domain no snapshot here collects.

[`NetworkServiceResolver`](../Sources/StatusTrioCore/Monitoring/NetworkServiceResolver.swift)
therefore names a service from its address dictionaries — `IPv4.InterfaceName`,
then `IPv6.InterfaceName` — and only falls back to the legacy `/Interface.DeviceName`
for a system that still publishes it. Reading the legacy key first left two things
silently broken on macOS 27: the wired panel's Interface row read Unavailable, and
`PrimaryLinkResolver`'s "is the primary service the wired link" branch could never
match, so the tunnel case and the stale-primary case collapsed into the same
fallback.

The **display name** does not come from the store at all, which is why the row's
title survived that incident untouched: it is read off the `SCNetworkInterface`
the resolver already had to enumerate. On the machine this was built on, the same
call reports `en9` as `iPhone USB`, `en5` as `USB 10/100/1000 LAN`, and `en4` as
`Ethernet Adapter (en4)` — the system's own name for each port, not the service's
`UserDefinedName`.

[`scripts/probe-network-link.swift`](../scripts/probe-network-link.swift) walks this
whole path against the live system — the `NWPath` interface types, the
`SCNetworkInterface` types, the store snapshot, and the resolver's own branch — and
prints both the current and the legacy name side by side. Run it before and after
plugging a cable (or tethering a phone over USB) when a report does not match what
the popover shows.

## When it is read

`SystemStatusStore` activates the read only while **both** the popover is open and
the primary connection is Ethernet, and deactivates it the moment either stops
being true. Deactivating drops the value, so reopening the popover can never paint
the address of a link the user has left. Because the store samples the connection
itself, a cable plugged in while the popover is open starts the read on the
connection change rather than on the next poll.

The controller keeps a 30-second loop while it is active. That covers the one
change no event reports — a DHCP renewal on a link that stayed up. Everything else
(the cable, the tunnel, the primary interface) arrives as a connection change.

## Why the address is not in `StatusSnapshot`

`StatusSnapshot` is what the menu bar and Dock icons are drawn from. An address
that changes on a DHCP renewal must not be an icon input: it would invalidate
`StatusBarRenderKey` and `DockIconRenderKey` for a value neither icon draws. The
wired link therefore lives in its own `PrimaryLinkController`, which the popover
observes directly — the same shape `WiFiNetworkController` and
`BluetoothDeviceController` already use. Nothing in the icon path changes, so the
menu bar and Dock parity rule does not apply to this feature.

## Shared detail rows

`LinkDetailPresentation` builds the rows, and `LinkDetailsList` draws them, so the
Wi-Fi panel and the wired panel cannot drift apart on spacing, alignment, or what
tapping a value does. The wired panel reports the shared five and stops there: a
cable has no radio, no association, and no negotiated rate.

Addresses are copyable in both panels and the interface name is not, matching the
existing behaviour of the Wi-Fi panel.

The localization keys split along the same line:

- `network.detail.*` — the rows every link reports (`interface`, `ipv4`, `ipv6`,
  `router`, `dns`, and the `unavailable` placeholder). These carry no radio
  wording, which is why `network.detail.interface` reads "Interface" rather than
  "Wi-Fi Interface".
- `wifi.detail.*` — the rows only a radio has (SSID, BSSID, band, channel, RSSI,
  PHY, transmit rate, security, country code).

## What it deliberately does not do

- **No address in the row.** The row names the port; the panel reports the
  addresses. An address is private and the popover is not, so it is never on
  screen until the reader asks for it.
- **No public address.** Resolving one needs a request to a server the app does
  not run, which is outside a status app's remit.
- **No reachability probe.** The row reports the address the system has, never
  whether anything answers at it. This is the same boundary `wifi-summary.md`
  records for Wi-Fi.
- **No switching.** Which wired network a cable reaches is a cabling job; anything
  macOS has to be told about lives in the Network pane, which the row's gear and
  the panel's button open.
- **No icon change.** The menu bar and Dock already draw the Ethernet glyph; this
  feature adds the port's name to the popover only.

## Tests

- `PrimaryLinkTests` — service selection, the primary-service rule, the VPN and
  wireless fallbacks, the ambiguous and missing-service cases, where the interface
  name is read from, how the port's display name travels with it, and the
  controller's activation and late-answer behaviour.
- `WiredLinkPresentationTests` — what the row and the panel call the link, the
  fallbacks when macOS names nothing, and the assertion that the address never
  reaches either line.
- `LinkDetailPresentationTests` — the row sets of both links.
- `SystemStatusStoreTests` — when the read starts and stops.
