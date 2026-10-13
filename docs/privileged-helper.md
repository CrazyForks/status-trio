# Privileged power helper

Status Trio ships one privileged helper. It exists for a single job: turning
macOS Low Power Mode on or off. That is the only operation it exposes, and the
only reason it needs root.

## Why a helper at all

Low Power Mode is set with `pmset`, which refuses to run as anything but root:

```
$ pmset -b powermode 1
'pmset' must be run as root...
```

There is no public API that toggles it from an app process, so the write has to
happen in a root process. Reading the state needs no privilege:
`ProcessInfo.processInfo.isLowPowerModeEnabled` is what the app already uses,
and it is also what the daemon reads back after a change.

## Shape

- **Daemon**: `StatusTrioPowerHelper`, a SwiftPM executable target at
  `Sources/StatusTrioPowerHelper`, packaged as
  `Contents/Helpers/StatusTrioPowerHelper`.
- **LaunchDaemon plist**: `Support/StatusTrioPowerHelper.plist`, packaged as
  `Contents/Library/LaunchDaemons/com.lingsmbp.StatusTrio.PowerHelper.plist`.
  It uses `BundleProgram` (relative to the bundle root) and a `MachServices`
  entry, so no installer script ever writes to `/Library/LaunchDaemons`.
- **Shared protocol**: `Sources/PowerHelperProtocol`, a dependency-free target
  that names the XPC interface and the Mach service. The daemon depends only on
  it, so a root process never links AppKit, SwiftUI, or Sparkle.
- **Registration**: `SMAppService.daemon(plistName:)` (macOS 13+), wrapped by
  `PrivilegedHelperManager`, which mirrors `LaunchAtLoginManager`.

## On-demand, not always-on

The daemon is registered only while the user has opted in, and launchd only
bootstraps it once an administrator approves it and the app first connects. So
three gates must all open before root code runs:

1. The user ticks **Low Power Mode Control** in Settings › Battery.
2. The user approves the helper in System Settings › General › Login Items.
3. The app opens an XPC connection (the daemon starts lazily on that first
   connection and exits itself again once the app is done with it).

Unticking the control unregisters the daemon. The plist deliberately has no
`RunAtLoad` and no `KeepAlive`.

## Idle exit

launchd does **not** stop an idle job for us. A `MachServices` job that never
exits itself keeps running after the client is gone — measured on macOS 27 with
an equivalent user LaunchAgent, both with and without `EnableTransactions`
(`EnableTransactions` only tells launchd how to kill the job once something
else decides to stop it). Without help, quitting the app left
`StatusTrioPowerHelper` running as root until logout.

So the daemon owns its own lifetime (`IdleExitMonitor`, `Sources/StatusTrioPowerHelper`):

- The listener counts accepted connections. Each accepted connection is a
  reason for a root process to exist.
- When the last one ends — invalidated or interrupted, which is what the daemon
  sees both when the app invalidates its connection and when the app quits or
  dies mid-connection — the process exits after 5 seconds of no clients. The
  window is short enough that the helper is gone soon after a quit, and long
  enough for one app interaction (a popover read, then a toggle a few seconds
  later) to reuse the same process.
- The window starts when the daemon starts, too. launchd spawns the daemon for
  any Mach message, so a daemon that never gets a *usable* connection — a peer
  the code-signing requirement rejects, a request cancelled in flight — would
  otherwise linger forever with a connection count of zero.

Exiting is safe because launchd starts the job again on the next Mach message,
and `Support/StatusTrioPowerHelper.plist` sets `ThrottleInterval` to 1 second.
launchd's 10-second default would otherwise delay the relaunch that follows an
idle exit, so the next toggle would wait out the throttle instead of reaching a
fresh helper; `scripts/verify-privileged-helper-bundle.sh` pins that value.
`IdleExitMonitorTests` covers the policy: an exit after an idle window, no exit
while a client is connected, a connection cancelling a pending exit, and never
exiting twice for one window.

