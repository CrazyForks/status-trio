# Build And Signing Hardening Implementation Plan

> **STATUS: DEFERRED — do not start (owner decision, 2026-09-20).** The owner has no Apple Developer account, the app has an active user base, and Sparkle auto-update must keep working for them. Every change in this plan alters how the shipped bundle is signed or packaged, so it is on hold until the owner schedules it deliberately. See `2026-09-20-review-findings-index.md` §0. Non-negotiable precondition when it is picked up: the update path for already-installed copies must be provably unaffected, and no step may change how a user's existing app launches or updates.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `scripts/build-app.sh` stamp the SDK it actually built against, sign nested code explicitly instead of with the deprecated `--deep`, and state the Gatekeeper trust decision honestly in `README.md` and `AGENTS.md`.

**Architecture:** Keep the Ad-hoc release path as the documented default. Correct the `LC_BUILD_VERSION` stamp so `scripts/verify-platform-version.sh` asserts a real value instead of the literal it wrote itself, replace `--deep` with an ordered list of explicit `codesign` invocations, and gate any hardened-runtime change behind an entitlement that is proven to keep Sparkle loadable. All Developer ID and notarization work stays a conditional follow-up.

**Tech Stack:** Bash, `codesign`, `xcrun vtool`, `lipo`, `spctl`, `xattr`, `plutil`, SwiftPM, GitHub Actions

**Spec:** Derived from the 2026-09-20 security review (finding **R-11**); cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3; local Xcode 27 / Swift 6.4 is not proof.
- No Developer ID certificate / notarization secrets exist today; Ad-hoc signing is the documented status. Steps requiring a Developer ID must be written as conditional follow-ups, never as assumed prerequisites.
- The app must build with the macOS 26 SDK or newer. `scripts/build-app.sh` fails on an older SDK and `scripts/verify-platform-version.sh` asserts the built binary's `LC_BUILD_VERSION`. Do not remove or weaken either check (see `docs/swift-ci-compatibility.md` and issue #40).
- Run `swift test` and `swift build -c release` for Swift changes; a script-only change must still pass `bash scripts/validate-appcast-notes.sh` and a `publish=false` release preflight where applicable: `gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false` then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`.
- Release notes live in `release-notes/<version>/<language>.md`; `en.md` + `zh-Hans.md` always required; every file starts with a `# <title>` line containing `%VERSION%` and `%BUILD%`. Any user-visible behavior change needs an entry.
- Never print, echo, or pass secrets on a command line; never commit key material.
- **Prohibited change:** never enable the hardened runtime on the Ad-hoc path without `Support/StatusTrio.entitlements` granting `com.apple.security.cs.disable-library-validation`. Measured on this machine, `--options runtime` on an Ad-hoc bundle makes dyld refuse to load the embedded framework (`mapping process and mapped file (non-platform) have different Team IDs`), which ships a non-launchable app. The exact evidence is recorded in Task 1.
- This plan owns `scripts/build-app.sh`, `scripts/verify-platform-version.sh`, `Support/StatusTrio.entitlements`, `README.md`, and `AGENTS.md`. `.github/workflows/release.yml` is owned by the release-pipeline plan; only its release-body wording may be touched, and only by that plan.

## Measured Prerequisites

These results were produced during planning on a **copy** of the built bundle in a temporary directory (never `dist/StatusTrio.app` itself) on macOS 27 / Apple silicon. Do not re-derive them; re-run them only if the signing code changes.

1. `codesign --force --sign - --options runtime <framework>` then `codesign --force --sign - --options runtime <app>` succeeds; `codesign -dv` reports `flags=0x10002(adhoc,runtime)`, `Runtime Version=15.0.0`, `TeamIdentifier=not set`, and `codesign --verify --strict --verbose=2` reports `valid on disk` / `satisfies its Designated Requirement`.
2. Launching that bundle **fails**. dyld refuses the embedded framework: `Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle ... (code signature in ... not valid for use in process: mapping process and mapped file (non-platform) have different Team IDs)`. `--options runtime` turns on library validation, which requires the executable and every library it loads to share a Team ID; an Ad-hoc signature has none. This is why `scripts/build-app.sh:202` guards the runtime options behind a non-`-` identity — **that guard is load-bearing, not a convenience**.
3. Re-signing the app with both `--options runtime` **and** an entitlements file containing only `com.apple.security.cs.disable-library-validation` launches with no dyld diagnostic; the entitlement is confirmed present by `codesign -d --entitlements -`. Trade-off: this buys the runtime's W^X and unsigned-memory protections while explicitly switching library validation back off, so it is **not** a defence against library injection. The real fix remains Developer ID plus notarization, which puts both binaries under one Team ID and makes library validation meaningful.
4. A minimal reproducer outside the app bundle confirms all three points independently: an Ad-hoc `--options runtime` executable with **empty** entitlements fails to `dlopen` a differently-signed dylib (`DYLD_FAIL`), the same executable with the `disable-library-validation` entitlement loads it (`DYLD_OK`), and the same executable with **no** runtime loads it (`LOAD_OK`).
5. `--deep` does sign nested code today, but it also **propagates the app's entitlements to every nested item**: signing the bundle with `--deep --options runtime --entitlements <disable-library-validation>` gave `Sparkle.framework/Versions/B/Updater.app` the same `disable-library-validation` entitlement it does not need. That inconsistency is the concrete reason to stop signing with `--deep` (Apple documents `--deep` as deprecated for signing and intended for verification), not a claim that today's signature is broken.

## Verified Findings

