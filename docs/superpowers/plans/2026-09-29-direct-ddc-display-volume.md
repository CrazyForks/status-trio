# Direct DDC Display Volume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read and adjust the XV272U's speaker volume directly through DDC when its selected CoreAudio output has no writable volume control.

**Architecture:** Keep CoreAudio as the first choice. A separate DDC service resolves the selected output UID to exactly one live IORegistry `EDID UUID`, validates VCP `0x62`, and runs all I2C work on one serial queue. `VolumeMonitor` merges confirmed DDC readings into its existing status stream; the store and UI use explicit set-volume and mute capabilities.

**Tech Stack:** Swift 6, SwiftPM, CoreAudio, IOKit, CoreDisplay private symbols, SwiftUI, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-29-direct-ddc-display-volume-design.md`

## Global Constraints

- macOS minimum 15; build with macOS 26 SDK or newer. CI uses `macos-26`, Xcode 26.6, Swift 6.3.3.
- Apple Silicon only for the verified DDC transport. Other architectures and unavailable private APIs keep volume unavailable.
- Only VCP `0x62`; no capability sweep, `ASDDC` subprocess, keyboard hook, BetterDisplay automation, Accessibility request, or Screen Recording request.
- The exact CoreAudio UID must equal exactly one live DDC service's `EDID UUID`; never use fuzzy or first-match fallback.
- Popover/details open: 2-second polls. Closed: 10-second polls. Failed reads: 2, 4, 8, 16, 32, then 60 seconds, capped there. One I2C request at a time.
- Before each Swift commit run `swift test` and `swift build -c release`. Before merge or publication run the nonpublishing `release.yml` preflight because this change touches actor isolation and SwiftUI bindings.
- Do not disturb the installed Status Trio app or the existing first-phase work. Use the current `codex/external-display-volume` worktree and PR #75.

## File map

- `Sources/StatusTrioCore/Audio/DDCVolumeReply.swift`: pure reply validation and scalar conversion.
- `Sources/StatusTrioCore/Audio/DDCDisplayTransport.swift`: direct IORegistry service discovery and I2C requests, hidden behind an injectable protocol.
- `Sources/StatusTrioCore/Audio/DDCVolumeCoordinator.swift`: one serial worker, polling/backoff, drag coalescing, generation checks, and main-actor callbacks.
- `Sources/DDCPrivateAPI/`: separate C target with the private-function header and upstream MIT license/attribution. Add its target and CoreDisplay linker setting in `Package.swift`.
- `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`, `AudioStatusReader.swift`: choose backend, merge DDC state, invalidate on output change/stop/recovery.
- `Sources/StatusTrioCore/Store/SystemStatusStore.swift`, `Monitoring/MonitorProtocols.swift`: command gating and display sleep/wake forwarding.
- `Sources/StatusTrioCore/Audio/VolumeControlling.swift`, `UI/StatusPopoverView.swift`: flush the final slider value on drag end.
- `Sources/StatusTrioCore/Models/StatusSnapshot.swift`, `Audio/AudioOutputDevice.swift`, `UI/VolumeControlsView.swift`: independent set-volume/mute capabilities, selected-row volume, disabled DDC mute.
- `Sources/StatusTrioCore/App/AppEnvironment.swift`: production DDC dependency injection.
- `Tests/StatusTrioCoreTests/DDCVolumeReplyTests.swift`, `DDCDisplayTransportTests.swift`, `DDCVolumeCoordinatorTests.swift`, existing volume/store tests: deterministic validation and integration coverage.

## Review Focus

1. Two identical display UUIDs or an absent UID: keep controls disabled and never write either display. Test in Task 2.
2. A checksum-valid reply with unsupported result `1` or an echoed code other than `0x62`: never display `100%`. Test in Task 1.
3. Rapid slider events followed by an output switch: no queued write reaches the new output. Test in Task 3.
4. DDC read stalled across stop or display sleep: main actor remains responsive and no second I2C request overlaps it. Test in Task 3.
5. A display at zero volume whose mute VCP is unsupported: show `0%`, keep slider usable, and disable mute without claiming muted. Test in Task 4.

---

### Task 1: Strict VCP `0x62` decoding

**Files:**
- Create: `Sources/StatusTrioCore/Audio/DDCVolumeReply.swift`
- Create: `Tests/StatusTrioCoreTests/DDCVolumeReplyTests.swift`

**Interfaces:**
- Consumes: the 11-byte DDC get-VCP reply from Task 2.
- Produces: `DDCVolumeReply.decode(_ bytes: [UInt8]) -> DDCVolumeReply?`, `scalar: Double`, and `targetValue(for scalar: Double) -> UInt16`.

- [ ] **Step 1: Write failing decoding tests.** Use the measured XV272U response and derive valid-checksum malformed variants with a local XOR helper. Assert the success reply decodes as `100/100`; result byte `1`, echoed code `0x8D`, wrong length, bad checksum, maximum zero, and current above maximum all return `nil`. Assert `targetValue(for: 0.955)` rounds to 96 for a maximum of 100, with clamping at 0 and 100.

```swift
let valid: [UInt8] = [110, 136, 2, 0, 98, 0, 0, 100, 0, 100, 214]
XCTAssertEqual(DDCVolumeReply.decode(valid)?.scalar, 1)
XCTAssertNil(DDCVolumeReply.decode([110, 136, 2, 1, 255, 0, 0, 100, 0, 100, 74]))
XCTAssertNil(DDCVolumeReply.decode(Array(valid.dropLast())))
XCTAssertEqual(DDCVolumeReply(current: 95, maximum: 100).targetValue(for: 0.955), 96)
```

- [ ] **Step 2: Confirm red.** Run `swift test --filter DDCVolumeReplyTests`; expect compilation failure because `DDCVolumeReply` does not exist.
- [ ] **Step 3: Implement the pure parser.** Check reply bytes `[0] == 0x6E`, `[1] == 0x88`, `[2] == 0x02`, `[3] == 0`, `[4] == 0x62`; XOR bytes `0...9` with seed `0x50` and compare byte `[10]`. Decode big-endian max from `[6,7]` and current from `[8,9]`. Reject max zero and current greater than max; clamp finite scalar and round the requested target.

```swift
struct DDCVolumeReply: Equatable, Sendable {
    let current: UInt16
    let maximum: UInt16
    var scalar: Double { Double(current) / Double(maximum) }
    static func decode(_ bytes: [UInt8]) -> Self? {
        guard bytes.count == 11, bytes[0] == 0x6E, bytes[1] == 0x88,
              bytes[2] == 0x02, bytes[3] == 0, bytes[4] == 0x62,
              bytes.prefix(10).reduce(UInt8(0x50), ^) == bytes[10]
        else { return nil }
        let maximum = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        let current = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        guard maximum > 0, current <= maximum else { return nil }
        return Self(current: current, maximum: maximum)
    }
    func targetValue(for scalar: Double) -> UInt16 {
        guard scalar.isFinite else { return current }
        return UInt16((min(1, max(0, scalar)) * Double(maximum)).rounded())
    }
}
```

- [ ] **Step 4: Confirm green and commit.** Run `swift test --filter DDCVolumeReplyTests`, then `swift test` and `swift build -c release`. Commit the two files as `feat: validate DDC volume replies`.

### Task 2: Exact display identity and direct transport

**Files:**
- Create: `Sources/StatusTrioCore/Audio/DDCDisplayTransport.swift`
- Create: `Sources/DDCPrivateAPI/include/DDCPrivateAPI.h`
- Create: `Sources/DDCPrivateAPI/DDCPrivateAPI.m`
- Create: `Sources/DDCPrivateAPI/LICENSE-AppleSiliconDDC.txt`
- Modify: `Package.swift`
- Create: `Tests/StatusTrioCoreTests/DDCDisplayTransportTests.swift`

**Interfaces:**
- Consumes: exact CoreAudio device UID from `AudioOutputDevice.uid` and `DDCVolumeReply.decode` from Task 1.
- Produces: `DDCVolumeTransport` protocol and `DDCDisplayTransport` implementation with `resolve(uid: String) -> DDCDisplayTarget?`, `read(_ target: DDCDisplayTarget) -> DDCVolumeReply?`, `write(_ target: DDCDisplayTarget, value: UInt16) -> Bool`. `DDCDisplayTarget` is an opaque, worker-confined handle with immutable UID; do not mark an IOKit service reference `Sendable` just to silence the compiler.

```swift
// Construct and use only on the DDC worker. The optional service lets fake
// transports create identity-only targets without IOKit.
final class DDCDisplayTarget {
    let uid: String
    let service: IOAVService?
    init(uid: String, service: IOAVService?) {
        self.uid = uid
        self.service = service
    }
}

