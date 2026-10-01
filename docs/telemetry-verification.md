# Telemetry integration verification

Implementation acceptance is recorded separately from production acceptance.
This branch has no production endpoint or remote D1 writes.

## Local verification

- `bash scripts/test.sh`: 1,295 XCTest cases, 7 skipped, 0 failures; Swift Testing: 444 tests across 74 suites passed. Log: `/tmp/status-trio-telemetry-v2-full-test-script.log`.
- `swift test`: same XCTest and Swift Testing counts, 0 failures. Log: `/tmp/status-trio-telemetry-v2-swift-test.log`.
- `swift build -c release`: passed. Log: `/tmp/status-trio-telemetry-v2-release-build.log`.
- `VERSION=1.4.0 BUILD=17 PUBLISH=false bash scripts/validate-appcast-notes.sh`: passed with all 12 localized variants; confirms historical release notes without a telemetry link remain valid.
- `VERSION=2.0.0 BUILD=18 PUBLISH=false bash scripts/validate-appcast-notes.sh`: passed with 12 titles, 12 descriptions, English first, and a clickable privacy link in every Sparkle description. All 12 notes include the no-third-party-analytics-SDK statement.
- Ordinary and production-like no-open app bundles passed code-signature verification and `scripts/verify-platform-version.sh`: both target macOS 15.0 and record SDK 26.0; `STTelemetryProduction` is `false` and `true`, respectively. Bundles are preserved under `/tmp/status-trio-telemetry-v2/{ordinary,production}/StatusTrio.app`.
- An opt-in local Worker smoke test used `URLSessionTelemetryTransport` against `http://127.0.0.1:18787/v1/ping`, with local D1 state under `/tmp/status-trio-telemetry-v2/worker-state`. Consent OFF created no local installation ID or attempt; enabling consent produced HTTP 200. A local D1 `SELECT` found `first_app_version=2.0.0`, `app_version=2.0.0`, `build=18`, `os_language=en`, `app_language=en`, and `attributes={"app_icon_placement":"both"}`. Worker source was read only.
- A real `AppEnvironment.start()`/`stop()` lifecycle test uses fake battery, Wi-Fi and volume monitors and verifies both monitor and telemetry reporter lifecycle calls.

## Non-publishing CI

The published latest release was rechecked as v1.4.0 (2026-09-30), and the highest appcast build was 17. The feature branch was pushed and release workflow preflight was dispatched with version 2.0.0, build 18, and `publish=false`:

- Run: [36844103043](https://github.com/lingyired/status-trio/actions/runs/36844103043)
- Result: pending at the time this file was written.

## Deferred acceptance

Production endpoint requests and remote D1 inspection or writes were not authorized and were not performed. Production smoke and post-release verification remain outstanding. Worker/dashboard deployment source edits and unrelated SwiftUI/XCTest architecture migration were outside this implementation scope.