| Finding | Location | Evidence |
| --- | --- | --- |
| Ad-hoc is the default identity | `scripts/build-app.sh:200` | `SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"` |
| Runtime options are only added for a non-Ad-hoc identity | `scripts/build-app.sh:201-207` | `SIGNING_ARGS=(--force --deep --sign "$SIGNING_IDENTITY")` then `if [[ "$SIGNING_IDENTITY" != "-" ]]` |
| Signing uses `--deep` and passes no entitlements | `scripts/build-app.sh:209-210` | `codesign "${SIGNING_ARGS[@]}" "$CONTENTS/Frameworks/Sparkle.framework"` / `... "$APP_DIR"` |
| No entitlements file exists anywhere | repository root | `find . -name '*.entitlements' -not -path './.build/*' -not -path './.worktrees/*'` prints nothing |
| The SDK stamp is the literal `26.0` | `scripts/build-app.sh:192` | `xcrun vtool -set-build-version macos "$BUILT_MINOS" 26.0 -replace ...` |
| The assertion observes only what the build just wrote | `scripts/verify-platform-version.sh:53-61` | `if (( sdk_major < MINIMUM_SDK_MAJOR ))` against `sdk` read from the same file |
| The override is a documented test hook with no lock | `scripts/build-app.sh:64-65` | comment `STATUS_TRIO_SDK_VERSION_OVERRIDE exists only so this guard can be tested` |
| The install docs strip quarantine | `README.md:157`, `AGENTS.md:67` | `xattr -dr com.apple.quarantine "/Applications/Status Trio.app"` |

Confirmed against the built bundle during planning: `vtool -show-build dist/StatusTrio.app/Contents/MacOS/StatusTrio` reports `minos 15.0`, `sdk 26.0` while this machine's `xcrun --sdk macosx --show-sdk-version` reports `27.0` — the artifact advertises a value nothing measured. `codesign -dv --verbose=4 dist/StatusTrio.app` reports `flags=0x2(adhoc)` with no runtime, and `spctl -a -vv dist/StatusTrio.app` prints `rejected`.

## Review Focus

- **An SDK stamp that lies produces the exact bug issue #40 is about.** `scripts/build-app.sh:192` writes `sdk 26.0` regardless of the SDK in use, and `scripts/verify-platform-version.sh:58` then compares that same field against `26`, so the assertion can only pass. Task 3 makes the stamp the measured value and Task 4 makes the assertion compare the stamped value against the measured parameter; the pinning command is `bash scripts/verify-platform-version.sh <binary> 15.0 26 26.0` against a `27.0`-stamped binary, which must fail.
- **A naive hardened-runtime change ships a non-launchable app.** Adding `--options runtime` to both `codesign` calls makes dyld refuse to load `Sparkle.framework` (Measured Prerequisite 2). Task 2 leaves the Ad-hoc path unchanged and Task 5 proves the entitlement path still launches; the pinning commands are `codesign -dv` showing `flags=0x2(adhoc)` with no `runtime`, plus a launch whose process is still alive after 3 seconds.
- **`--deep` gives nested executables entitlements they do not need.** Measured Prerequisite 5 shows `Updater.app` inheriting `disable-library-validation`. Task 3 replaces `--deep` with an explicit ordered list; the pinning command is `codesign -d --entitlements - <bundle>/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app` returning empty while the main app returns the entitlement.
- **The install docs ask users to remove the only Gatekeeper signal and offer a checksum that cannot substitute for it.** `README.md:157` and `AGENTS.md:67` tell users to run `xattr -dr com.apple.quarantine` on an unnotarized binary, and the SHA-256 comes from the same release an attacker who controls the feed would control. Task 6 rewrites this as an explicit trust decision; the pinning command is `grep -c "notarized by Apple" README.md` and `grep -c "cannot protect you" README.md`, plus `grep -c "notarized" AGENTS.md` remaining non-zero so the Ad-hoc limitation stays documented.
- **The release preflight is the only end-to-end proof these scripts work.** `scripts/release.sh` requires `scripts/release-notes/<version>` to exist and calls `scripts/build-app.sh` at line 161 and `scripts/verify-platform-version.sh` transitively through it, so a signature change that breaks packaging is caught only there. Task 7 pins it with the `publish=false` dispatch and `gh run watch --exit-status`.

### Task 1: Capture the hardened-runtime failure as a prerequisite, not a discovery

**Files:**
- No file changes. This task produces the evidence Task 2 and Task 5 depend on.

**Interfaces:**
- Consumes: an existing built bundle at `dist/StatusTrio.app` (produced by `bash scripts/build-app.sh release no-open`).
- Produces: a recorded, reproducible sequence that shows `--options runtime` without an entitlement is a build-breaking change.

- [ ] **Step 1: Confirm the current signature has no hardened runtime**

```bash
codesign -dv --verbose=4 dist/StatusTrio.app 2>&1 | grep -E "flags|TeamIdentifier|Runtime"
```

Expected:

```text
CodeDirectory v=20400 size=8976 flags=0x2(adhoc) hashes=274+3 location=embedded
TeamIdentifier=not set
```

No `runtime` in the flags and no `Runtime Version` line. If `runtime` appears, the bundle in `dist/` was built by a modified script and this task's baseline does not apply.

- [ ] **Step 2: Reproduce the dyld failure on a throwaway copy**

Never sign `dist/StatusTrio.app` here; the experiment replaces its signature.

```bash
T="$(mktemp -d)"
cp -R dist/StatusTrio.app "$T/app"
F="$T/app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --options runtime "$F"
codesign --force --sign - --options runtime "$T/app"
codesign -dv --verbose=4 "$T/app" 2>&1 | grep -E "flags|TeamIdentifier"
"$T/app/Contents/MacOS/StatusTrio" 2>&1 | head -4
echo "exit=$?"
```

Expected: `flags=0x10002(adhoc,runtime)` and `TeamIdentifier=not set`, then a dyld diagnostic containing `Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle` and `mapping process and mapped file (non-platform) have different Team IDs`. The non-zero exit is the point of this step: it is the failure a blanket `--options runtime` change would ship.

- [ ] **Step 3: Confirm the signature itself still verifies, so the failure is purely at load time**

```bash
codesign --verify --strict --verbose=2 "$T/app" 2>&1 | tail -2
```

Expected: `valid on disk` and `satisfies its Designated Requirement`. The bundle is correctly signed and still cannot launch — do not treat a passing `codesign --verify` as evidence that a runtime change is safe.

