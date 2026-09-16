# Wi-Fi status responsiveness

Opening the popover calls `SystemStatusStore.setPopoverVisible(true)`, which
refreshes the monitors before displaying the popover. Previously, the Wi-Fi
monitor synchronously read CoreWLAN properties and the Internet Sharing dynamic
store on the main actor. A slow system service therefore delayed UI event handling,
even though the application's average CPU usage could be low.

Apple's [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
recommends removing non-UI work from the main thread and keeping discrete
interaction work below roughly 100 ms. Merely wrapping a synchronous read in
`Task {}` on the main actor does not move it off that actor.

`CoreWLANStatusReader` now performs these synchronous reads on a serial utility
dispatch queue and delivers a Sendable value to the main actor. This also avoids
blocking Swift concurrency's cooperative thread pool. See Apple's
[Swift concurrency: Behind the scenes](https://developer.apple.com/videos/play/wwdc2021/10254/).

The monitor keeps at most one in-flight read and one pending refresh. A burst of
events or fallback polls while the service is slow cannot create an unbounded
backlog. Results from before a visibility, permission or recovery change are
discarded and reread; stopped or released monitors ignore completion. The last
published snapshot remains available while a read is in progress. Poll intervals,
event monitoring, classification and the existing stale-reading policy are unchanged.

## Verification

- `swift test --filter WiFiClassifierTests`: the blocked-reader test requires a
  main-actor continuation to unblock a synchronous background read. It fails if
  that read runs on the main thread. This is a deterministic responsiveness check,
  not a claim about wall-clock speed on any particular Mac.
- Deferred-completion tests cover 100 refresh requests collapsing to one follow-up,
  closing details, permission changes, wake/recovery, shutdown and deallocation.
- Run `swift test`, `swift build -c release` and the non-publishing release workflow
  on Xcode 16.4 / Swift 6.1.2, as required by `AGENTS.md`.

The synchronous system call itself cannot be cancelled once it starts. A stuck
call can still delay fresh Wi-Fi data, but it no longer occupies the main thread
or creates additional reads. CoreAudio reads, event registration, view layout,
timers and Liquid Glass adoption are outside this change. Real-device interaction
latency under load still needs measurement with Instruments; these tests do not
establish a battery-life improvement or a measured end-to-end speedup.
