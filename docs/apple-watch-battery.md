# iPhone and Apple Watch battery readings

## Setup

1. In **Settings → Bluetooth**, enable **iPhone and Apple Watch battery**.
2. Connect the iPhone to the Mac over USB. On the iPhone, accept **Trust This Computer** if asked. Status Trio does not initiate pairing or change trust settings.
3. For wireless reads, configure Wi-Fi syncing for the iPhone in Finder yourself. The app uses an already-configured route and does not enable Wi-Fi syncing.
4. Keep the iPhone and Watch paired as usual. The Watch reading is obtained through its trusted parent iPhone; the Watch does not need a separate Mac pairing.

The setting is off by default. Reads are on demand while the Bluetooth device list is visible, refresh periodically while it stays open, and stop when the panel closes. Battery observations are cached for up to 30 minutes across temporary read failures. The helper reads only devices already trusted by macOS. It stores no pairing credentials in Status Trio and routine logs omit device identifiers.

A Watch can appear with the localized fallback name **Apple Watch**. Watch charging state is not currently read. When the phone is temporarily unavailable, an earlier successful reading can remain visible until its observation expires.

## Helper dependencies and redistribution

The app bundles a native helper and universal runtime libraries built from source. Exact upstream repositories, versions, commit pins, and declared licenses are in [`Support/mobile-battery-dependencies.json`](../Support/mobile-battery-dependencies.json). The dependency graph is OpenSSL 3.5.9, libplist 2.8.0, libimobiledevice-glue 1.3.2, libusbmuxd 2.1.1, libtatsu 1.0.5, and libimobiledevice 1.4.0. The corresponding license texts and source rebuild/replacement instructions are in [`Support/MobileBatteryHelper/ThirdPartyNotices/`](../Support/MobileBatteryHelper/ThirdPartyNotices/NOTICE.md).

To rebuild the helper, install the build-only tools `autoconf`, `automake`, `libtool`, and `pkg-config`, then run:

```sh
UNIVERSAL_BUILD=1 bash scripts/build-mobile-battery-helper.sh
```

The build checks out the pinned commits and builds arm64 and x86_64 slices with a macOS 15 deployment target. `scripts/verify-mobile-battery-bundle.sh` checks architectures, deployment versions, macOS SDK adoption, signatures, runtime load paths, transitive dependencies, and a sterile-environment helper invocation. The linked runtime libraries are bundled in the app; Homebrew is not needed at runtime. Recipients can replace an LGPL library with a compatible build from its identified source; see the notice for replacement and re-signing steps.

## Verification record

**Local automated checks — 2026-10-03:** on macOS 27.0.1 with Xcode 27.0 (Swift 6.4, macOS SDK 27.0), `swift test` passed 1,139 XCTest cases (6 skipped, 0 failed) and 475 Swift Testing cases in 76 suites; `swift build -c release` completed. `scripts/test-mobile-battery-helper.sh` passed all 17 native adapter cases. `UNIVERSAL_BUILD=1 bash scripts/build-app.sh release no-open` built and signed the app; the bundle audit passed for arm64 and x86_64. Both slices report macOS 15.0 minimum and SDK 27.0. The packaged app also passed `scripts/verify-mobile-battery-bundle.sh` after copying it to a temporary path containing spaces and invoking the helper with a sterile PATH. The audit's transitive `otool` checks accepted bundled/Apple dependencies and rejected unbundled runpaths; the dedicated rpath and dependency fixtures passed. Appcast-note validation and final diff checks are recorded with the preflight evidence below.

Local logs are retained in the task scratch directory (not shipped): `.superpowers/sdd/2026-10-03-apple-watch-battery/task-5-*.log`.

**Release workflow preflight:** pending dispatch and CI completion. After it finishes, record its URL, run ID, tested commit, actual runner/Xcode/Swift versions, and results for tests, helper build, universal app build/signing, DMG creation, and artifact upload. `publish=false` must leave Release upload and appcast publication skipped. Do not treat a docs-only follow-up commit as the tested implementation SHA.

**Hardware acceptance: PENDING.** At the local check on 2026-10-03, the packaged helper's isolated `--list` command found zero trusted phones. No already-trusted iPhone or paired Watch was available to this check, so USB battery values, Watch readings against device displays, configured Wi-Fi transport, panel reopen, Bluetooth-off behavior, phone disconnect, and cache expiry have not been observed on hardware. Mocks and packaging checks do not resolve this acceptance item. To complete it, connect an already-trusted iPhone by USB, enable the setting, compare iPhone and Watch percentages and charging indications with their displays, then check the existing Wi-Fi-sync route and the documented close/reopen, Bluetooth-off, disconnect, and expiry behavior. Record OS/device versions, transport, observation times, and results here without stable device IDs. Do not pair devices or change Wi-Fi-sync configuration as part of verification.
