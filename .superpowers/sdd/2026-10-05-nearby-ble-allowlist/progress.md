# SDD ledger — plan: docs/superpowers/plans/2026-10-05-nearby-ble-allowlist.md

Base: f2aedbad69d893266d5149c269315e9e8d9ea713

Pre-flight: Task 1 produces BLE identity, candidate, vendor and persisted selections; Tasks 2 and 4 consume candidate/vendor and identity/selection. Task 2 produces scanner authorization/callbacks consumed by Task 3. Task 3 produces controller demands, selections, candidates and visible read permission consumed by Task 4. Task 4 produces panel catalog rows consumed by Task 5. Task 5 produces the selection UI and geometry visibility reports used by Task 6 local app validation. No incompatible signatures found; spec remains binding.


RED evidence: test-1-red failed to compile because candidate, identity, and persisted selection APIs were absent; task-1-order-red then failed because a BLE row was dropped when ordinary read rows led their group.
Task 1: complete (commits f2aedba..e9be3df, tests: swift test → ✔ Test run with 490 tests in 78 suites passed after 5.386 seconds.)

Task 2: Ruling: Include recognized Apple Continuity advertisements even when the OS provides no name — the spec says name is display data and Apple classification comes from broadcast metadata; filtering on a known name can hide an otherwise eligible device before user selection. Limit this to full Apple company identifier plus recognized Continuity message type; connection still requires the UUID allowlist. Cost if wrong: unnamed nearby Apple candidates can appear in the picker, but cannot be connected without explicit selection.

Task 2 RED evidence: task-2-red failed because NearbyBLEReadAuthorization was absent; task-2-company-red then proved Apple detection accepted a partial company identifier. Focused final: 29 Swift Testing cases plus 25 XCTest cases passed. Full verification before commit: swift test → 496 tests / 79 suites passed; swift build -c release → Build complete.
Task 2: complete (commits e9be3df..b9f2345, tests: swift test → 496 tests in 79 suites passed; swift build -c release → Build complete)

Task 3 RED evidence: `swift test --filter 'NearbyBLEControllerDemandTests|BluetoothNearbyBatteryLifecycleTests'` failed before implementation because the new controller demand API was absent. The first full attempt exposed layout fixtures that still supplied unselected synthetic readings and an actor-method reference caught by `ForbiddenPatternGuardTests`; fixtures now provide selected UUIDs and the hidden-ID parser uses an explicit closure. Added scanner-side revoked-result cache removal so an unrelated authorized result snapshot cannot resurrect a revoked UUID's old reading after re-selection. The panel's general battery-level toggle now empties only visible read demand while the global nearby feature configuration remains enabled for independent settings discovery.
Task 3: complete (commit b9f2345..d5d720f; focused: 34 XCTest cases passed; `swift test` → 1,152 XCTest cases, 6 skipped, 0 failures; Swift Testing → 496 tests / 79 suites passed; `swift build -c release` → Build complete.)