protocol DDCVolumeTransport: AnyObject {
    func resolve(uid: String) -> DDCDisplayTarget?
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReply?
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool
}
```

- [ ] **Step 1: Write failing identity tests.** Extract a pure `uniqueMatch(uid:services:)` selector taking tuples of `edidUUID` and stable test handles. Test one exact match, zero matches, blank UID, two matches with the same UUID, and one name-only resemblance. Assert only the one exact match resolves. Add a transport fake whose invalid `0x62` bytes are rejected through `DDCVolumeReply.decode`.

```swift
XCTAssertNil(DDCDisplayTransport.uniqueMatch(uid: "", services: [(edidUUID: "A", handle: 1)]))
XCTAssertNil(DDCDisplayTransport.uniqueMatch(uid: "A", services: [(edidUUID: "A", handle: 1), (edidUUID: "A", handle: 2)]))
XCTAssertEqual(DDCDisplayTransport.uniqueMatch(uid: "A", services: [(edidUUID: "B", handle: 1), (edidUUID: "A", handle: 2)])?.handle, 2)
```

- [ ] **Step 2: Confirm red.** Run `swift test --filter DDCDisplayTransportTests`; expect the missing transport/selector error.
- [ ] **Step 3: Add the narrow private API bridge and transport.** Link `CoreDisplay` only in the StatusTrioCore target, add a small C target for the header, and copy the upstream MIT license. Derive the IORegistry discovery and I2C packet format from AppleSiliconDDC revision `67ff964ab8123d9d35fadf7d8e1a7c677d31da14` (locally `/tmp/status-trio-asddc-probe/Sources/AppleSiliconDDC/AppleSiliconDDC.swift`), retaining copyright attribution and excluding its display-name scoring, capability scan, CLI, and probe debug print. On arm64, enumerate external `DCPAVServiceProxy` services and their parent display `EDID UUID`; resolve only when the pure selector returns one candidate. Create/release service handles on the DDC serial queue. On other architectures return `nil`/`false`. `DDCVolumeTransport` is injected for tests; the concrete transport is confined to the serial worker. If a Swift 6 closure requires a Sendable wrapper for that worker, apply `@unchecked Sendable` only to a wrapper that synchronizes all access on that queue and document that invariant.

```c
typedef CFTypeRef IOAVService;
extern IOAVService IOAVServiceCreateWithService(CFAllocatorRef, io_service_t);
extern IOReturn IOAVServiceReadI2C(IOAVService, uint32_t, uint32_t, void *, uint32_t);
extern IOReturn IOAVServiceWriteI2C(IOAVService, uint32_t, uint32_t, void *, uint32_t);
```

```swift
static func uniqueMatch<Handle>(
    uid: String,
    services: [(edidUUID: String, handle: Handle)]
) -> (edidUUID: String, handle: Handle)? {
    guard !uid.isEmpty else { return nil }
    let matches = services.filter { $0.edidUUID == uid }
    return matches.count == 1 ? matches[0] : nil
}

