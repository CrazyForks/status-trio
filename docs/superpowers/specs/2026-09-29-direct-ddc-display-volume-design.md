# Direct DDC volume for the selected display audio output

## Intent and evidence

Status Trio should show and adjust the hardware speaker volume of the selected external display when macOS exposes that display as the default audio output but exposes no writable CoreAudio volume scalar. The first acceptance device is the user's Acer XV272U on an Apple Silicon Mac over HDMI. Status Trio must talk to the display directly. It must not intercept volume keys, drive BetterDisplay, or change another application's settings. BetterDisplay may remain installed and continue to own the keyboard shortcut behavior.

On the XV272U, the default CoreAudio output has no scalar or mute property on the main element or its output channels. Its CoreAudio device UID exactly matches the display's IORegistry `EDID UUID`. A direct DDC read and write of VCP `0x62` changed the monitor's volume and read it back; the probe restored the original value. These observations establish this one device path, not universal DDC support. No BenQ display has been tested. Full DDC capability enumeration took about 13 seconds and failed; it is excluded from startup, refresh, and detection.

## Backend selection and identity

Keep CoreAudio as the preferred backend whenever the selected default output has a readable, writable volume scalar. Consider DDC only when that output lacks one. Resolve the selected CoreAudio output's UID against the `EDID UUID` of attached displays, and require exactly one matching live DDC service. Do not choose by display name, model string, physical position, or first result. If the UID is absent, multiple services match, the service disconnects, or the transport is unavailable, report volume as unavailable and leave volume actions disabled. The output device list and switching remain CoreAudio operations.

The backend resolver should produce one immutable selection for a given default output identity: CoreAudio, uniquely matched DDC target, or unavailable. A DDC target becomes volume-capable only after a valid `0x62` read. The read path and command path must use that same selection, so the UI cannot display one monitor's volume while a command targets another. Re-resolve on default-output change and display topology change. Every queued command carries its output identity and resolution generation; drop it if either changed before execution. Never write a newly selected display with a command queued for the previous one.

This phase targets Apple Silicon, where the direct transport was verified. An unsupported architecture or macOS API failure remains unavailable rather than guessing a route.

## DDC transport and validation

Add an in-process DDC adapter based on the minimal required MIT-licensed AppleSiliconDDC transport code, with its license and attribution retained. It uses the display service's I2C path directly; do not spawn `ASDDC` or another CLI process for production reads. Keep the private framework calls behind a narrow transport interface so they can be replaced if macOS changes. A transport failure must not block Status Trio startup or other status monitors.

Probe only VCP `0x62` (audio volume). Validate the DDC reply length and checksum, success/result byte (`0`), echoed VCP code (`0x62`), a positive maximum, and a current value no greater than the maximum. Treat any failed check as unsupported or failed, never as a volume value. The observed XV272U reply for an unsupported code carried a valid checksum and a result byte of `1`; the upstream probe otherwise displayed it as a plausible `100/100`. A checksum alone is therefore insufficient. Do not use a full capabilities scan.

Convert the monitor value to the existing `0...1` scalar using `current / maximum`. Clamp and round a requested scalar into `0...maximum`, write VCP `0x62`, then read the same code back. Publish the returned value as the confirmed state. A successful write call without a valid readback is unconfirmed and triggers a later retry/read, not a permanent optimistic value. Keep DDC operation details out of user-visible status strings.

The XV272U returned unsupported for VCP `0x8D` mute. DDC mode therefore offers volume adjustment but no mute action. Do not synthesize mute by writing zero and restoring a hidden previous value: that would conflate volume and mute and could overwrite a change made elsewhere.

## State, commands, and UI

Extend the volume status with explicit control capabilities, including whether the selected backend can set volume and whether it can mute. CoreAudio preserves its existing behavior when those capabilities are present. With a valid DDC read, show the current percentage and enable the slider and existing volume scroll action. Disable the mute button and mute command for a DDC-only output. The UI should not render a false muted state when DDC reports zero volume. The menu bar, Dock icon, and popover summary should consume the same published scalar. In the output list, update the selected display row with that scalar; leave other rows on their existing CoreAudio readings. No separate DDC-specific icon rendering path is needed.