- [ ] **Step 4: Confirm the entitlement is a targeted opt-out, in isolation**

```bash
cat > "$T/lv.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.cs.disable-library-validation</key><true/></dict></plist>
EOF
plutil -lint "$T/lv.entitlements"
codesign --force --sign - --options runtime --entitlements "$T/lv.entitlements" "$F"
codesign --force --sign - --options runtime --entitlements "$T/lv.entitlements" "$T/app"
codesign -d --entitlements - "$T/app" 2>&1 | grep -c disable-library-validation
"$T/app/Contents/MacOS/StatusTrio" 2>&1 | head -4
echo "exit=$?"
rm -rf "$T"
```

Expected: `lv.entitlements: OK`, then `1`, then **no** dyld diagnostic. The process exits non-zero or zero depending on whether an instance is already running, which is irrelevant here — what matters is the absence of `different Team IDs`. If the diagnostic is still present, the entitlement name is wrong and Task 5 must not be attempted.

- [ ] **Step 5: Record the outcome and commit nothing**

There are no file changes. This task is complete when Steps 1-4 have all been observed on the current bundle. If Step 4 does not suppress the diagnostic, record that fact and take option (a) in Task 2.

### Task 2: Keep the Ad-hoc path runtime-free, and make that deliberate

**Files:**
- Modify: `scripts/build-app.sh`

**Interfaces:**
- Consumes: the evidence from Task 1.
- Produces: an explicit `RUNTIME_SIGNING` decision variable, a comment explaining why the Ad-hoc path omits `--options runtime`, and a refusal to combine `--options runtime` with a missing library-validation entitlement.

This task deliberately does **not** enable the hardened runtime on the Ad-hoc path. Measured Prerequisite 3 makes the entitlement path technically viable but it is a trade, not an upgrade: it turns library validation off explicitly, and it would need every future nested-binary load to be re-verified by actually launching the app. That is more moving parts than the current threat model justifies for a personal-use Ad-hoc build, and the real fix is the Developer ID path in Task 8. The valuable change here is that the reason is written down and the mistake is made impossible.

- [ ] **Step 1: Confirm the decision is currently implicit**

```bash
sed -n '200,207p' scripts/build-app.sh
grep -c "RUNTIME_SIGNING" scripts/build-app.sh
```

Expected: the `SIGNING_IDENTITY` default and the `if [[ "$SIGNING_IDENTITY" != "-" ]]` block, then `0`.

- [ ] **Step 2: Replace the signing block with a documented decision**

Replace `scripts/build-app.sh:196-211` with:

```bash
# The declared minimum is the expected value for every slice, so a slice that
# alone requires a newer macOS is caught here rather than by a user.
bash "$ROOT/scripts/verify-platform-version.sh" "$CONTENTS/MacOS/StatusTrio" "$DECLARED_MINOS"

# The hardened runtime is enabled only for a real signing identity.
#
# `--options runtime` turns on library validation, which requires the executable
# and every library it loads to share a Team ID. An Ad-hoc signature has no Team
# ID, so enabling the runtime here makes dyld refuse to load the embedded
# Sparkle.framework and ships an app that cannot launch:
#
#   Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
#   ... mapping process and mapped file (non-platform) have different Team IDs
#
# The only way to keep the runtime on an Ad-hoc build is to add
# com.apple.security.cs.disable-library-validation, which switches library
# validation back off and therefore buys less than it costs. Do not do it here.
# See docs/superpowers/plans/2026-09-20-build-signing-hardening.md and issue #40.
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$ROOT/Support/StatusTrio.entitlements}"
ENTITLEMENT_KEY="com.apple.security.cs.disable-library-validation"

RUNTIME_SIGNING=0
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    RUNTIME_SIGNING=1
elif [[ "${STATUS_TRIO_RUNTIME_SIGNING:-0}" == "1" ]]; then
    RUNTIME_SIGNING=1
fi

if [[ "$RUNTIME_SIGNING" == "1" && "${STATUS_TRIO_ALLOW_RUNTIME_WITHOUT_TEAM:-0}" != "1" ]]; then
    GRANTED="$(/usr/libexec/PlistBuddy -c "Print :${ENTITLEMENT_KEY}" "$ENTITLEMENTS_PATH" 2>/dev/null || true)"
    if [[ "$GRANTED" != "true" ]]; then
        echo "Error: the hardened runtime requires a Team ID or an explicit" >&2
        echo "       ${ENTITLEMENT_KEY} entitlement in ${ENTITLEMENTS_PATH}." >&2
        echo "       Without one, Sparkle.framework cannot be loaded at runtime." >&2
        exit 2
    fi
fi

SIGNING_ARGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$RUNTIME_SIGNING" == "1" ]]; then
    SIGNING_ARGS+=(--options runtime --timestamp)
    if [[ -n "${KEYCHAIN_PATH:-}" ]]; then
        SIGNING_ARGS+=(--keychain "$KEYCHAIN_PATH")
    fi
fi
```

Two notes on the guard. It reads the entitlements file as a **plist** with `PlistBuddy` rather than grepping it, because `Support/StatusTrio.entitlements` documents the rejected alternative in an XML comment: a `grep -q` for the key name matches that comment and would let the runtime through without the entitlement ever being applied. Measured during planning — `PlistBuddy -c 'Print :com.apple.security.cs.disable-library-validation'` exits `0` and prints `true` for an active key, and exits `1` with `Does Not Exist` when the key appears only inside a comment. It also inspects the file rather than the signed bundle because it runs before the first `codesign` invocation, and `codesign -d --entitlements -` on an unsigned or missing path prints `No such file or directory` while still exiting `0`, which would silently pass. The `STATUS_TRIO_ALLOW_RUNTIME_WITHOUT_TEAM` escape hatch exists only so the refusal itself can be regression-tested; nothing in the release path sets it.

The `--deep` flag is intentionally absent: Task 3 adds the explicit nested-code invocations that replace it.