// Read packet for VCP 0x62: 0x81, 0x01, 0x62, DDC checksum.
// I2C chip address 0x37, data address 0x51; reply has exactly 11 bytes.
// Use bounded retries from AppleSiliconDDC; return nil on nonzero IOReturn.
guard let candidate = Self.uniqueMatch(uid: uid, services: services) else { return nil }
return DDCDisplayTarget(uid: uid, service: candidate.service)
```

- [ ] **Step 4: Confirm green and commit.** Run `swift test --filter DDCDisplayTransportTests`, `swift test`, and `swift build -c release`. Check the built binary links CoreDisplay and no `ASDDC` executable is bundled. Commit transport, bridge, license, tests, and `Package.swift` as `feat: add direct display DDC transport`.

### Task 3: Serialized DDC coordinator

**Files:**
- Create: `Sources/StatusTrioCore/Audio/DDCVolumeCoordinator.swift`
- Create: `Tests/StatusTrioCoreTests/DDCVolumeCoordinatorTests.swift`

**Interfaces:**
- Consumes: Task 2 `DDCDisplayTransport` and Task 1 `DDCVolumeReply`.
- Produces: `@MainActor DDCVolumeCoordinator` with `select(outputID: AudioDeviceID, uid: String?)`, `topologyChanged()`, `setDetailsVisible(_:)`, `setDisplayAsleep(_:)`, `setVolume(_:)`, `flushPendingVolume()`, `refresh()`, and `stop()`. It emits `(outputID, uid, scalar: Double?)` updates with a generation token to `VolumeMonitor`. Inject transport, timer sleep, and callback in tests.

- [ ] **Step 1: Write failing coordinator tests with a gateable fake transport and manual clock.** Assert 2-second open and 10-second closed intervals; an immediate read on selection/open/wake/topology change; failed-read intervals of 2, 4, 8, 16, 32, 60 seconds; success resets backoff. A blocked fake read must leave the main actor responsive and must not be overlapped by any scheduled read. Burst slider values `0.2, 0.4, 0.8` yield one final write; output switch before the debounce yields no write. A completed write is followed by a validated readback. Stop and display sleep cancel timers and suppress stale callbacks.

```swift
coordinator.select(outputID: 93, uid: "DISPLAY-A")
fake.reply = DDCVolumeReply(current: 50, maximum: 100)
coordinator.setVolume(0.2)
coordinator.setVolume(0.4)
coordinator.setVolume(0.8)
clock.advance(by: .milliseconds(150))
XCTAssertEqual(fake.writeValues, [80])
coordinator.select(outputID: 94, uid: "DISPLAY-B")
fake.finishOldRead(current: 30, maximum: 100)
XCTAssertFalse(updates.contains { $0.outputID == 94 && $0.scalar == 0.3 })
```

- [ ] **Step 2: Confirm red.** Run `swift test --filter DDCVolumeCoordinatorTests`; expect missing coordinator errors.
- [ ] **Step 3: Implement one worker and main-actor state machine.** Keep the transport and its service handle on one serial `DispatchQueue(qos: .utility)`. Main-actor state owns current output ID/UID, generation, visibility, sleep flag, pending latest scalar, and timer task. Queue one operation at a time; follow a write with a read on the same worker. Before sending a queued write, compare captured generation and output ID/UID with current state. Ignore late callbacks from earlier generations. Do not launch a second physical I2C operation when an old one stalls; mark the status unavailable and wait for the worker to return. A final drag-end value bypasses debounce through an explicit `flushPendingVolume()` method called by the UI/store path. `topologyChanged()` increments generation, drops the old target, and resolves the same output UID again.

```swift
struct DDCVolumeUpdate: Sendable {
    let outputID: AudioDeviceID
    let uid: String
    let generation: UInt64
    let scalar: Double?
}