DDC I/O must run off the main actor on a single serial worker per target. Keep only the latest pending slider value during a drag, with a short debounce (target 150 ms), while preserving an immediate final value when dragging ends. Avoid concurrent reads and writes to the same display. The store may present a provisional slider position during interaction. If a write or readback fails, clear that provisional position and publish volume as unavailable until the next valid `0x62` read. Commands that arrive during a backend switch, stop, or display sleep must not execute against stale identities. CoreAudio volume commands retain their current event-driven path.

The sound-settings gear and CoreAudio output switching behavior remain as they are. Status Trio does not require Accessibility or Screen Recording permission for the DDC path verified on this machine; it does not request keyboard interception. Other machines may deny or lack the undocumented I2C API, in which case controls remain unavailable.

## Refresh and resource bounds

Poll VCP `0x62` only for the current DDC-backed default output: every 2 seconds while the popover or relevant details are visible, and every 10 seconds while closed. Read immediately when the relevant view opens, the default output changes, a display reconnects, or the machine wakes. Stop polling on monitor stop or display sleep, and cancel a pending timer when the selected backend changes. Keep at most one I2C request in flight and coalesce a pending refresh into one follow-up read. On a transient read failure, publish volume as unavailable and retry after 2, 4, 8, 16, 32, then 60 seconds, capped at 60 seconds until a valid read resets the interval. An explicit unsupported VCP reply should also leave controls unavailable, without a tight retry loop. The normal CoreAudio path remains event-driven and receives no new DDC timer.

The local probe measured roughly 117–128 ms per `ASDDC` read including process startup, but that measurement is not a CPU or battery guarantee for the in-process adapter. Acceptance should measure actual polling time and idle CPU in the dev build. The polling interval is a responsiveness target; the worker must skip or defer a tick while an operation is still in flight.

## Verification and acceptance

1. Unit-test backend choice and exact, unique UID-to-EDID matching: writable CoreAudio wins; missing or ambiguous matches never write; changing output invalidates queued DDC commands.
2. Unit-test DDC reply parsing with valid `0x62`, unsupported result (`1`), wrong echoed code, invalid checksum, zero maximum, and out-of-range current value. Test scalar conversion, write coalescing, readback, failure reconciliation, stop, disconnect, and wake.
3. Verify UI capabilities: the XV272U DDC state shows a percentage and enabled slider but a disabled mute action; the existing CoreAudio controls and output switching still work. Verify menu bar and Dock read the same scalar.
4. Run `swift test` and `swift build -c release` before committing Swift changes. Because the planned worker and UI capability flow may touch actor isolation and SwiftUI bindings, run the repository's nonpublishing macOS 26 release workflow before merge or publication, and record any failed Actions run as required by `AGENTS.md`.
5. On the real XV272U, compare Status Trio's value with a direct DDC read, move the slider and confirm a hardware readback, then use the keyboard's existing BetterDisplay path and confirm Status Trio catches up within the selected polling interval. Switch outputs and disconnect/reconnect the display to confirm no cross-device writes. Measure idle CPU and polling duration in the dev app.

Completion means the dev build reads and adjusts the XV272U's speaker level, reflects external changes, and safely disables DDC controls when identity or transport validation fails. It does not promise DDC support for every monitor, mute on this model, or direct control of the macOS system-volume key path.

## Risks and limits

The Apple Silicon I2C calls used by AppleSiliconDDC are undocumented and may change in a macOS update. Some docks, adapters, monitors, and input modes do not expose a usable DDC path. Exact identity matching and strict reply checks favor a disabled control over a wrong-display write. This phase has no per-monitor DDC configuration UI; additional hardware models can be evaluated from real read/write evidence later.