- [ ] **Step 3: Prove the refusal fires without a real identity**

```bash
STATUS_TRIO_RUNTIME_SIGNING=1 bash scripts/build-app.sh release no-open; echo "exit=$?"
```

Expected: exit `2` with `Error: the hardened runtime requires a Team ID or an explicit` and `com.apple.security.cs.disable-library-validation entitlement in`. This is the guard that stops a reviewer from "hardening" the Ad-hoc path by flipping one variable. Before Task 5 creates `Support/StatusTrio.entitlements`, the `PlistBuddy` read fails with a missing file and the same refusal fires, so this step is valid to run before Task 5.

- [ ] **Step 4: Prove the escape hatch is what allows the runtime, and nothing else**

```bash
STATUS_TRIO_RUNTIME_SIGNING=1 STATUS_TRIO_ALLOW_RUNTIME_WITHOUT_TEAM=1 bash scripts/build-app.sh release no-open
codesign -dv --verbose=4 dist/StatusTrio.app 2>&1 | grep -E "flags|Runtime"
"dist/StatusTrio.app/Contents/MacOS/StatusTrio" 2>&1 | head -3
```

Expected: the build succeeds, `codesign` reports `flags=0x10002(adhoc,runtime)`, and the launch prints the `different Team IDs` dyld diagnostic from Measured Prerequisite 2. This step exists to make the failure reproducible on demand.

- [ ] **Step 5: Rebuild the Ad-hoc bundle so `dist/` is launchable again**

Step 4 deliberately leaves a runtime-signed, non-launchable bundle in `dist/`. Rebuild before anything else uses it:

```bash
bash scripts/build-app.sh release no-open
codesign -dv --verbose=4 dist/StatusTrio.app 2>&1 | grep -E "flags|Runtime"
```

Expected: the build succeeds and prints `flags=0x2(adhoc)` with no `Runtime Version` line.

- [ ] **Step 6: Commit**

```bash
git add scripts/build-app.sh
git commit -m "build: keep the ad-hoc path runtime-free and say why in the script"
```

### Task 3: Replace `--deep` signing with explicit nested signing, and stamp the measured SDK

**Files:**
- Modify: `scripts/build-app.sh`

**Interfaces:**
- Consumes: `RUNTIME_SIGNING` and `SIGNING_ARGS` from Task 2.
- Produces: an ordered explicit `codesign` sequence over the four nested items inside `Sparkle.framework`, and a `vtool` stamp of `${SDK_VERSION}` instead of `26.0`.

Signing order matters: inner-most first. `dist/StatusTrio.app/Contents/Frameworks/Sparkle.framework` contains `Versions/B/XPCServices/Downloader.xpc`, `Versions/B/XPCServices/Installer.xpc`, `Versions/B/Updater.app`, and `Versions/B/Autoupdate` (all confirmed present in the built bundle). Signing the framework before its nested items would invalidate the framework signature.

- [ ] **Step 1: Confirm the stamp is a literal**

```bash
grep -n "vtool -set-build-version" scripts/build-app.sh
vtool -show-build dist/StatusTrio.app/Contents/MacOS/StatusTrio | grep -E "minos|sdk"
xcrun --sdk macosx --show-sdk-version
```

Against the current tree this prints line `192` with `26.0`, then `sdk 26.0`, then `27.0`. The last two lines disagreeing is the defect: the artifact advertises a value that was never measured.

- [ ] **Step 2: Fix the guard so the override cannot be left on by accident**

Replace `scripts/build-app.sh:64-70` with:

```bash
# STATUS_TRIO_SDK_VERSION_OVERRIDE exists only so this guard can be tested. It
# must be demanded explicitly: an accidental override would let the artifact
# advertise an SDK this build never used.
SDK_OVERRIDE="${STATUS_TRIO_SDK_VERSION_OVERRIDE:-}"
if [[ -n "$SDK_OVERRIDE" ]]; then
    if [[ "${STATUS_TRIO_SDK_VERSION_OVERRIDE_ACK:-}" != "1" ]]; then
        echo "Error: STATUS_TRIO_SDK_VERSION_OVERRIDE is set but not acknowledged." >&2
        echo "       Set STATUS_TRIO_SDK_VERSION_OVERRIDE_ACK=1 to use it deliberately." >&2
        exit 2
    fi
    SDK_VERSION="$SDK_OVERRIDE"
    echo "Warning: using SDK version override ${SDK_VERSION}; this build is a guard test." >&2
else
    SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
fi

if [[ -z "${SDK_VERSION%%.*}" || "${SDK_VERSION%%.*}" == *[!0-9]* ]]; then
    echo "Error: could not determine the macOS SDK version (got '${SDK_VERSION}')." >&2
    exit 2
fi

if [[ "${SDK_VERSION%%.*}" -lt 26 ]]; then
    echo "Error: Status Trio must be built with the macOS 26 SDK or newer; found ${SDK_VERSION}." >&2
    echo "       An older SDK silently ships the pre-Tahoe popover appearance." >&2
    exit 2
fi
```

The guard is not weakened: an older SDK still fails, and a non-numeric `xcrun` result now fails loudly instead of aborting on a bash arithmetic error.

- [ ] **Step 3: Prove the guard still refuses an old SDK and that the override needs the acknowledgement**

```bash
STATUS_TRIO_SDK_VERSION_OVERRIDE=25.4 bash scripts/build-app.sh release no-open; echo "exit=$?"
STATUS_TRIO_SDK_VERSION_OVERRIDE=25.4 STATUS_TRIO_SDK_VERSION_OVERRIDE_ACK=1 bash scripts/build-app.sh release no-open; echo "exit=$?"
```

Expected: the first exits `2` with `is set but not acknowledged`; the second prints `Warning: using SDK version override 25.4` and then exits `2` with `must be built with the macOS 26 SDK or newer; found 25.4`. Both paths refuse; only the second reaches the SDK-age check.

- [ ] **Step 4: Stamp the measured SDK**

Replace `scripts/build-app.sh:191-194` with:

