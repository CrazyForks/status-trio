# Charging Effects: Follow-up Before Integration

## Current status

Phase one has no known implementation defects after the final independent whole-branch review. The reviewed fixes cover the 36-frame steady cache and layer presenter, the live Settings preview, gap-aware visible tail length, and release of cached animation resources when the menu-bar item is hidden.

Latest local verification passed:

- `swift test --quiet`: 637 XCTest tests (6 skipped) and 234 Swift Testing tests across 43 suites.
- `swift build -c release`: succeeded, with existing deprecation warnings only.
- The worktree app bundle was also built and launched locally with the macOS 26 SDK; this was for interactive testing, not a distributable release package.

The measured layer-backed 60-second CPU A/B was 1.651% enabled mean versus 0.136% disabled mean (1.515 percentage-point increase; below the accepted 3% mean). This measurement predates the final review-only fixes; those changes affect visible-tail coordinates, Settings preview selection, and hide-time teardown, not the steady-state layer update loop. No second CPU sample was taken on the exact final tree.

## Deferred follow-ups

1. **Verify with the exact CI toolchain.** The local machine has Xcode 27 / Swift 6.4, not the repository's Xcode 26.6 / Swift 6.3.3. A local successful build does not establish exact CI-toolchain compatibility.
2. **Run the non-publishing release preflight before merge or publishing.** The branch changes actor-isolated and SwiftUI code, so repository rules require the `release.yml` workflow with `publish=false` before integration. The user explicitly deferred release preflight; do not start it without later authorization.
3. **Optionally repeat the matched 60-second CPU A/B on the exact final tree** if acceptance requires a measurement from the committed revision rather than the already measured layer-backed update path.
4. **Choose branch integration after those gates.** `feature/charging-effects` remains isolated and has not been merged or pushed.

These are deferred verification and integration steps, not known unfinished implementation work. No DMG or public release package has been created.
