# Nearby BLE device selection and verification

The nearby-device allowlist starts empty, including after an upgrade. The
Nearby BLE section in Bluetooth settings discovers broadcast candidates without
connecting. Selecting a UUID adds that UUID to the status panel and its
device-order settings. The panel only permits battery reads for selected rows
that remain within the configured row limit and intersect the visible list
viewport. Hiding, deselecting, collapsing, scrolling a row offscreen, disabling
the battery display, or closing the panel removes the corresponding read
permission. Settings discovery can continue while panel battery reads are off.

BLE rows keep their CoreBluetooth UUID identity and remain separate from system
Bluetooth rows. Names and Apple vendor data are display and sorting metadata;
they do not establish ownership, pair devices, or prove a match to a system
address. Blank and duplicate picker names gain a stable UUID suffix. Settings
order entries show a Nearby BLE source label. A changed BLE UUID needs a new
explicit selection. Read failures keep the saved row and show an unavailable
status; expired or missing readings never appear as zero percent. The visual
and VoiceOver status use the same state. BLE rows are always displayed as
nearby and do not expose connect or disconnect actions.

The live candidate list reflects the latest five-second discovery window. A
candidate not observed in the next completed scan is removed; live entries also
expire after 60 seconds. A saved selection remains in Settings after it leaves
range and is marked not nearby. The 60-second freshness window matches the
existing automatic discovery interval, keeping names current without retaining
stale rows indefinitely.

Apple Continuity advertisements are candidates only when the existing
recognized payload predicate matches and the complete Apple company identifier
is present. Apple manufacturer data alone is insufficient. Discovery does not
open GATT. A connection begins only for an explicitly selected UUID that is
currently visible in the panel; per-session callback delegates and a
cancellation gate prevent a revoked UUID from starting another session until
its asynchronous disconnect/failure callback drains.

## Local verification

Implementation branch: `codex/nearby-ble-allowlist`. Product code and tests
were verified at commit `3764a719c2cd4abebb651ff1c26dd9508ddb4497`. The
separate documentation commit records this evidence without changing product
code.

After the consolidated review fixes, `swift test` exited successfully. XCTest
ran 1,154 tests with 6 skipped and 0 failures; Swift Testing ran 517 tests in
83 suites, all passed. The complete output is saved outside the repository at
`/tmp/nearby-ble-final-swift-test.log`. `git diff --check` passed. The required
`swift build -c release` exited successfully (26.49 seconds; output at
`/tmp/nearby-ble-final-release-build.log`). The final test-app package also
completed successfully at `dist/StatusTrio.app`; its bundle identifier is
`com.lingsmbp.StatusTrio.BLETest` and display name is `Status Trio BLE Test`.
The packaged executable check reported `arm64: minos 15.0, sdk 26.0` and
`LC_BUILD_VERSION check passed`; package output is at
`/tmp/nearby-ble-final-testapp-build.log`.

The final test app is packaged separately from the installed product, using
bundle ID `com.lingsmbp.StatusTrio.BLETest` and display name `Status Trio BLE
Test`. The package must pass `scripts/verify-platform-version.sh` with macOS 26
SDK or newer. It uses the repository's ad-hoc signing configuration; the
project has no Developer ID certificate or notarization secrets.

A `publish=false` GitHub release preflight passed for the previous implementation
SHA `43d9786ed3ae52db74f735964ecdbc477f876361` (run `37324480752`: tests,
release build, app/DMG packaging, signing and artifact upload passed; publishing
was skipped). That run predates the consolidated review fixes. The parent task
owns the final-SHA preflight and its result must be recorded separately.

The focused regression suite covers session-gate retirement/regrant, candidate
cache removal and expiry, Apple-first sorting across selected and discovered
rows, duplicate/blank-name disambiguation, shared visual/accessibility status,
settings discovery without read permits, and preservation of a visible selected
UUID when an off-limit UUID is hidden or deselected. The headless test host did
not produce row geometry for a hosted `NSHostingView`; attaching an `NSWindow`
made XCTest exit with signal 11. The stable tests therefore pin the visibility
invalidation policy used by the view and the controller's permit retention.
Actual SwiftUI geometry reporting after a hidden-row settings change remains
unverified by automated UI integration. No failing Actions run remains
unrecorded; the failed local hosted-view experiment is not a GitHub Actions run.

## Hardware verification limits

This implementation pass did not run a controlled iPhone, Watch, or standard
Battery Service peripheral matrix. Automated tests establish permission
boundaries and row projection, but do not prove that a particular radio target
advertises the recognized candidate payload, accepts a GATT connection, or
returns a readable battery characteristic. Settings discovery, Apple-first
ordering on real advertisements, actual charge readings, callback routing under
radio races, and physical scroll-away cancellation therefore remain unverified
on hardware.

No reliable mapping from a nearby BLE UUID to a system Bluetooth address is
available in the current advertisement inputs. The implementation does not
infer one from a name. BLE rows remain distinct and `isConnected == false`; a
system row keeps the state reported by macOS. Whether a temporary GATT session
changes that system-reported state was not measured during this pass, so this
work does not claim to resolve a false-connected system row. A prior isolated
diagnostic for a paired keyboard left it in the system connected section after
canceling an app-local read, but did not exercise this feature's scanner or
establish a BLE-UUID-to-system-address association.

If a test device changes its BLE UUID, its prior selection cannot safely follow
it by name. The user must select the newly discovered UUID. Any future
connection-state correction requires a reliable cross-source identity before
changing the system row; matching names are insufficient.
