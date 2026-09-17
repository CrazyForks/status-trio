# Current Wi-Fi summary

For an associated Wi-Fi connection with an available SSID, the summary uses the
SSID as its title and shows the current radio band and RSSI below it. Either
measurement may be absent; missing values are omitted, never replaced by zero.
If both are absent, the subtitle simply says Connected (or Personal Hotspot).
Existing permission actions remain visible when the network name is unavailable.
The technical connection panel remains available through the same disclosure.

`CoreWLANWiFiSystemReader` reads
[`CWInterface.wlanChannel()`](https://developer.apple.com/documentation/corewlan/cwinterface/wlanchannel())
only behind its existing visible-details gate, and only while Wi-Fi power and
service are active. It maps known `CWChannelBand` values; unknown values remain
nil. The call runs on the existing serial utility queue introduced for Wi-Fi
status reads. It does not call `scanForNetworks`, request authorization, probe
Internet servers, or change the polling interval. RSSI already comes from this
reader. Neither measurement is Internet speed or a test of Internet reachability.

Closing details, a disconnected/off state, or a failed fresh reading drops the
frequency band. The existing short-lived RSSI/status fallback is unchanged.
The enhanced title and measurements require the primary path to be Wi-Fi,
a connected/hotspot radio, and a nonempty SSID. They are suppressed while the
primary path is Ethernet, offline, other, or unknown. VoiceOver shares the same
visibility gate, so permission prompts never announce visually hidden measurements.
A hotspot using a Wi-Fi primary path remains eligible. The existing technical
panel can still expose radio details separately from this primary-path summary.

The optional band is omitted from `MenuBarStatus`. Both icon subscriptions project
to this lightweight status before deduplication, and neither menu-bar nor Dock
render keys change when only the band changes. The full popover snapshot retains
the band for display. Twelve localizations share standard GHz/dBm unit labels;
frequency numbers use the selected locale's decimal formatting.
