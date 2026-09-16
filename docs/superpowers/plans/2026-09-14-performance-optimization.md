# Status Trio Performance Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate avoidable menu bar CPU work, coalesce monitor storms, bound memory growth, and make the fallback refresh interval user-adjustable.

**Architecture:** Keep the existing event-driven monitor architecture. Add a lightweight menu bar model and render key in front of AppKit, bound monitor streams with `bufferingNewest(1)`, coalesce high-frequency CoreAudio/CoreWLAN notifications, and load expensive details only while the popover is visible.

**Tech Stack:** Swift 6.1-compatible SwiftPM package, AppKit, SwiftUI, Combine, CoreAudio, CoreWLAN, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-14-performance-optimization-design.md`

## Global Constraints

- CI toolchain is Xcode 16.4 / Swift 6.1.2.
- Do not use `isolated deinit`, `weak let`, Swift 6.2-only syntax, or actor-isolated method references in `Binding.set`.
- Do not add a third-party dependency.
- Preserve existing public behavior and ad-hoc signing/release rules.
- Run `swift test` and `swift build -c release` after Swift changes.
- Run a `publish=false` release workflow after completion because the change touches actor isolation, SwiftUI bindings, and resources.

---

### Task 1: Render Deduplication And Appearance Loop Break

**Files:**
- Create: `Sources/StatusTrioCore/Models/MenuBarStatus.swift`
- Create: `Sources/StatusTrioCore/UI/Icon/StatusBarRenderCache.swift`
- Modify: `Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusPopoverView.swift`
- Modify: `Sources/StatusTrioCore/UI/Settings/IconSizePreview.swift`
- Test: `Tests/StatusTrioCoreTests/StatusBarRenderCacheTests.swift`
- Test: `Tests/StatusTrioCoreTests/StatusIconRendererTests.swift`
- Test: `Tests/StatusTrioCoreTests/StatusPresentationTests.swift`

**Interfaces:**
- Produces: `MenuBarStatus`, `MenuBarVolumeStatus`.
- Produces: `StatusBarRenderKey`, `StatusBarRenderCache.shouldRender(_:)`.
- Produces: `StatusIconRenderer.image(menuBarStatus:size:options:connectionOptions:)`.
- Keeps snapshot-based renderer overloads for existing tests.

- [ ] **Step 1: Write failing render-cache tests**

Add tests covering:

```swift
func testSameRenderKeyIsSuppressed() {
    var cache = StatusBarRenderCache()
    let key = makeKey(volumeScalar: 0.5, appearance: "NSAppearanceNameDarkAqua")
    XCTAssertTrue(cache.shouldRender(key))
    XCTAssertFalse(cache.shouldRender(key))
}

func testAppearanceChangeRendersAgain() {
    var cache = StatusBarRenderCache()
    XCTAssertTrue(cache.shouldRender(makeKey(appearance: "NSAppearanceNameAqua")))
    XCTAssertTrue(cache.shouldRender(makeKey(appearance: "NSAppearanceNameDarkAqua")))
}

func testOutputDevicesDoNotInvalidateMenuBarStatus() {
    let first = StatusSnapshot(snapshotWithOutputDevices: [device(1)])
    let second = StatusSnapshot(snapshotWithOutputDevices: [device(2)])
    XCTAssertEqual(MenuBarStatus(snapshot: first), MenuBarStatus(snapshot: second))
}
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter StatusBarRenderCacheTests`
Expected: compile failure because `StatusBarRenderCache` and `MenuBarStatus` do not exist.

- [ ] **Step 3: Implement the lightweight model and cache**

`MenuBarStatus` copies battery, Wi-Fi, connection, and volume scalar/mute/device-name fields from `StatusSnapshot`, but never copies `outputDevices`.

`StatusBarRenderKey` contains `MenuBarStatus`, icon size, battery options, connection options, and appearance name. `StatusBarRenderCache.shouldRender` stores the key before returning true.

- [ ] **Step 4: Add menu-bar renderer overloads**

Add `image(menuBarStatus:...)` and `render(menuBarStatus:...)`. Keep existing `snapshot:` overloads as wrappers that construct `MenuBarStatus(snapshot:)`.

- [ ] **Step 5: Update `StatusBarController`**

- Remove the `NSApp.effectiveAppearance` observer.
- Keep only the button appearance observer.
- Remove the periodic icon timer entirely.
- Cache `StatusBarRenderKey`.
- Assign `button.image` only when the cache returns true.
- Remove `button.setNeedsDisplay`.
- Cache an accessibility key and update accessibility only when its value changes.

- [ ] **Step 6: Update presentation and preview call sites**

Use `MenuBarStatus` for menu bar accessibility and `IconSizePreview`; leave popover views on `StatusSnapshot`.

- [ ] **Step 7: Run tests**

Run: `swift test --filter StatusBarRenderCacheTests`
Run: `swift test --filter StatusIconRendererTests`
Run: `swift test --filter StatusPresentationTests`
Expected: PASS.

---

### Task 2: Coalesce Volume And Wi-Fi Events

**Files:**
- Create: `Sources/StatusTrioCore/Monitoring/MonitorStream.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/NetworkConnectionMonitor.swift`
- Test: `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`
- Test: `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift`
- Test: `Tests/StatusTrioCoreTests/MonitorStreamTests.swift`

**Interfaces:**
- Produces: `MonitorStream.make(of:)`.
- Produces coalesced monitor refresh behavior with injectable async sleep.
- Consumes: no new Task 1 interfaces.

- [ ] **Step 1: Write failing buffering and coalescing tests**

Add a stream test:

```swift
func testMonitorStreamKeepsOnlyNewestUnconsumedValue() async {
    let (stream, continuation) = MonitorStream.make(of: Int.self)
    continuation.yield(1)
    continuation.yield(2)
    continuation.yield(3)
    var iterator = stream.makeAsyncIterator()
    XCTAssertEqual(await iterator.next(), 3)
}
```

Add a volume test that sends many event callbacks against a manual sleeper and expects one reader call after release.

Add the equivalent Wi-Fi event test.

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter MonitorStreamTests`
Run: `swift test --filter VolumeMonitorTests/testVolumeCallbacksCoalesce`
Run: `swift test --filter WiFiClassifierTests/testLinkQualityCallbacksCoalesce`
Expected: compile failure for `MonitorStream` and missing initializers.