private func receive(_ update: DDCVolumeUpdate) {
    guard !stopped, !displayAsleep,
          update.generation == generation,
          update.outputID == outputID, update.uid == uid else { return }
    onUpdate(update)
}
```

- [ ] **Step 4: Confirm green and commit.** Run `swift test --filter DDCVolumeCoordinatorTests`, `swift test`, and `swift build -c release`. Commit coordinator and tests as `feat: serialize and poll DDC volume`.

### Task 4: Connect DDC to volume status and controls

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/AudioStatusReader.swift`
- Modify: `Sources/StatusTrioCore/Models/StatusSnapshot.swift`
- Modify: `Sources/StatusTrioCore/Audio/AudioOutputDevice.swift`
- Modify: `Sources/StatusTrioCore/Audio/CoreAudioOutputController.swift`
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift`
- Modify: `Sources/StatusTrioCore/Audio/VolumeControlling.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/MonitorProtocols.swift`
- Modify: `Sources/StatusTrioCore/UI/VolumeControlsView.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusPopoverView.swift`
- Modify: `Sources/StatusTrioCore/App/AppEnvironment.swift`
- Modify: `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`
- Modify: `Tests/StatusTrioCoreTests/VolumeMonitorAsyncTests.swift`
- Modify: `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift`
- Create: `Tests/StatusTrioCoreTests/DDCVolumePresentationTests.swift`

**Interfaces:**
- Consumes: `DDCVolumeCoordinator` updates and commands from Task 3.
- Produces: one `VolumeStatus` stream with `canSetVolume` and `canMute`, plus selected output row updated from confirmed DDC scalar.

- [ ] **Step 1: Write failing integration tests.** Fake a default output with UID `DISPLAY-A` and no CoreAudio scalar; after a valid DDC update assert scalar `0.75`, `canSetVolume == true`, `canMute == false`, `isMuted == false`, and selected output row volume `0.75`. Verify a readable and settable CoreAudio scalar prevents any DDC request. Verify an unreadable/unsettable CoreAudio scalar selects DDC. Verify `toggleMute()` makes no controller call when `canMute == false`, and zero DDC volume is `0%` but never muted. Verify switching to another output clears the old scalar until the new backend read resolves.

```swift
XCTAssertEqual(status.scalar, 0.75)
XCTAssertEqual(status.outputDevices.first(where: { $0.isCurrent })?.volume, 0.75)
XCTAssertTrue(status.canSetVolume)
XCTAssertFalse(status.canMute)
XCTAssertFalse(status.isMuted)
store.toggleMute()
XCTAssertEqual(fakeAudioCommands.muteCount, 0)
```

- [ ] **Step 2: Confirm red.** Run `swift test --filter DDCVolumePresentationTests` and the named volume/store tests; expect missing capability or behavior failures.
- [ ] **Step 3: Add explicit capabilities and preserve the CoreAudio path.** Add `isPropertySettable` to `CoreAudioClient` using `AudioObjectIsPropertySettable`, including its fake. `CoreAudioVolumeReader` reports scalar only for a readable, settable main element or channel; derive mute capability from a settable mute property. In `VolumeMonitor.receive`, retain the latest CoreAudio output identity and dispatch DDC selection only when that scalar is absent. Ignore coordinator updates with a different output ID, UID, or generation. Set `canSetVolume`/`canMute` in `VolumeStatus`, update the current output device's `volume` using a copy initializer, and keep other rows unchanged. Gate `SystemStatusStore.setVolume` and `toggleMute` separately. `VolumeControlsView` disables mute using `!volume.canMute` and slider using `!volume.canSetVolume`. Its `onEditingChanged(false)` calls a new `onVolumeEditingEnded` closure; wire that through `StatusPopoverView` and `SystemStatusStore.finishVolumeAdjustment()` to `VolumeControlling.flushPendingVolume()`, which is a no-op for CoreAudio. Wire display sleep/wake to coordinator through the monitor protocol and production `AppEnvironment`. Observe `NSApplication.didChangeScreenParametersNotification` while running and call `topologyChanged()`; remove the observer at stop/deinit.

```swift
// Existing convenience initializers may infer capabilities for fixture compatibility;
// production readings pass both values explicitly.
let ddcStatus = VolumeStatus(
    scalar: update.scalar, isMuted: false, deviceName: coreReading.deviceName,
    currentDevice: coreReading.currentDevice, outputDevices: selectedRowUpdated,
    canSetVolume: update.scalar != nil, canMute: false
)
guard liveVolume.canMute else { return } // before optimistic mute mutation
```

- [ ] **Step 4: Confirm green and commit.** Run focused volume/store/UI tests, then `swift test` and `swift build -c release`. Commit these integration changes as `feat: expose direct DDC display volume`.

### Task 5: Real-device dev build and release preflight

**Files:**
- Update: `docs/superpowers/plans/2026-09-29-direct-ddc-display-volume.md` checkboxes/results only.
- Update: `docs/swift-ci-compatibility.md` only if a GitHub Actions run fails.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: validated `StatusTrio Dev.app`, measurement notes, and nonpublishing CI result linked to PR #75.

- [x] **Step 1: Build and run the isolated dev app.** Run `bash scripts/build-worktree.sh release no-open` and `open dist/StatusTrio.app`; verify the running PID and bundle path point to the worktree build. Do not replace `/Applications/Status Trio.app` or change BetterDisplay settings.
- [ ] **Step 2: Exercise the XV272U.** Read `0x62` with the scratch probe, move Status Trio's slider to 95%, read back `95` (or the nearest supported step), then restore the user's original hardware value. Use the existing keyboard shortcut path and verify Status Trio reflects the new value within 2 seconds with details open or 10 seconds closed. Verify MacBook speakers remain CoreAudio-controlled, switching outputs cannot issue a stale DDC write, and disconnect/reconnect disables then restores controls.
- [ ] **Step 3: Measure resource use.** Record open/closed DDC request durations and idle Status Trio CPU over at least 60 seconds each using a local system sampler. Check there is only one DDC request at a time and no reads while display sleep is active. If polling causes measurable sustained CPU use, fix the coordinator and rerun this step before handoff.
- [x] **Step 4: Verify and preflight.** Run `swift test`, `swift build -c release`, and the nonpublishing `release.yml` workflow from `codex/external-display-volume` with explicit next version/build inputs. Watch the run to completion; if it fails, add its run ID, stage, root cause, fix, and verification result to `docs/swift-ci-compatibility.md`, then retry. Update PR #75 with the direct DDC scope and evidence. Stop before any published release.

**Results:** Step 1 built and launched the isolated release app (PIDs 22880 and 20069; bundle ID `com.lingsmbp.StatusTrio.dev.external-display-volume`). For Step 2, the read-only baseline was VCP 0x62=100/100; a temporary gated product-transport test wrote/read 95, restored/read 100, and a read-only VolumeMonitor check published scalar 1.0. CUA bound to the settings window, but clicking AX menu-bar element 84 opened the app's About/Settings/Hide/Quit menu, not the status popover; screenshots were unavailable. Final read-only CUA lookups for SystemUIServer and Control Center both timed out with error -10005 and returned no AX tree. Slider and keyboard interactions, switching/disconnect UI, MacBook speaker behavior, and sleep polling remain unverified. A fresh read after the UI attempts confirmed VCP 0x62 remained 100/100. Step 3 recorded 0.07 CPU seconds over a 60-second idle sample; details visibility could not be determined and open/closed request durations were not measured. Step 4 passed 387 tests, release build, and workflow 36549713915 (1.3.4/build17, `publish=false`) and updated PR #75; the workflow built an artifact without publishing. Whole-branch Luna review accepted two limitations: the approved Task 2 association supports one external framebuffer and one external DDC service, failing closed for ambiguous multi-display topology; synchronous I2C has no cancellation API, so the watchdog invalidates UI state while the single worker remains occupied until the request returns, preventing overlapping requests.

## Handoff

The user has specified Luna for implementation. After the user confirms this written plan, run it with the newest available Luna model (`gpt-6-luna` at plan time) in the existing worktree. Review each task's tests and diff before advancing; preserve the user's original hardware volume after real-device verification.