```bash
# Stamp the SDK this build actually used. Hardcoding a literal here would make
# scripts/verify-platform-version.sh assert the value this script just wrote,
# which is a tautology; the stamp must be the measured version so the assertion
# has something independent to compare against.
VTMP_BINARY="$(mktemp "${TMPDIR:-/tmp}/StatusTrio.vtool.XXXXXX")"
xcrun vtool -set-build-version macos "$BUILT_MINOS" "$SDK_VERSION" -replace -output "$VTMP_BINARY" "$CONTENTS/MacOS/StatusTrio"
mv "$VTMP_BINARY" "$CONTENTS/MacOS/StatusTrio"
chmod +x "$CONTENTS/MacOS/StatusTrio"
```

- [ ] **Step 5: Apply the explicit nested signing sequence**

Replace the two `codesign` calls in the block written by Task 2 with:

```bash
SPARKLE_FRAMEWORK="$CONTENTS/Frameworks/Sparkle.framework"

# Sign inner-most first. `--deep` is deprecated for signing and also propagates
# the app's entitlements to every nested binary, which hands
# Sparkle's Updater.app entitlements it does not need. This explicit order is
# what Apple documents for manual signing and it keeps each decision visible.
codesign "${SIGNING_ARGS[@]}" "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGNING_ARGS[@]}" "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGNING_ARGS[@]}" "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
codesign "${SIGNING_ARGS[@]}" "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
codesign "${SIGNING_ARGS[@]}" "$SPARKLE_FRAMEWORK"
codesign "${SIGNING_ARGS[@]}" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
```

`--deep` stays on the `--verify` line on purpose: verification is exactly what it is still for.

- [ ] **Step 6: Prove the explicit order still verifies and every nested item is signed**

```bash
bash scripts/build-app.sh release no-open
codesign --verify --deep --strict --verbose=2 dist/StatusTrio.app 2>&1 | tail -2
for p in Contents/MacOS/StatusTrio \
  Contents/Frameworks/Sparkle.framework \
  Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app \
  Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate \
  Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc \
  Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc; do
  printf '%-72s %s\n' "$p" "$(codesign -dv "dist/StatusTrio.app/$p" 2>&1 | grep -o 'flags=[^ ]*' | head -1)"
done
```

Expected: `valid on disk` / `satisfies its Designated Requirement`, then `flags=0x2(adhoc)` for all six paths. An empty flags column means that item was skipped.

- [ ] **Step 7: Commit**

```bash
git add scripts/build-app.sh
git commit -m "build: sign Sparkle explicitly instead of with --deep and stamp the measured SDK"
```

### Task 4: Make the platform-version assertion compare two independent values

**Files:**
- Modify: `scripts/verify-platform-version.sh`

**Interfaces:**
- Consumes: the `$SDK_VERSION` stamp from Task 3.
- Produces: an optional fourth argument `expected-sdk`; when given, every slice's `sdk` must equal it exactly, in addition to the existing `minos` and minimum-major checks.

Without the fourth argument the script behaves as before, so existing callers keep working.

- [ ] **Step 1: Confirm the assertion is currently self-referential**

```bash
sed -n '53,61p' scripts/verify-platform-version.sh
grep -c "EXPECTED_SDK" scripts/verify-platform-version.sh
```

Expected: the `sdk_major < MINIMUM_SDK_MAJOR` block, then `0`.

- [ ] **Step 2: Accept and enforce an expected SDK**

Change the usage line and argument parsing:

```bash
# Usage: verify-platform-version.sh <binary> <expected-minos> [minimum-sdk-major] [expected-sdk]
```

```bash
MINIMUM_SDK_MAJOR="${3:-26}"
EXPECTED_SDK="${4:-}"
```

and add, immediately after the existing `minos` check inside the per-architecture loop:

```bash
    if [[ -n "$EXPECTED_SDK" && "$sdk" != "$EXPECTED_SDK" ]]; then
        echo "Error: ${arch}: built against SDK ${sdk}, but the build measured SDK ${EXPECTED_SDK}." >&2
        echo "       The LC_BUILD_VERSION stamp does not match the SDK that was used." >&2
        FAILED=1
    fi
```

Also extend the final success line so the asserted value is visible in CI logs:

```bash
printf '%s: minos %s, sdk %s\n' "$arch" "$minos" "$sdk"
```

stays as the per-arch print, and the summary becomes:

```bash
echo "LC_BUILD_VERSION check passed for $BINARY (minos ${EXPECTED_MINOS}${EXPECTED_SDK:+, sdk ${EXPECTED_SDK}})"
```

- [ ] **Step 3: Prove the assertion can now fail on a mismatch**

Build a contradicting artifact from a copy, so the real bundle is untouched:

```bash
T="$(mktemp -d)"; cp dist/StatusTrio.app/Contents/MacOS/StatusTrio "$T/real"
xcrun vtool -set-build-version macos 15.0 26.0 -replace -output "$T/claimed-26" "$T/real"
bash scripts/verify-platform-version.sh "$T/claimed-26" 15.0 26 27.0; echo "exit=$?"
bash scripts/verify-platform-version.sh "$T/claimed-26" 15.0 26 26.0; echo "exit=$?"
```

Expected: the first exits `1` with `built against SDK 26.0, but the build measured SDK 27.0`; the second exits `0` with `LC_BUILD_VERSION check passed`. This is the check that Issue #40 needed: the previous script passed both.

- [ ] **Step 4: Prove the old call shape still works**

```bash
bash scripts/verify-platform-version.sh dist/StatusTrio.app/Contents/MacOS/StatusTrio 15.0; echo "exit=$?"
```

Expected: exit `0`. A change that breaks the three-argument form would break `scripts/build-app.sh` on any branch that has not yet picked up Task 3.

- [ ] **Step 5: Commit**

```bash
git add scripts/verify-platform-version.sh
git commit -m "build: assert the stamped SDK equals the measured SDK"
```

### Task 5: Add the entitlements file and record the rejected alternative

