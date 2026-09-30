# Task 10 report: Bluetooth and detail panel state

## Implementation

Added value state and main-actor mappers for Bluetooth summary/device rows, battery details, wired details, and Wi-Fi list/details. Mappers reuse existing presentation helpers for ordering, visibility, status, battery segments, power values, network grouping, wireless security, and link detail eligibility. `PanelDetailRow.isCopyable` defaults to `false` and carries `LinkDetailPresentation` eligibility for IPv4, IPv6, router, DNS, and Wi-Fi BSSID rows. Wi-Fi SSIDs remain byte-for-byte as supplied, and unconnected network rows retain the System Settings action. Wi-Fi state keeps the complete resolved detail list, collapsed count, view-local visible slice helper, and existing localized More/Less text.

Extended the existing closure-based `StatusPanelActions` for Bluetooth authorization request/settings actions, current-address actions, row-tap confirmation policy, listening mode, independent battery and nearby claims, detail lifecycle, Wi-Fi power/refresh, volume listening-mode lifecycle, and device reordering. Bluetooth row values include connection state, battery layout and segments (including the case symbol), action status text/tint, and confirmation policy. The summary disappearance releases the visible surface and paired-level claim while retaining the nearby opt-in until the preference is explicitly disabled. No monitor protocol, new timer, or state-owned controller was added.

The production panel reorder accepts the currently displayed identity slice, validates it against the current filtered/saved-order prefix, and no-ops on stale input. Moves affect only those displayed slots in full saved order, preserving hidden, ghost, and beyond-collapse ranks. Destination `count` appends within the visible slice, before undisplayed rows. The raw Settings reorder path retains its prior behavior. Task 11 must pass its current `pairedRows` display slice including the collapsed limit.

Updated the tracked Task 10 plan and scratch Task 10/11 briefs with the resolved action, permission, nearby-cache, presentation, and reorder contracts. SwiftUI consumers remain Task 11 work.

## TDD and verification

Focused mapper/action tests were first run against missing resolved fields and action APIs; after implementation, the added cases passed. The Settings-backed reorder test covers hidden, ghost, visible keyboard/mouse, and beyond-collapse saved ranks, including destination-at-count and stale-prefix no-op. The controller lifecycle test proves summary disappearance stops scanning while cache data remains for independent Settings and summary claims, then clears on explicit preference disable. Bluetooth mapper tests cover request versus denied permission behavior, request subtitle versus accessibility copy, row connection/battery/case-glyph/failure-tint/confirmation values, and resolved helper behavior.

- Focused mapper/detail/action and Bluetooth permission, targeting, listening-mode, nearby lifecycle suites: 66 tests passed; log `/tmp/task10-fix1-focused.log`.
- `swift test --filter ForbiddenPatternGuardTests`: 2 tests passed; log `/tmp/task10-fix1-forbidden-pattern.log`.
- Final `swift test`: 1,209 XCTest cases, 6 skipped, 0 failures; 407 Swift Testing tests in 70 suites passed. Full log `/tmp/task10-fix1-swift-test.log`.
- Final `swift build -c release`: passed. Full log `/tmp/task10-fix1-swift-build-release.log`.
- `git diff --check`: passed before staging; the staged diff is checked again before commit.

Existing Bluetooth action-targeting, permission-timing, listening-mode lifecycle, and nearby lifecycle controller suites were run without changing controller ownership. No source method reference was introduced into collection transforms; the focused forbidden-pattern guard passed.

## Changed files

- `Sources/StatusTrioCore/Presentation/Panel/BluetoothPanelMapper.swift`
- `Sources/StatusTrioCore/Presentation/Panel/BluetoothPanelState.swift`
- `Sources/StatusTrioCore/Presentation/Panel/PanelSummaryState.swift`
- `Sources/StatusTrioCore/Presentation/Panel/StatusPanelActions.swift`
- `Tests/StatusTrioCoreTests/BluetoothPanelMapperTests.swift`
- `Tests/StatusTrioCoreTests/BluetoothNearbyBatteryLifecycleTests.swift`
- `Tests/StatusTrioCoreTests/PanelActionRoutingTests.swift`
- `docs/superpowers/plans/2026-09-30-v2-presentation-state-refactor.md`
- `.superpowers/sdd/2026-09-30-v2-presentation-state-refactor/task-10-brief.md`
- `.superpowers/sdd/2026-09-30-v2-presentation-state-refactor/task-11-brief.md`

The main-actor action and mapper changes require the repository's non-publishing release workflow preflight before any merge or publish. No push, merge, preflight, or publish was performed.