- [ ] **Step 3: Implement `MonitorStream` and replace production streams**

Use:

```swift
enum MonitorStream {
    static func make<Element>(
        of type: Element.Type
    ) -> (AsyncStream<Element>, AsyncStream<Element>.Continuation) {
        AsyncStream.makeStream(
            of: type,
            bufferingPolicy: .bufferingNewest(1)
        )
    }
}
```

Replace production `AsyncStream.makeStream()` calls with `MonitorStream.make`.

- [ ] **Step 4: Add coalescing to `VolumeMonitor`**

Add injectable `refreshDebounceSleep` and 150 ms debounce. Event callbacks and local set/toggle operations schedule one refresh instead of calling `refresh()` directly. Cancel the pending task in `stop()` and `deinit`.

- [ ] **Step 5: Add coalescing to `WiFiMonitor`**

Add injectable `refreshDebounceSleep` and 150 ms debounce. All CoreWLAN event callbacks and path updates schedule one refresh. Keep error recovery behavior.

- [ ] **Step 6: Run tests**

Run: `swift test --filter MonitorStreamTests`
Run: `swift test --filter VolumeMonitorTests`
Run: `swift test --filter WiFiClassifierTests`
Expected: PASS.

---

### Task 3: Lazy Details And Cached Audio Device List

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/MonitorProtocols.swift`
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift`
- Test: `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`
- Test: `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift`
- Test: `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift`

**Interfaces:**
- Produces: `WiFiMonitoring.setDetailsVisible(_:)`.
- Produces: `VolumeMonitoring.setDetailsVisible(_:)`.
- Produces: `SystemStatusStore.setPopoverVisible(_:)`.
- Consumes: coalesced refresh behavior from Task 2.

- [ ] **Step 1: Write failing lazy-detail tests**

Cover:

```swift
func testVolumeDetailsLoadOnlyWhenVisible() { ... }
func testVolumeLevelRefreshReusesCachedDevices() { ... }
func testWiFiDoesNotReadSSIDWhenDetailsAreHidden() { ... }
func testPopoverVisibilityIsForwardedToDetailsMonitors() { ... }
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter VolumeMonitorTests`
Run: `swift test --filter WiFiClassifierTests`
Run: `swift test --filter SystemStatusStoreTests`
Expected: failures because `setDetailsVisible` and `setPopoverVisible` do not exist.

- [ ] **Step 3: Extend protocols and store**

Add detail visibility methods. Replace `refreshForPopoverOpening()` with `setPopoverVisible(_:)`. On open, publish the current snapshot, forward `true`, and refresh all monitors. On close, forward `false`.

- [ ] **Step 4: Implement volume caching**

- Cache `[AudioOutputDevice]`.
- Reload the cache only for full detail refreshes and default-device changes.
- Level-only event refreshes reuse the cache.
- When details are hidden, publish `outputDevices: []`.

- [ ] **Step 5: Implement conditional SSID reads**

Add `read(includeSSID:)` with a default protocol extension that calls `read()` for existing fakes. Production CoreWLAN reader skips `interface.ssid()` when `includeSSID` is false.

