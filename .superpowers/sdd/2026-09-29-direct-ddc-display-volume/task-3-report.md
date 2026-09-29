# Task 3 report: serialized DDC coordinator

## RED

Added `DDCVolumeCoordinatorTests.swift` first and ran `swift test --filter DDCVolumeCoordinatorTests`. The test target failed to compile because `DDCVolumeCoordinator` and `DDCVolumeUpdate` were not defined, as expected for this task. During initial test authoring, Swift also caught test-fixture issues (invalid inheritance from the final target and actor-isolated fake clock access); those were corrected before proceeding to production code.

## GREEN

Implemented a `@MainActor` coordinator and one dedicated serial utility queue that owns the transport and `DDCDisplayTarget`. Main-actor state tracks selection identity, generations, details visibility, sleep, pending writes, and polling timers. The worker checks a lock-protected identity snapshot immediately before reads and writes. A write uses the latest validated volume range, and a successful write is followed by a readback on the same worker. Topology changes invalidate the cached target even when the UID remains unchanged.

Focused tests cover selection read, 2-second visible polling, 10-second hidden polling, 2/4/8/16/32/60-second failure backoff, reset after a successful read, wake refresh, a blocked worker with generation switch, latest-value write coalescing, output switch before debounce, and write readback.

Verification:

- `swift test --filter DDCVolumeCoordinatorTests`: 8 tests passed.
- `swift test`: 387 tests across 64 suites passed.
- `swift build -c release`: passed.
- `git diff --check`: passed.

## Self-review

- DDC transport resolution, target access, reads, and writes all run on one serial queue. A stalled I2C read keeps the main actor responsive and prevents physical overlap; queued work is revalidated before it reaches the transport.
- Selection, topology generation changes, sleep, and stop suppress stale callbacks. Debounced writes retain only the latest scalar and are canceled on identity change.
- Timer and callback seams are injectable. The fake transport gates a read to exercise late-generation suppression and serial access.
- This task introduces actor-isolated code; the repo guidance requires a non-publishing release workflow before merge/publish. No workflow was dispatched because this task is a local commit for parent review, not a merge or publish.

## Review round 1 fixes

Updated `Sources/StatusTrioCore/Audio/DDCVolumeCoordinator.swift`:

- Display sleep now advances the generation, clears and cancels pending slider work, cancels the read watchdog and poll timer, and clears the worker identity. Wake establishes a new identity and queues a fresh read. Any write queued with the earlier token fails the worker's identity check.
- Read requests are tracked one at a time. Additional refresh requests are coalesced while the current physical read is running. A separately timed watchdog emits an unavailable (`scalar: nil`) update for the active identity after two seconds by default; it never starts a second transport operation. A read queued behind an older blocked operation gets a watchdog for the new generation too.
- Completion handling releases the in-flight slot even when the result belongs to a stale generation, then starts a queued current-generation read when appropriate. Topology changes therefore cannot strand coordinator state behind a late callback.

Reworked `Tests/StatusTrioCoreTests/DDCVolumeCoordinatorTests.swift`:

- The gated transport protects all mutable fake state with its lock, tracks resolution and read overlap, and can block individual reads.
- The manual clock now removes canceled continuations and can release an exact interval. Async waits report XCTest failures on timeout instead of silently continuing.
- Tests verify actual worker reads and generation-matched callbacks across wake, same-UID topology re-resolution, queued write rejection after sleep/stop/topology changes, stale pre-sleep read suppression, a stalled read becoming unavailable without overlapping I2C, visible and hidden polling periods, backoff and success reset, the exact 150 ms debounce, and immediate `flushPendingVolume()`.

Commands and outputs:

- `swift test --filter DDCVolumeCoordinatorTests` — passed, 11 tests, 0 failures.
- `git diff --check` — passed, no output.
- `swift test` — passed, 387 tests in 64 suites.
- `swift build -c release` — passed, `Build complete!`.

The read watchdog is configurable for deterministic tests; production default is 2 seconds. A timed-out physical operation remains on the one serial worker until the transport returns, so status becomes unavailable without risking overlapping I2C requests.

## Review round 2 fixes

Updated `Sources/StatusTrioCore/Audio/DDCVolumeCoordinator.swift` so every dispatched read invokes its completion, including a read rejected by the worker's generation/identity guard. This releases `readInFlight`; if a newer selection, wake, or topology event requested a refresh while the old request was queued, the completion starts that current-generation read.

Added an injectable `beforeReadValidation` worker hook and `ReadValidationGate` in `Tests/StatusTrioCoreTests/DDCVolumeCoordinatorTests.swift` to deterministically pause a queued request before the identity check. The new test runs selection A→B, sleep/wake, and topology change through the same race and asserts that each reaches a current-generation callback without touching DDC for the stale queued request.

Strengthened lifecycle verification in the same test file:

- The sleep/debounce test advances the canceled 150 ms timer after wake, drains the worker queue, and confirms no write occurred.
- Stop and topology tests capture updates, release the blocked I/O, await a serial worker barrier, and then assert callback suppression for stop or a current-generation refresh for topology before checking that no queued write ran.
- `waitForWorkerIdle()` exposes a serial queue barrier for deterministic lifecycle assertions. The fake transport uses locked backing state for every field.

Commands and outputs for this round:

- `swift test --filter DDCVolumeCoordinatorTests` — passed, 12 tests, 0 failures.
- `git diff --check` — passed, no output.
- `swift test` — passed, 387 tests in 64 suites.
- `swift build -c release` — passed, `Build complete!`.

## Review round 3 fixes

Added explicit MainActor acknowledgments to the coordinator's read-completion and debounce-task seams. Lifecycle tests now wait for these acknowledgments directly instead of treating a serial worker barrier as proof that independently scheduled MainActor tasks have run.

Updated `Tests/StatusTrioCoreTests/DDCVolumeCoordinatorTests.swift`:

- `testStopAndTopologyChangeInvalidateQueuedWrites` waits for the blocked read's old-generation completion acknowledgment. For topology, it also waits for the new-generation read completion and verifies the complete published update list contains only the current generation. The stop case confirms its acknowledged completion published no status update.
- `testSleepCancelsDebouncedWriteBeforeWake` waits for the canceled debounce task to acknowledge termination, wakes and observes a fresh read, advances the manual clock by 150 ms, and verifies no write occurred.
- The manual clock's `advance(by:)` gives the cancellation check an explicit post-wake clock advance.

Commands and outputs for this round:

- `swift test --filter DDCVolumeCoordinatorTests` — passed, 12 tests, 0 failures.
- `git diff --check` — passed, no output.
- `swift test` — passed, 387 tests in 64 suites.
- `swift build -c release` — passed, `Build complete!`.
