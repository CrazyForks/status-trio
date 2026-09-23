# VPN row

The popup's VPN row reports whether traffic is being relayed: through a tunnel,
through a system VPN service, or through the system-wide proxy. It is a popup
row only — nothing in the menu bar or the Dock icon draws it, and it is not part
of `StatusSnapshot`.

## The three signals

| Signal | Source | What it means |
| --- | --- | --- |
| Tunnel interface | `getifaddrs()`, names matching `utun`/`ppp`/`ipsec`/`tap`/`tun` that are `IFF_UP` and hold a routable IPv4 address | A tunnel is carrying traffic. Covers every client that creates a virtual interface: WireGuard, Tailscale, OpenVPN, and Clash in TUN mode. |
| System VPN service | `SCNetworkServiceCopyAll` plus `SCNetworkConnectionGetStatus`, for services whose interface type is PPP, IPSec or L2TP | A VPN configured in System Settings is connected. Supplies the name the row leads with. |
| System-wide proxy | `State:/Network/Global/Proxies` through `SCDynamicStoreCopyValue` | A proxy is set. Not a tunnel — no virtual interface, no new address — so it is reported separately and never reads as a connected VPN. |

A tunnel or a connected service makes the row read **Connected**; a proxy alone
reads **System proxy** with its endpoint as the detail; neither reads **Not
connected**. When both are up, the detail carries them together
(`Connected · proxy 127.0.0.1:10808`).

## Why an address and not a name list

macOS keeps its own tunnels up. Measured on macOS 26.6.1, with Clash Verge in
system-proxy mode:

```
utun0 up=true flags=32849 v4=[]
utun1 up=true flags=32849 v4=[]
utun2 up=true flags=32849 v4=[]
utun3 up=true flags=32849 v4=[]
```

All four are `UP,RUNNING` and none carries an IPv4 address, while a tunnel that
is forwarding traffic has one. That is the property
`TunnelInterfaceClassifier.isActiveTunnel` keys on. A hard-coded list of system
interface names would need maintaining on every macOS release and would still
miss a new one; the address is what separates a tunnel carrying traffic from a
tunnel that is merely present.

## Known limitations

- **A system proxy is not a VPN.** Clash Verge in system-proxy mode sets
  `HTTPEnable`, `HTTPSEnable` and `SOCKSEnable` on `127.0.0.1:10808` and creates
  no tunnel. The row reports it as a proxy. Only TUN mode produces a `utun` with
  an address.
- **iCloud Private Relay** does not report as a VPN either. Whether it holds an
  address on a system `utun` has not been observed on this machine; if a report
  comes in, the place to extend is `TunnelInterfaceClassifier`, with the
  observed interface as the evidence.
- **The service name needs an admin account.** macOS treats the network
  preferences as administrative. On this machine (admin, macOS 26.6.1)
  `SCNetworkServiceCopyAll` returns the seven configured services without sudo.
  A standard account can be refused the list; the row then reads **Connected**
  without a name. The name is decoration and the verdict does not depend on it —
  that is why the service signal is not the primary one.
- **VPN services have no Settings pane of their own.** They live in the Network
  pane's service list, so the row is not a button and offers no gear. See
  [System Settings pane routes](settings-pane-routes.md): the first route
  decides the destination and a wrong one is never corrected.
- **No NetworkExtension.** `NEVPNManager` would name the VPN precisely, but it
  needs the `com.apple.developer.networking.networkextension` entitlement and a
  provisioning profile, and this repository signs Ad-hoc with no Developer ID.
  SystemConfiguration needs no entitlement, no `Info.plist` entry and no TCC
  grant — the same reason the Wi-Fi and Bluetooth rows avoid entitlements.
- **The read runs on the main actor.** One read is a `getifaddrs` pass plus two
  SystemConfiguration lookups, measured in single-digit milliseconds, and the
  monitor is driven by the store's fallback tick rather than a per-frame path.

## Default state

`.vpn` is in `SettingsStore.defaultEnabledPopupSections`, so a fresh install
shows the row. A user who has already saved a section list is covered by a
one-shot migration: `sanitizedEnabledPopupSections(_:hasIntroducedVPN:)` adds the
row when the `vpnPopupSectionIntroduced.v1` marker is unset, and the result is
written back to `UserDefaults` because `didSet` does not run for an assignment
made inside `init`. After that the stored list is the user's own choice, so
switching the row off sticks.

## Where the code lives

| File | Role |
| --- | --- |
| `Models/VPNStatus.swift` | `VPNStatus`, `VPNProxyStatus`, `VPNProbeReading`, `VPNStatusResolver`, `TunnelInterfaceClassifier` |
| `Monitoring/VPNProbe.swift` | The three readers and their protocols |
| `Monitoring/VPNMonitor.swift` | Lifecycle, the `SCDynamicStore` subscription, the stream |
| `UI/VPNStatusView.swift` | The popup row |
| `UI/StatusPopoverView.swift` | `StatusPresentation.vpnTitle/vpnSubtitle` |
| `Settings/SettingsStore.swift` | Default selection and the migration marker |

## Verifying by hand

```bash
# Tunnels, with the flags and addresses the classifier sees
for i in $(ifconfig -l | tr ' ' '\n' | grep -E '^(utun|ppp|ipsec|tap|tun)'); do
  echo "--- $i"; ifconfig "$i" | grep -E 'flags|inet '
done

# Configured VPN services and their state
scutil --nc list

# The proxy dictionary the row reads
scutil --proxy
```

## Tests

| File | Covers |
| --- | --- |
| `VPNStatusTests.swift` | Resolver output, name prefixes, the up-plus-address rule, proxy dictionary parsing |
| `VPNMonitorTests.swift` | Lifecycle, subscription, `stop()` finishing the stream, `start()` idempotence |
| `VPNRowSettingsTests.swift` | Default selection, the one-shot migration and its write-back, a switched-off row staying off |
| `StatusPresentationTests.swift` | Row title and detail for a named tunnel, a bare tunnel, a proxy, both, and a PAC configuration |
| `LocalizationParityTests.swift` | All twelve languages carrying the six new keys |
