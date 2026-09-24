# Audio input controls — acceptance record (2026-09-23)

## Result

**Local automated verification: PASS. Manual hardware acceptance: PARTIAL / NOT VERIFIED. GitHub Actions release preflight: PASS for source SHA `3792b2e56c35ab91ab45b7698df068934984be50` (run [35946682196](https://github.com/lingyired/status-trio/actions/runs/35946682196), `publish=false`).** This record covers Task 7 on branch `codex/audio-input-controls`, starting at `e74fb512785e9f9f96c50a17b4bb1c452928c245`.

## Change boundary

- `git status --short` was empty; `git diff --check` passed.
- Neither `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift` nor `Sources/StatusTrioCore/Audio/CoreAudioOutputController.swift` differs from `origin/main` in this branch.
- `StatusSnapshot` contains battery, Wi-Fi, connection, and output-volume fields only. The input monitor state is held by `SystemStatusStore.liveInput` and passed to `StatusPopoverView`; a scan of status/menu/Dock icon sources found no input-state reference.
- A source scan found no `AVAudioEngine`, `AVAudioRecorder`, `AVCaptureAudioDataOutput`, `AudioQueueNewInput`, or `AudioUnitSetProperty` capture/recording API use. This is a source scan, not a substitute for observing the macOS microphone privacy indicator.

## Automated verification

All commands ran from the repository root:

| Command | Result |
| --- | --- |
| `swift test --filter AudioInput` | PASS — 62 tests, 0 failures |
| `swift test --filter SettingsStoreTests` | PASS — 74 tests, 0 failures |
| `swift test --filter LocalizationParityTests` | PASS — 4 tests, 0 failures |
| `swift test` | PASS — 836 XCTest tests (6 skipped, 0 failures), plus 255 Swift Testing tests in 36 suites passed |
| `swift build -c release` | PASS — production build completed, exit 0 |
| `bash scripts/build-app.sh release no-open` | PASS — app bundle built; deep/strict code-signature verification reported valid on disk and designated requirement satisfied |
| `bash scripts/verify-platform-version.sh 'dist/StatusTrio.app/Contents/MacOS/StatusTrio' 15.0` | PASS — arm64 `minos 15.0`, `sdk 26.0`; `LC_BUILD_VERSION` check passed |
| `VERSION=1.3.3 BUILD=16 PUBLISH=false bash scripts/validate-appcast-notes.sh` | PASS — local non-publishing appcast-note check generated 2 localized titles and descriptions, English first; no workflow was run |

The local toolchain was Xcode 27.0 (build 27A266a), Swift 6.4.0.34.1, and macOS SDK 27.0. The packaged executable reports the required SDK field as 26.0. These local results do **not** establish compatibility with the acceptance runner's macOS 26 / Xcode 26.6 / Swift 6.3.3 toolchain.

The local app bundle is **Ad-hoc signed** (`Signature=adhoc`, no TeamIdentifier). It was not launched. This is not Developer ID signing or notarization.

## Observable hardware baseline and manual matrix

Captured hardware facts are in the ignored companion evidence file `.superpowers/sdd/2026-09-23-audio-input-controls/hardware-observation.txt` (`captured_at_utc=2026-09-23T18:49:56Z`). It records MacBook Pro `Mac15,9`, Apple M3 Max, macOS 27.0 build `26A428`; the built-in `MacBook Pro麦克风` was the default input (one input channel, 44.1 kHz, Built-in). The connected `XV272U` was listed as HDMI output, not an input. No USB or Bluetooth input device appeared in the observed audio-device listing.

Computer-use inspection reported that the Mac was locked and automatic unlock could not unlock it. No app or System Settings interaction was possible. The app was not opened; no permission prompt or microphone privacy indicator was observed. No screenshot was captured. Microphone TCC and Accessibility permission states were not queried and remain unknown.

| Scenario | Observation/result |
| --- | --- |
| Built-in microphone presence/default | **Observed baseline only:** present and default according to the captured system audio-device listing. App selection and readback behavior not exercised. |
| USB input device selection | **NOT VERIFIED:** no USB input device was available in the observed listing. |
| Bluetooth input device selection | **NOT VERIFIED:** no Bluetooth input device was available in the observed listing. |
| App ↔ System Settings “Sound → Input” selection synchronization | **NOT VERIFIED:** UI could not be operated. |
| Input hot-plug and sleep/wake recovery | **NOT VERIFIED:** neither an external input device nor interactive UI was available. |
| External mute/gain changes and confirmed readback | **NOT VERIFIED:** not exercised on hardware. |
| Disable section and verify input enumeration/listeners stop | **NOT VERIFIED:** settings and live monitor behavior were not exercised. |
| Failure/unsupported-control explanation in UI | **NOT VERIFIED:** no UI interaction. |
| Microphone TCC prompt and recording/privacy indicator behavior | **NOT VERIFIED:** app was not launched and no prompt/indicator was observed; permission state is unknown. The source scan above is not evidence of runtime indicator behavior. |

No unavailable device, unobserved UI behavior, TCC state, or privacy-indicator behavior is marked as passed.

## Release version and CI preflight status

A read-only GitHub check confirmed latest release `v1.3.2` (published `2026-09-23T09:24:45Z`). Its `Support/Info.plist` values are version `1.3.2`, build `15`; the local `Support/Info.plist` has the same values. The non-publishing preflight used `VERSION=1.3.3` and `BUILD=16` (greater than published build 15). Local `release-notes/1.3.3/` contains only `en.md` and `zh-Hans.md`; the `PUBLISH=false` validator passed for those 2/12 languages. Ten localized notes are absent, so this does not establish readiness to publish.

The feature branch `codex/audio-input-controls` was pushed at source SHA `77685400fdc3d41844ba7ee54969c2bc6b154b74`. One `release.yml` `workflow_dispatch` was issued at `2026-09-24T00:11:30Z` with `VERSION=1.3.3`, `BUILD=16`, and `publish=false`. The unique matching run was [35937278279](https://github.com/lingyired/status-trio/actions/runs/35937278279); its head SHA matched the pushed source SHA. `gh run watch --exit-status` passed, and the run completed successfully in 3m9s on Xcode 26.6 / Swift 6.3.3. Version resolution and appcast-note validation passed; `swift test` passed with 836 XCTest tests (6 skipped, 0 failures) and Swift Testing reported 255 tests in 36 suites passed. The release build and `LC_BUILD_VERSION` platform check passed, the app passed codesign disk validation, and `StatusTrio-1.3.3.dmg` was built without publishing. Actions artifact `StatusTrio-172` uploaded successfully (4,590,057 bytes; 3 files). This is a workflow artifact, not a GitHub Release asset: no GitHub Release was created and no appcast was published. There was no CI failure, so `docs/swift-ci-compatibility.md` was not changed.

A follow-up `release.yml` `workflow_dispatch` with `publish=false` was created at `2026-09-24T02:18:23Z`; its job completed successfully at `2026-09-24T02:21:58Z`. Run [35946682196](https://github.com/lingyired/status-trio/actions/runs/35946682196) has head SHA `3792b2e56c35ab91ab45b7698df068934984be50`, matching the pushed source commit immediately before this documentation update on `codex/audio-input-controls`; it resolved `VERSION=1.3.3`, `BUILD=16`. The logged toolchain was Xcode 26.6 (build 17F113) / Swift 6.3.3. Appcast-note validation passed for 2/12 languages (`en`, `zh-Hans`); the other 10 remain missing. Tests passed: 845 XCTest tests (6 skipped, 0 failures) and 255 Swift Testing tests in 36 suites. The release build, `LC_BUILD_VERSION` platform check, and codesign disk/designated-requirement checks passed; `StatusTrio-1.3.3.dmg` was built without publishing. Actions artifact `StatusTrio-173` (ID 10786719124; 4,602,488 bytes; 3 files) uploaded successfully. This is a workflow artifact, not a GitHub Release asset: no GitHub Release was created and no appcast was published. This successful CI run does not verify the manual device/UI/TCC matrix above or establish publish readiness. There was no CI failure, so `docs/swift-ci-compatibility.md` was not changed.

## Overall status

Task 7 local checks and CI preflight are complete. Status remains **DONE_WITH_CONCERNS** because the manual device/UI acceptance matrix is incomplete. The successful `publish=false` run is not a publish authorization or a substitute for hardware/TCC/UI verification.