**Files:**
- Create: `Support/StatusTrio.entitlements`

**Interfaces:**
- Consumes: Task 2's check for `disable-library-validation`, and Measured Prerequisite 3.
- Produces: a committed, empty entitlements file with a comment explaining why it is empty, so a future runtime decision has a place to live.

Writing the comment into real XML rather than only into the plan is the point: the next person to consider `--options runtime` will be reading this file.

- [ ] **Step 1: Confirm no entitlements file exists**

```bash
find . -name '*.entitlements' -not -path './.build/*' -not -path './.worktrees/*'
```

Expected: no output.

- [ ] **Step 2: Create the file**

`Support/StatusTrio.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!--
	Intentionally empty.

	Status Trio ships Ad-hoc signed because this repository has no Developer ID
	certificate. An Ad-hoc signature grants no entitlements, and the app needs
	none: it is not sandboxed, it uses no restricted API, and Sparkle runs inside
	the app process.

	If a Developer ID certificate is ever added, this file is where the
	hardened-runtime entitlements belong. The one to think hard about is
	com.apple.security.cs.disable-library-validation: it is the only way to keep
	`--options runtime` on a build whose libraries do not share the app's Team ID,
	and it turns library validation back off, so it trades one protection for
	another rather than adding one. Prefer putting Sparkle and the app under the
	same Team ID over disabling library validation.

	Commented-out example, for that future decision only:

	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
	-->
</dict>
</plist>
```

- [ ] **Step 3: Prove the file is valid and that the Ad-hoc path does not require it**

```bash
plutil -lint Support/StatusTrio.entitlements
bash scripts/build-app.sh release no-open
codesign -d --entitlements - dist/StatusTrio.app 2>&1 | tail -3
```

Expected: `Support/StatusTrio.entitlements: OK`, a successful build, and no entitlement dictionary in the output.

- [ ] **Step 4: Confirm the file does not accidentally satisfy the Task 2 guard**

Task 2's refusal branch reads this file as a plist with `PlistBuddy`, so the key being present only inside an XML comment must not satisfy it. Verify that directly, and verify that activating the key does satisfy it — that pair is what proves the guard reads the plist rather than the raw bytes.

```bash
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.cs.disable-library-validation' Support/StatusTrio.entitlements; echo "print exit=$?"
STATUS_TRIO_RUNTIME_SIGNING=1 bash scripts/build-app.sh release no-open; echo "guard exit=$?"
```

Expected: `Does Not Exist` with `print exit=1`, then `guard exit=2`. If the guard exits `0`, it is matching the comment text and must be changed to the `PlistBuddy` form from Task 2 before this task is complete.

- [ ] **Step 5: Prove the activated key opens the guard, then revert it**

```bash
cp Support/StatusTrio.entitlements /tmp/st-entitlements.bak
python3 - <<'PY'
import re
p = 'Support/StatusTrio.entitlements'
s = open(p).read()
active = "\t<key>com.apple.security.cs.disable-library-validation</key>\n\t<true/>\n"
s = s.replace("\t<key>com.apple.security.cs.disable-library-validation</key>\n\t<true/>\n\t-->\n", "\t-->\n" + active, 1)
open(p, 'w').write(s)
PY
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.cs.disable-library-validation' Support/StatusTrio.entitlements; echo "print exit=$?"
STATUS_TRIO_RUNTIME_SIGNING=1 bash scripts/build-app.sh release no-open; echo "guard exit=$?"
codesign -dv --verbose=4 dist/StatusTrio.app 2>&1 | grep -E "flags|Runtime"
codesign -d --entitlements - dist/StatusTrio.app 2>&1 | grep -c disable-library-validation
"dist/StatusTrio.app/Contents/MacOS/StatusTrio" 2>&1 | head -3
cp /tmp/st-entitlements.bak Support/StatusTrio.entitlements
bash scripts/build-app.sh release no-open
git diff --stat Support/StatusTrio.entitlements
```

Expected: `true` with `print exit=0`; `guard exit=0`; `flags=0x10002(adhoc,runtime)`; `1` entitlement match; no dyld diagnostic on launch. The final `cp` restores the file and `git diff --stat` must print nothing, because the file that ships is the one with the key commented out.

This step is the honest cost of the entitlement: it works, it is verifiable, and it is still not taken on the Ad-hoc path. Recording it here means the next reviewer can re-run it in one minute instead of re-discovering the dyld failure.

- [ ] **Step 6: Commit**

```bash
git add Support/StatusTrio.entitlements
git commit -m "build: add the entitlements file with the runtime decision recorded"
```

### Task 6: Rewrite the Gatekeeper and quarantine guidance as a trust decision

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `README.zh-CN.md`

**Interfaces:**
- Consumes: the Ad-hoc limitation, unchanged by this plan.
- Produces: installer guidance that states what the user is accepting, what the checksum does and does not protect against, and keeps the Ad-hoc limitation explicit.

- [ ] **Step 1: Confirm the current wording**

```bash
grep -n "xattr -dr" README.md AGENTS.md README.zh-CN.md
grep -c "cannot protect you" README.md
```

Expected: `README.md:157`, `AGENTS.md:67`, and whichever line `README.zh-CN.md` uses, then `0`.

- [ ] **Step 2: Replace the README passage around line 157**

Keep these facts and add the framing:

- The build is Ad-hoc signed and **not notarized by Apple** — keep this sentence.
- Gatekeeper warning is expected; it is not evidence of malware.
- The published SHA-256 verifies that the file arrived intact. It **cannot** verify who published it, because the checksum and the DMG come from the same release; an attacker who can publish the release can publish a matching checksum.
- Only remove quarantine when the DMG came from the official Releases page, and prefer **System Settings → Privacy & Security → Open Anyway** over `xattr`, because it is the documented flow and leaves an auditable record.
- Do not disable Gatekeeper globally.
- Sparkle updates are authenticated by the EdDSA key, so `xattr` is normally needed only for the first manual install.

