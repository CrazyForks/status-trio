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
