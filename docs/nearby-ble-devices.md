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

The final test app is packaged separately from the installed product. It uses
the repository's ad-hoc signing configuration; the
project has no Developer ID certificate or notarization secrets.

A manual settings smoke test used three simulated UUID selections in the
isolated test-app preferences, without granting Bluetooth access. Blank and
duplicate names displayed distinct UUID suffixes; device-order rows displayed
the Nearby BLE source badge without overlapping controls. Deselecting one
candidate removed its corresponding device-order row. The test app was then
closed and its isolated preferences reset; installed-product preferences were
not changed. This checks settings presentation, not radio discovery or reads.

The final `publish=false` GitHub release preflight
[run 37328285452](https://github.com/lingyired/status-trio/actions/runs/37328285452)
passed at commit `f675c42f08d663a7da04a8fabffcfa0b116685f8`, whose product
code and tests are identical to `3764a719c2cd4abebb651ff1c26dd9508ddb4497`.
Version `1.4.0`, build `18` was used only for the preflight. Tests, release
build, app/DMG packaging, signing, and artifact upload passed. Artifact
`StatusTrio-226` was uploaded (12,127,822 bytes); release and appcast publication
were skipped. Subsequent documentation changes do not alter the verified code.

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

## Implementation rulings

- Recognized Apple Continuity candidates may appear without a name. Names are
  presentation metadata; the complete company identifier and recognized message
  type still gate discovery. If this admits unwanted unnamed candidates, the
  picker can be noisier, but no UUID gains read permission without selection.
- Real iPhone/Watch GATT capability remains a hardware verification item. Unit
  tests prove authorization boundaries, not a particular device's readable
  characteristic. If a target is unsupported, its selected row may remain
  unavailable rather than deliver battery data.
- BLE UUID stability remains a hardware verification item. Selection follows
  only the saved UUID because names cannot safely identify ownership. If a UUID
  rotates, the user must select the new UUID.
- Temporary GATT effects on macOS connection reporting remain unverified. Pure
  BLE rows stay disconnected, while system rows preserve macOS state without a
  reliable cross-source identity. If macOS reports a temporary GATT session as a
  connection, that system row may still appear connected.
- Exact CI toolchain compatibility is decided by the nonpublishing release
  workflow, not the newer local compiler. A failed preflight blocks merge and
  must be diagnosed and recorded before completion.
- All 12 translations use the existing localization vocabulary, but this pass
  does not provide native-speaker review. Some wording may need later refinement.
- Headless hosted-view geometry verification was replaced with deterministic
  policy and controller regressions after no geometry and a signal-11 host
  failure. Physical scrolling and actual SwiftUI layout remain manual hardware
  checks; a layout-specific regression could escape these tests.

No review minors remain deferred. The visual/VoiceOver status inconsistency was
regraded as important and fixed with shared status derivation and a regression.

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
work does not claim to resolve a false-connected system row.

If a test device changes its BLE UUID, its prior selection cannot safely follow
it by name. The user must select the newly discovered UUID. Any future
connection-state correction requires a reliable cross-source identity before
changing the system row; matching names are insufficient.