- [ ] **Step 3: Update `AGENTS.md:67`**

Change the release-body rule from a bare command recipe to one that requires the trust framing, so future release bodies keep the explanation:

```markdown
- GitHub Release bodies must append the first-launch commands `xattr -dr com.apple.quarantine "/Applications/Status Trio.app"` and `open "/Applications/Status Trio.app"` after the bilingual notes, preceded by a short statement that the build is Ad-hoc signed and not notarized, that removing quarantine is a trust decision the user makes, and that the published SHA-256 only proves the download was not corrupted in transit. Do not include these commands in the Sparkle appcast.
```

- [ ] **Step 4: Mirror the change in `README.zh-CN.md`**

Use the same three facts, matching the terminology already used in `Sources/StatusTrioCore/Resources/zh-Hans.lproj`.

- [ ] **Step 5: Prove the framing is present and the limitation is still stated**

```bash
grep -c "not notarized by Apple" README.md
grep -c "cannot verify who published" README.md
grep -c "notarized" AGENTS.md
grep -c "xattr -dr" README.md AGENTS.md README.zh-CN.md
```

Expected: `1`, `1`, a non-zero count for `notarized` in `AGENTS.md`, and one `xattr -dr` match in each of the three files. A zero for the last group means the install steps were deleted rather than re-framed, which would break the documented path.

- [ ] **Step 6: Commit**

```bash
git add README.md README.zh-CN.md AGENTS.md
git commit -m "docs: explain the ad-hoc trust decision behind removing quarantine"
```

### Task 7: Verify the whole pipeline still works

**Files:**
- No file changes.

**Interfaces:**
- Consumes: Tasks 2-6.
- Produces: the preflight evidence that the release path is intact.

- [ ] **Step 1: Lint the scripts**

```bash
bash -n scripts/build-app.sh
bash -n scripts/verify-platform-version.sh
bash scripts/validate-appcast-notes.sh
```

Expected: no output from `bash -n`, and the appcast validator's normal success output.

- [ ] **Step 2: Build and confirm the claimed values are real**

```bash
bash scripts/build-app.sh release no-open
vtool -show-build dist/StatusTrio.app/Contents/MacOS/StatusTrio | grep -E "minos|sdk"
xcrun --sdk macosx --show-sdk-version
codesign -dv --verbose=4 dist/StatusTrio.app 2>&1 | grep -E "flags|TeamIdentifier"
spctl -a -vv dist/StatusTrio.app 2>&1 | head -2
```

Expected: `sdk` matches `xcrun --show-sdk-version` (both `27.0` on this machine, both `26.x` on the `macos-26` runner), `flags=0x2(adhoc)` with no runtime, and `spctl` printing `rejected`. The rejection is expected for an unnotarized Ad-hoc build and is exactly what Task 6 documents.

- [ ] **Step 3: Confirm the Ad-hoc bundle launches without a dyld diagnostic**

```bash
pkill -f "Status Trio.app/Contents/MacOS/StatusTrio" 2>/dev/null || true
open dist/StatusTrio.app
sleep 3
pgrep -fl "Status Trio.app/Contents/MacOS/StatusTrio"
```

Expected: `pgrep` prints a PID. An empty result means dyld refused the bundle — check `log show --last 1m --predicate 'process == "StatusTrio"'` for a `Library not loaded` diagnostic before blaming anything else.

- [ ] **Step 4: Open the popover once and confirm the app is functional**

Click the menu bar icon and confirm the popover opens with live battery, Wi-Fi, and volume rows. This is a manual step because the popover is an `NSPopover` attached to a status item; there is no supported CLI hook. Confirm from the menu bar icon's context menu that the version matches `Support/Info.plist`.

- [ ] **Step 5: Run the Swift checks**

```bash
swift test
swift build -c release
```

Expected: all tests pass and the release build succeeds. These scripts do not change Swift code, but the repository requires both for any change.

- [ ] **Step 6: Run the non-publishing release preflight**

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref <branch> \
  -f version=1.3.0 \
  -f build=12 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: the workflow passes without publishing, the DMG is created, and the `vtool` check inside `scripts/build-app.sh` asserts the SDK that the `macos-26` runner actually has. If the runner's SDK is 26.x and the stamp or assertion disagrees, that is a real failure of Task 3 or Task 4 and must be fixed before merge.

- [ ] **Step 7: Record any failed run**

Append any failed run to `docs/swift-ci-compatibility.md` with its run ID, failed stage, root cause, and fix, per the repository rule.

### Task 8: Conditional follow-up — activate the Developer ID path

**Files:**
- Modify later: `scripts/build-app.sh`
- Modify later: `.github/workflows/release.yml` (owned by the release-pipeline plan; coordinate before editing)
- Keep unchanged: `Support/Info.plist` `SUPublicEDKey`

**Interfaces:**
- Consumes: a paid Apple Developer Program membership and a `Developer ID Application` certificate.
- Produces: hardened-runtime, notarized releases with no change to the Sparkle trust root.

**This task is not a prerequisite for anything above and must not be started without the certificate.** It is written as a follow-up so no earlier task assumes a Developer ID.

- [ ] **Step 1: Confirm the certificate is actually available**

```bash
security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p'
```

Expected: at least one identity. No output means this task stops here.

- [ ] **Step 2: Add the hardened-runtime entitlements**

Move the entitlement that is needed for Sparkle under a shared Team ID, if any, into `Support/StatusTrio.entitlements`. With both binaries under one Team ID, library validation passes and `disable-library-validation` should stay commented out.

- [ ] **Step 3: Sign with the identity**

```bash
CODE_SIGN_IDENTITY="Developer ID Application: <name> (<team>)" bash scripts/build-app.sh release no-open
codesign -dv --verbose=4 dist/StatusTrio.app 2>&1 | grep -E "flags|TeamIdentifier|Runtime"
```

Expected: `flags=0x10000(runtime)`, a real `TeamIdentifier`, and a `Runtime Version` line.

- [ ] **Step 4: Notarize and staple**

