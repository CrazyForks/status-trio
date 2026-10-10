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
   connection and is not kept alive otherwise).

Unticking the control unregisters the daemon. The plist deliberately has no
`RunAtLoad` and no `KeepAlive`.

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
  `AssociatedBundleIdentifiers`, and it embeds the Apple-anchored client
  requirement. `scripts/verify-privileged-helper-bundle.sh` checks all of this,
  and the non-publishing release workflow runs it.
- **Not in CI**: the live XPC round trip and the actual `pmset` write. A CI
  runner cannot grant the administrator approval a LaunchDaemon needs, so these
  are a manual Developer-ID check: build with a Developer ID identity, install
  the app, tick the control, approve it in Login Items, and confirm
  `sudo launchctl print system/com.lingsmbp.StatusTrio.PowerHelper` shows the
  daemon and that toggling the switch changes `pmset -g`.

## Notes

- macOS 26 renamed the Battery settings control from "Low Power Mode" to a
  unified **Power Mode** (Automatic / Low / High). `pmset -g` now prints
  `powermode` rather than `lowpowermode`. The daemon writes
  `pmset -a lowpowermode 0|1`, which remains the accepted argument, and reads the
  state back through `ProcessInfo`.