## Client authorization

A root daemon that accepted any client would let any local process change power
settings. The daemon refuses every connection that is not the signed app:

- `NSXPCListener.setConnectionCodeSigningRequirement` is the authoritative gate.
  Foundation evaluates the requirement against the peer's audit token before the
  delegate runs, so a mismatched caller never reaches the service.
- The requirement is
  `anchor apple generic and identifier "com.lingsmbp.StatusTrio" and certificate leaf[subject.OU] = "HCB7JKMQ2F"` —
  an Apple-anchored chain, the exact app identifier, and the signing team.
- The delegate re-checks the caller by PID as a second opinion and logs any
  rejection.

Because the requirement is Apple-anchored, an Ad-hoc-signed build can never
satisfy it. That is intentional: relaxing the requirement to make Ad-hoc work
would let any unsigned binary drive the daemon. Local end-to-end testing
therefore needs a Developer ID identity (see below), not an Ad-hoc build.

## Build variants

`scripts/build-app.sh` takes `PRIVILEGED_HELPER=1|0` (default `1`).

- `1` copies and signs the daemon and its plist, and writes
  `STIncludesPrivilegedHelper=true` into `Info.plist`.
- `0` omits both and writes `false`. This is what an App-Store-style build needs,
  since a root LaunchDaemon cannot ship there.

At runtime the app reads `STIncludesPrivilegedHelper`; when it is false the Low
Power Mode control is not offered at all, rather than offered and failing.
`scripts/verify-privileged-helper-bundle.sh` enforces both directions: the helper
and plist are present and well-formed when the flag is true, and absent when it
is false.

## What can and cannot be verified

- **CI / static**: the daemon is signed and hardened, its `minos` is 13.0 and its
  SDK is 26+, its plist names the right `Label`/`BundleProgram`/`MachServices`/
  `AssociatedBundleIdentifiers`/`ThrottleInterval`, and it embeds the
  Apple-anchored client requirement. `scripts/verify-privileged-helper-bundle.sh`
  checks all of this, and the non-publishing release workflow runs it.
- **Not in CI**: the live XPC round trip and the actual `pmset` write. A CI
  runner cannot grant the administrator approval a LaunchDaemon needs, so these
  are a manual Developer-ID check: build with a Developer ID identity, install
  the app, tick the control, approve it in Login Items, and confirm
  `sudo launchctl print system/com.lingsmbp.StatusTrio.PowerHelper` shows the
  daemon and that toggling the switch changes `pmset -g`.
- **Local, without root or a Developer ID**: the daemon's own lifetime, because a
  user LaunchAgent can run the same binary under the same `MachServices` name
  (`logout` moves the name back to the system domain). `swift build -c release
  --product StatusTrioPowerHelper`, copy the binary somewhere outside
  `~/Documents`, register a LaunchAgent for it with `ThrottleInterval 1`, and
  send it one Mach message. There is no approved app here, so the connection is
  rejected — the daemon still has to disappear about 5 seconds later, which is
  the case that used to leak a root process. Measured on macOS 27: the daemon
  exited with status 0 five seconds after the rejected connection, and a second
  message one second later started a new one immediately. A copy of the daemon
  built with the client requirement removed was used to confirm the other half —
  a connection that stays open keeps the process alive, and it exits 5 seconds
  after that connection is invalidated. Running the helper out of `~/Documents`
  hangs it inside `dyld` instead: a launchd-spawned process gets no TCC grant for
  that folder.

## Notes

- macOS 26 renamed the Battery settings control from "Low Power Mode" to a
  unified **Power Mode** (Automatic / Low / High). `pmset -g` now prints
  `powermode` rather than `lowpowermode`. The daemon writes
  `pmset -a lowpowermode 0|1`, which remains the accepted argument, and reads the
  state back through `ProcessInfo`.