```bash
xcrun notarytool submit dist/StatusTrio-<version>.dmg --keychain-profile status-trio-notary --wait
xcrun stapler staple dist/StatusTrio-<version>.dmg
xcrun stapler validate dist/StatusTrio-<version>.dmg
spctl -a -vv dist/StatusTrio.app
```

Expected: `spctl` prints `accepted` with `source=Notarized Developer ID`. Only then does Task 6's guidance change from "a decision you make" to a normal install.

- [ ] **Step 5: Run the preflight with Ad-hoc still the fallback**

```bash
gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false
gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: passes. The workflow's `Configure Developer ID signing` step is conditional, so a run without the secrets must keep working exactly as before.

## Verification

- `bash -n scripts/build-app.sh` and `bash -n scripts/verify-platform-version.sh` produce no output; `plutil -lint Support/StatusTrio.entitlements` prints `OK`.
- `vtool -show-build dist/StatusTrio.app/Contents/MacOS/StatusTrio | grep sdk` prints the same value as `xcrun --sdk macosx --show-sdk-version`. Before the change these disagreed (`sdk 26.0` versus `27.0` on this machine).
- `bash scripts/verify-platform-version.sh "$T/claimed-26" 15.0 26 27.0` exits `1` with `built against SDK 26.0, but the build measured SDK 27.0`; the same command with `26.0` exits `0`. Before the change both exited `0`, because the script only compared the field against itself. Reproduce `$T/claimed-26` with `cp dist/StatusTrio.app/Contents/MacOS/StatusTrio "$T/real"` then `xcrun vtool -set-build-version macos 15.0 26.0 -replace -output "$T/claimed-26" "$T/real"`.
- `bash scripts/verify-platform-version.sh dist/StatusTrio.app/Contents/MacOS/StatusTrio 15.0` still exits `0`, so the three-argument callers keep working.
- `STATUS_TRIO_SDK_VERSION_OVERRIDE=25.4 bash scripts/build-app.sh release no-open` exits `2` with `is set but not acknowledged`, and adding `STATUS_TRIO_SDK_VERSION_OVERRIDE_ACK=1` makes it exit `2` with `must be built with the macOS 26 SDK or newer; found 25.4`.
- `STATUS_TRIO_RUNTIME_SIGNING=1 bash scripts/build-app.sh release no-open` exits `2` with `the hardened runtime requires a Team ID or an explicit`; `/usr/libexec/PlistBuddy -c 'Print :com.apple.security.cs.disable-library-validation' Support/StatusTrio.entitlements` exits `1` with `Does Not Exist`, proving the guard reads the plist rather than the comment text.
- `codesign --verify --deep --strict --verbose=2 dist/StatusTrio.app` prints `valid on disk` and `satisfies its Designated Requirement`, and all six nested paths report `flags=0x2(adhoc)`.
- `codesign -dv --verbose=4 dist/StatusTrio.app | grep flags` shows no `runtime`, matching `flags=0x2(adhoc)`.
- After `open dist/StatusTrio.app`, `sleep 3`, `pgrep -fl "Status Trio.app/Contents/MacOS/StatusTrio"` prints a PID, and the popover opens with live rows.
- `spctl -a -vv dist/StatusTrio.app` prints `rejected`, and `README.md` explains both why that is expected and what removing quarantine actually accepts.
- `swift test` and `swift build -c release` pass.
- `gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false` followed by `gh run watch <run-id> --repo lingyired/status-trio --exit-status` exits 0.

## Out of Scope

- `.github/workflows/release.yml`, apart from the release-body wording that the release-pipeline plan owns. The keychain `-A` removal and the environment gate belong to that plan.
- `scripts/release.sh`. It passes `CODE_SIGN_IDENTITY` and `KEYCHAIN_PATH` through (lines 159-160) and needs no change for this plan.
- Turning the hardened runtime on for the Ad-hoc path. Measured Prerequisite 3 makes it possible only with `disable-library-validation`, which is a trade rather than an upgrade; Task 5 records the decision in `Support/StatusTrio.entitlements` instead.
- Rotating `SUPublicEDKey` or changing the Sparkle trust root. `Support/Info.plist` is untouched.
- Raising `LSMinimumSystemVersion` above the `15.0` declared in `Support/Info.plist:LSMinimumSystemVersion`; `scripts/build-app.sh:185-189` already asserts it against the compiled deployment target.
- Unit tests for these scripts. They are shell and code-signing behaviour; every step above is verified by a command with an expected output rather than by a test target.

## File Ownership & Conflicts

- `scripts/build-app.sh` is owned exclusively by this plan. It does not touch `.github/workflows/release.yml`; the workflow calls `bash scripts/release.sh`, which calls `bash scripts/build-app.sh` at `scripts/release.sh:161`, so the new `RUNTIME_SIGNING` guard runs inside CI without any workflow edit.
- `scripts/verify-platform-version.sh` is owned exclusively by this plan. Its new fourth argument defaults to empty and reproduces the previous behaviour, so a branch that has not yet picked up Task 3 keeps working.
- `README.md` is touched by both this plan (Task 6, the quarantine guidance) and the release-pipeline plan (which only changes the text its workflow prints into a GitHub Release body). These are different locations and should not conflict; if they do, keep this plan's framing and re-apply the release-body wording.
- `AGENTS.md:67` is owned by this plan. Task 6 rewrites the release-body rule; the release-pipeline plan must not edit that line.
- `Support/StatusTrio.entitlements` is created by this plan and referenced by nothing else. `Support/Info.plist` is untouched.
- `docs/swift-ci-compatibility.md` may be appended to by Task 7 Step 7 and by the release-pipeline plan; land those as separate commits.
- `docs/superpowers/plans/2026-09-20-release-pipeline-hardening.md` and `docs/superpowers/plans/2026-09-20-test-gate-workflow.md` are sibling plans. Neither may edit the files owned here, and this plan may not edit `.github/workflows/release.yml` or create `.github/workflows/ci.yml`.
