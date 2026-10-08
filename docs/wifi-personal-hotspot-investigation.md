# Personal Hotspot missing from the Wi-Fi list

Investigation date: 2026-10-07. Base: `main` at
`f2aedbad69d893266d5149c269315e9e8d9ea713`.

## Report and reproduction limits

The reporter observed a Personal Hotspot in the macOS Wi-Fi menu but not in
Status Trio. An iPhone is not currently available for reproduction. No claim
of an end-to-end fix can be made from synthetic tests alone.

## Confirmed code path

- `CoreWLANNetworkWorker.scanSynchronously()` in
  `Sources/StatusTrioCore/Monitoring/WiFiNetworkController.swift` obtains all
  list candidates from `interface.scanForNetworks(withSSID: nil)`.
- `projectCandidate(_:)` discards results with a missing `CWNetwork.ssid`.
  There is no hotspot-specific exclusion.
- `WiFiNetwork.merge` groups candidates by SSID and security. The presentation
  partitions them into known/connected and other networks, without a
  hotspot-specific filter.
- No separate Instant Hotspot discovery source is integrated into this list.
- `WiFiNetworkListView` already provides an Open Wi-Fi Settings action.

## Apple documentation

[Instant Hotspot security](https://support.apple.com/en-euro/guide/security/seca4b33e8c9/web)
explains that Instant Hotspot discovery uses Bluetooth Low Energy and an
Apple Account-linked identifier. Selecting a device can request that it turn
on its hotspot. This is distinct from enumerating ordinary Wi-Fi scan results.

[Use Instant Hotspot](https://support.apple.com/en-gb/109321)
explains that Allow Others to Join need not be enabled for Instant Hotspot.

[CWInterface](https://developer.apple.com/documentation/corewlan/cwinterface)
documents Wi-Fi scanning. The local SDK's `CWInterface.h` describes
`includeHidden` as retaining hidden networks in Wi-Fi scan results, not as
Instant Hotspot discovery. Changing that flag is not evidence of a fix.

The documentation inspected does not identify a public API to enumerate the
system's Apple Account-based Instant Hotspot list. This is not an exhaustive
proof that no such API exists.

## Working hypothesis, not a reproduced root cause

The system menu may have shown a device discovered through Instant Hotspot
before its Wi-Fi hotspot was advertising. Status Trio's scan-only list would
then have no candidate to display. Another unexcluded possibility is that the
hotspot was in the raw scan but its SSID was unavailable. Distinguishing these
requires evidence from a real device.

Do not fabricate devices from preferred SSIDs, infer hotspots from names such
as “iPhone”, or use private properties as a discovery substitute.

## Verification completed

The initial worktree baseline `swift test` completed successfully:

- XCTest: 1,143 tests executed, 6 skipped, 0 failures.
- Swift Testing: 484 tests passed in 76 suites.

These results validate the baseline, not hotspot discovery. No Swift source
changes, release build, CI preflight, or publication were performed.

## Next verification when a device is available

1. Record whether the system entry is in Personal Hotspots and whether it is
   visible before Allow Others to Join is enabled.
2. Compare raw scan count, candidates missing SSID, and projected candidate
   count inside the app's own authorized process. Avoid logging SSIDs/BSSIDs
   by default. A standalone command-line probe has a different permission
   context and cannot establish what the app sees.
3. Enable Allow Others to Join, keep the phone's Personal Hotspot settings
   open, and use Status Trio's explicit refresh. Check whether a normal scan
   now includes the hotspot.
4. Connect using the system menu, then refresh Status Trio. Inspect the
   associated connection details as well as the scanned list.
5. Choose a fix based on the boundary that failed. Mocked candidates can
   validate projection/grouping/display but cannot validate BLE discovery,
   Apple Account authorization, hotspot wake-up, or actual scan visibility.

## Follow-up: hotspot is discovered but not classified

The reporter supplied two screenshots showing `jiling iPhone`: macOS places it
in Personal Hotspots, while Status Trio places it in Other Networks. This
confirms that the reported network is visible in the app in this test. It does
not prove that the earlier disappearance had the same cause.

For this reproduction the issue is classification/presentation, not missing
scan results: `WiFiNetworkCandidate` has no hotspot classification, and
`WiFiNetworkPresentation.grouped` only creates known and other groups. The
existing `WiFiClassifier` marks an associated Wi-Fi path as hotspot when it
is satisfied and expensive; that heuristic is not a classifier for nearby,
unassociated scan candidates and does not establish that a device is an iPhone.

The independent debug app has now built and launched successfully:
`dist/StatusTrio.app`, display name `Status Trio (Hotspot Test)`, bundle ID
`com.lingsmbp.StatusTrio.dev.wifi-personal-hotspot`. Product Swift sources
remain unchanged. The installed production app remains running separately.

Before changing grouping, establish a reliable source of hotspot metadata for
scan candidates. Do not classify networks solely by an SSID containing iPhone.

## Approved bounded correction

The reporter connected to the hotspot and confirmed that the summary already
shows the hotspot glyph, while the Wi-Fi list still puts it in Known Networks.
They approved moving only the currently connected, already recognized hotspot
to a Personal Hotspot section.

The list now uses the existing `WiFiStatus.state` and each scan group's
BSSID-based `isConnected` flag. The connected hotspot is excluded from Known
and Other, its row retains the checkmark and uses the hotspot trailing glyph,
and its details toggle belongs to the hotspot section. All 12 languages have
a localized section title. Unconnected hotspot discovery/classification and
menu-bar/Dock status rendering remain unchanged.

Local verification after the change: `swift test` passed (1,146 XCTest tests,
6 skipped, zero failures; 484 Swift Testing tests). The first implementation
run encountered temporary PID-file failures in MobileBatteryHelperReaderTests;
the isolated rerun and the subsequent full rerun passed. CI-toolchain
verification and a new live screenshot are still required before treating this
as a shipped fix.

## Unconnected-device probe result (2026-10-07)

At 2026-10-07T14:08:16Z the opt-in probe found one exact target among 11 raw
scan results. Its BSSID did not match the current interface BSSID, confirming
that the target was not the associated network. The information elements were
available (298 bytes), parsed without truncation, and contained a
vendor-specific payload `0017F206010103010000`. Other vendor payloads are not
reproduced here because they may contain device-specific identifiers. The
output file is owner-readable/writable only (0600) and remains local.

A primary reverse-engineering report independently demonstrates this exact
payload inducing macOS Personal Hotspot presentation on an OpenWrt access
point: https://www.yichya.dev/configure-access-point-as-personal-hotspot/ .
This is empirical, not an Apple-documented stable classification contract,
and a broadcast marker is not proof of device identity or authenticity.

The public read API is CWNetwork.informationElementData. A prospective
classifier should parse bounded IE/TLV data conservatively, recognize only
the supported observed hotspot feature record, ignore other Apple vendor
records, and fall back to normal grouping for unavailable/malformed/unknown
data. This only covers advertising Wi-Fi networks, not BLE-only sleeping
Instant Hotspot devices. Implementation of this next stage is not yet approved.

## GitHub reuse search and final scope

The user requested Luna research into an existing implementation and explicitly
chose connected-only grouping if no suitable implementation was found.

A bounded GitHub search covered informationElementData + CoreWLAN/IOS_IE,
isPersonalHotspot + macOS, and DD0A0017F206. OLoveBar provides the closest
functional example, but at revision
`3fbf65cb95c4292efac7a1fd2ef69c2f607f84d0` its WiFiNetworksController reads the
undocumented isPersonalHotspot getter through KVC. Its README advertises MIT
while LICENSE contains GPL version 3. No code was copied from that repository.

Sources verified:
- https://github.com/SacrilegeWasTaken/olovebar/blob/3fbf65cb95c4292efac7a1fd2ef69c2f607f84d0/Sources/OLoveBar/WidgetModels/WiFiNetworksController.swift
- https://github.com/SacrilegeWasTaken/olovebar/blob/3fbf65cb95c4292efac7a1fd2ef69c2f607f84d0/LICENSE
- https://github.com/SacrilegeWasTaken/olovebar/blob/3fbf65cb95c4292efac7a1fd2ef69c2f607f84d0/README.md

Other research candidates were YBar (a private saved-profile ivar, GPL-3, not
a direct scan classifier) and DataSaver (connected-only IOS_IE inspection,
reuse license not verified). No verified permissively licensed public-API
hotspot parser was found in the bounded search; this does not prove none exists.

Final user-authorized scope: retain connected-hotspot grouping and its row icon
and details, leave unconnected networks under their existing known/other
groups, and remove the temporary probe. A broadcast-based unconnected
classifier is not implemented.
