# Task 2 report: exact display identity and direct transport

## RED evidence

Added `DDCDisplayTransportTests` first, with exact UID selection cases for blank UID, no match, duplicate exact UUIDs, a single exact match among nonmatches, and a name-only resemblance. Added a fake transport that passes malformed VCP `0x62` bytes through `DDCVolumeReply.decode`.

Ran `swift test --filter DDCDisplayTransportTests` before production implementation. It failed at compile time as expected: `cannot find 'DDCDisplayTransport' in scope` at each selector assertion. The failure established that the transport and selector API were absent.

## GREEN evidence

Implemented the transport, pure unique selector, IORegistry resolution, I2C read/write bridge, test fake, C target, framework link, and upstream MIT license.

- `swift test --filter DDCDisplayTransportTests`: passed, 2 tests, 0 failures.
- `swift test`: passed, 387 tests in 64 suites, 0 failures.
- `swift build -c release`: passed.
- `otool -L .build/out/Products/Release/StatusTrio`: includes `/System/Library/Frameworks/CoreDisplay.framework/Versions/A/CoreDisplay`.
- `find .build -iname '*ASDDC*' -print`: no matches.
- `git diff --check`: clean.

## Self-review

- Resolution rejects blank UIDs, requires exactly one case-sensitive EDID UUID match, and does not use display names.
- Discovery only accepts external `DCPAVServiceProxy` entries and searches ancestors for `EDID UUID`.
- IOKit service references are created, examined, and discarded on the calling serial worker. `DDCDisplayTarget` has no `Sendable` conformance; the raw service handle is not wrapped for cross-queue transfer.
- Reads use VCP `0x62`, chip address `0x37`, data address `0x51`, bounded five attempts, an 11-byte response, and the existing validating decoder. Writes use bounded retries and two write cycles.
- Non-arm64 paths return `nil`/`false`.
- The bridge declares only the needed private IOKit calls. CoreDisplay is linked on StatusTrioCore. Upstream attribution and its MIT license are included.
- No ASDDC subprocess, name scoring, capability scan, CLI, or probe output was added.

## Concerns

Hardware enumeration and DDC read/write were not exercised against a physical external display in this automated run. The service and target must continue to be created, used, and released exclusively on the DDC worker as the worker is integrated.

## Follow-up fix: reject duplicate identity before service creation

### RED/GREEN evidence

Added `testDuplicateIdentityIsRejectedBeforeOpeningAnyService`, which supplies two external proxy identities with the same EDID UUID and a fake opener that succeeds for the first identity. The test asserts that the result is nil and the opener was never called. Before adding the generic `uniqueOpenedMatch` boundary, the focused test failed to compile because that testable ordering API was absent. After implementation, the test passes.

The discovery path now gathers external proxy registry entries and their ancestor EDID UUIDs before creating any `IOAVService`. It rejects zero or multiple exact UUID matches using the pure selector, then opens only the uniquely selected proxy. A failed open therefore returns nil without hiding another proxy identity.

- `swift test --filter DDCDisplayTransportTests`: passed, 3 tests, 0 failures.
- `swift test`: passed, 387 tests in 64 suites, 0 failures.
- `swift build -c release`: passed.

## Follow-up hardware correction: associate the separate framebuffer and DDC branches

### RED/GREEN evidence

The hardware brief's read-only registry probe showed one external `DCPAVServiceProxy`, with no `EDID UUID` on it or its first 12 IOService ancestors. The UUID was available on a separate `IOMobileFramebufferShim` branch. Added deterministic tests for exact framebuffer UID association, duplicate framebuffer identities, multiple framebuffer/service ambiguity, and confirming that ambiguous cases never call the opener. Before the association boundary was implemented, the new tests failed to compile because `uniqueFramebufferServiceMatch` did not exist; after implementation, the focused suite passed.

Discovery now collects the `EDID UUID` from `IOMobileFramebufferShim` entries and external DDC proxy handles independently. It opens a service only after the requested CoreAudio UID exactly matches the sole framebuffer UUID and the registry contains exactly one external service. Multiple UUID-bearing framebuffer entries, multiple external services, missing/mismatched UIDs, or failed service creation return nil. The earlier duplicate-UUID-before-open regression remains in place.

### Read-only hardware evidence

Product-path probe result: `match=true`, `current=100`, `max=100`. It invoked `DDCDisplayTransport.resolve(uid:)` and `read(_:)`; no volume write was issued. The full device UID was not recorded. The temporary gated probe test was removed before commit.

- `swift test --filter DDCDisplayTransportTests`: passed, 5 tests, 0 failures.
- `swift test`: passed, 387 tests in 64 suites, 0 failures.
- `swift build -c release`: passed.

## Follow-up fix: count connected external framebuffers without UUIDs

### Registry evidence and relevance rule

Inspected live IORegistry properties without displaying any display UID. This Mac reported five `IOMobileFramebufferShim` entries:

- `IONameMatched=disp0,t603x`: built-in panel; has dimensions but is not an external display.
- `IONameMatched=dispext0,t603x`: connected external display; dimensions are `2560x1440` and recursive `EDID UUID` is present.
- `IONameMatched=dispext1,t603x`, `dispext2,t603x`, and `dispext3,t603x`: inactive external ports; display dimensions and UUID are absent.
- One `DCPAVServiceProxy` reports `Location=External`.

The code now treats an `IOMobileFramebufferShim` as a connected external framebuffer when `IONameMatched` begins with `dispext` and both direct `DisplayWidth` and `DisplayHeight` properties are positive. This excludes the built-in `disp0` panel and inactive `dispext` ports on the observed host. It appends every relevant framebuffer, including a `nil` UUID for an unreadable identity, so any second connected external framebuffer fails closed.

### RED/GREEN and hardware evidence

Added regression coverage for `[matching UUID, missing UUID]` with one external service, asserting `nil` and zero opener calls. Added property relevance tests for the active external output, inactive external port, built-in panel, and invalid dimensions. Before implementation, the new tests could not compile against the previous `[String]`-only framebuffer API, which could not represent a connected framebuffer with missing identity. After implementation:

- `swift test --filter DDCDisplayTransportTests`: passed, 6 tests, 0 failures.
- Read-only product probe through `DDCDisplayTransport.resolve(uid:)` and `read(_:)`: `match=true current=100 max=100`. No volume write was issued; the temporary gated test was removed.
- `swift build -c release`: passed.

Full suite command: `swift test`. Its 387 Swift Testing cases passed, but the command exited 1 because XCTest failed at `Tests/StatusTrioCoreTests/DDCVolumeCoordinatorTests.swift:267`: `testSwitchBeforeDebounceDropsQueuedWrite` asserted that the old debounce had been cancelled. Re-running only `swift test --filter DDCVolumeCoordinatorTests.testSwitchBeforeDebounceDropsQueuedWrite` reproduced the failure. This test and coordinator code are outside the transport correction; no unrelated files were changed.