- [ ] **Step 6: Update popover lifecycle**

Call `store.setPopoverVisible(true)` before showing and `false` when closed.

- [ ] **Step 7: Run tests**

Run: `swift test --filter VolumeMonitorTests`
Run: `swift test --filter WiFiClassifierTests`
Run: `swift test --filter SystemStatusStoreTests`
Expected: PASS.

---

### Task 4: Release Hidden View Graphs And Cache Localization

**Files:**
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift`
- Modify: `Sources/StatusTrioCore/UI/Settings/SettingsWindowController.swift`
- Modify: `Sources/StatusTrioCore/Localization/Localization.swift`
- Modify: `Sources/StatusTrioCore/UI/OutputDeviceList.swift`
- Test: `Tests/StatusTrioCoreTests/SettingsWindowControllerTests.swift`
- Test: `Tests/StatusTrioCoreTests/LocalizationTests.swift`
- Test: `Tests/StatusTrioCoreTests/OutputDeviceListPresentationTests.swift`

**Interfaces:**
- Consumes Task 3 popover visibility behavior.
- Produces reusable, cached localization bundle lookup.
- Produces settings-window release/recreate behavior.

- [ ] **Step 1: Write failing tests**

Add tests for:
- Settings window can be shown, closed, and recreated without retaining the old window.
- Localization repeatedly returns the same cached bundle for a language.
- Output-device ordering is calculated once per presentation pass.

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter SettingsWindowControllerTests`
Run: `swift test --filter LocalizationTests`
Run: `swift test --filter OutputDeviceListPresentationTests`
Expected: new assertions fail.

- [ ] **Step 3: Release popover content on close**

Recreate the hosting controller when opening; clear `popover.contentViewController` after close.

- [ ] **Step 4: Release settings content on close**

Set the window to release on close and clear `window` and `tabController` in `windowWillClose`.

- [ ] **Step 5: Cache localization bundles**

Store resolved bundles in a `[AppLanguage: Bundle]` dictionary on `Localization`.

- [ ] **Step 6: Avoid repeated output-device sorting**

Compute ordered and visible device arrays once per `OutputDeviceList.body` evaluation and pass them to the child views.

- [ ] **Step 7: Run tests**

Run the three filtered suites from Step 2.
Expected: PASS.

---

### Task 5: Adjustable Refresh Interval

**Files:**
- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift`
- Modify: `Sources/StatusTrioCore/App/AppEnvironment.swift`
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift`
- Modify: `Sources/StatusTrioCore/UI/Settings/BasicsSettingsPane.swift`
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift`
- Modify: all `Sources/StatusTrioCore/Resources/*.lproj/Localizable.strings`
- Test: `Tests/StatusTrioCoreTests/SettingsStoreTests.swift`
- Test: `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift`

**Interfaces:**
- Produces: `SettingsStore.refreshIntervalSeconds`, `SettingsStore.refreshInterval`.
- Produces: `SystemStatusStore.setRefreshInterval(_:)`.
- Consumes render deduplication from Task 1.

- [ ] **Step 1: Write failing persistence and scheduling tests**

Cover default 5 seconds, clamping to 5–300, step rounding, persistence, and the next sleep cycle using the updated interval.

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter SettingsStoreTests`
Run: `swift test --filter SystemStatusStoreTests`
Expected: compile failures because the new properties do not exist.

- [ ] **Step 3: Implement the setting**

Add the persisted property, localized setting row, value formatter, and a 5-second step from 5 to 300 seconds.

- [ ] **Step 4: Wire the store**

Construct the store with the persisted interval. `SystemStatusStore.setRefreshInterval` updates the interval read at the start of each sleep cycle.

- [ ] **Step 5: Wire live changes**

Subscribe in `StatusBarController` to `settings.$refreshIntervalSeconds` and forward changes to the store.

- [ ] **Step 6: Verify no-change rendering**

Update the render test to assert that a periodic refresh that publishes no changed data does not call the image renderer.

- [ ] **Step 7: Run tests**

Run: `swift test --filter SettingsStoreTests`
Run: `swift test --filter SystemStatusStoreTests`
Run: `swift test --filter StatusBarRenderCacheTests`
Expected: PASS.

---

### Task 6: Full Verification

**Files:**
- No production files.

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 2: Run release build**

Run: `swift build -c release`
Expected: successful build.

- [ ] **Step 3: Run non-publishing CI preflight**

Run:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref codex/perf-optimizations \
  -f version=1.0.4 \
  -f build=5 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: workflow passes without publishing.

- [ ] **Step 4: Review diff**

Run: `git diff --check` and `git status --short`.
Expected: no whitespace errors and only intended files modified.
