# Charging Effects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship phase one of the charging comet effect: a low-cost, opt-out charging-only battery-ring animation in the menu bar, with event-only Dock bursts and safety stops.

**Architecture:** Keep geometry, timeline, event detection, and frame policy as deterministic value-level code. A single injected `@MainActor` clock publishes phases to the existing menu-bar and Dock render paths; rendering with a `nil` phase remains byte-for-byte the existing static render. Reuse `SystemStatusStore.isDisplayAsleep` instead of introducing a second display-sleep observer, and add only the system Reduce Motion observation needed by the shared clock.

**Tech Stack:** Swift 6, SwiftUI, AppKit/CoreGraphics, Combine, Swift Testing/XCTest, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-09-20-charging-effects-design.md`

## Global Constraints

- CI acceptance toolchain: `macos-26`, Xcode `26.6`, Swift `6.3.3`.
- Build the app with the macOS 26 SDK or newer.
- Animate only while `battery.isCharging`; connected-but-not-charging and charged states stay static.
- The menu bar clock runs at 20 fps; Dock draws only event bursts at 10 fps (6 frames for plug-in, 3 frames for a level advance).
- `phase == nil` and any phase received while not charging must preserve today's rendered pixels; inactive effects must not schedule redraws.
- Reduce Motion, display sleep, and the user toggle stop the phase clock and restore static rendering.
- The effect toggle defaults to `true`; this phase uses the automatic status-derived tail color only. Presets and custom color selection are out of scope for this plan.
- Add the new setting strings in all 12 shipped locales. Do not add dependencies.
- Before committing Swift changes, run `swift test` and `swift build -c release`. This work touches `@MainActor`, SwiftUI, and timer lifecycles, so a non-publishing release workflow preflight is also required before merge or publish.

## Review Focus

- **Invalid or boundary progress (`NaN`, infinities, below 0, above 1, empty/full battery):** geometry and policy tests pin safe clamping and no invalid path output (Tasks 1–2).
- **The large top gap, including a fill endpoint inside the gap and a no-gap arc:** geometry and frame tests pin visible-fraction round trips, gap-time traversal, and endpoint behavior (Tasks 1–2).
- **A stale/non-nil phase during unplugged, full, disabled, or non-charging states:** renderer and policy tests pin static output/no effect (Tasks 2–3).
- **Reduce Motion changes and display sleep/wake while charging:** clock/monitor tests pin immediate stop and resume behavior without an extra idle tick (Task 5).
- **Dock work outside events and exact burst length:** controller tests pin zero steady-state renders, 6 plug-in frames, and 3 level-advance frames (Task 6).

---

### Task 1: Battery arc intervals and visible-fraction mapping

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Icon/StatusIconGeometry.swift`
- Create: `Tests/StatusTrioCoreTests/ChargingEffectGeometryTests.swift`

**Interfaces:**
- Consumes: existing battery ring constants and `batteryArc(progress:hasTopGap:topGapWidth:)`.
- Produces: `batteryArc(from:to:hasTopGap:topGapWidth:) -> CGPath`, `batteryHighlight(from:to:hasTopGap:topGapWidth:) -> CGPath`, `visibleFraction(forProgress:hasTopGap:topGapWidth:) -> Double`, `progress(forVisibleFraction:hasTopGap:topGapWidth:) -> Double`, and `lastVisibleProgress(for:hasTopGap:topGapWidth:) -> Double`. Visible coordinates remain in full-arc progress units (`0...(1-gap)`); progress inside the gap projects to the shared midpoint/left edge, and only visible positions have a unique inverse.

- [ ] **Step 1: Write failing geometry tests** for a full continuous arc, both visible halves around the top gap, and conversion round trips at `0`, `0.1`, `0.5`, `0.9`, and `1`.

```swift
@Test func visibleFractionMappingRoundTripsAcrossChargingBoltGap() {
    for progress in [0.0, 0.1, 0.2, 0.385, 0.615, 0.8, 0.9, 1.0] {
        let visible = StatusIconGeometry.visibleFraction(
            forProgress: progress,
            hasTopGap: true,
            topGapWidth: StatusIconGeometry.batteryChargingBoltTopGapWidth
        )
        let roundTrip = StatusIconGeometry.progress(
            forVisibleFraction: visible,
            hasTopGap: true,
            topGapWidth: StatusIconGeometry.batteryChargingBoltTopGapWidth
        )
        #expect(abs(roundTrip - progress) < 1e-9)
    }
}
```

- [ ] **Step 2: Run the focused test and verify the expected compile failure** because the interval and mapping APIs do not exist yet.

Run: `swift test --filter ChargingEffectGeometryTests`
Expected: FAIL because the new geometry APIs are missing.

- [ ] **Step 3: Implement interval geometry** by clamping finite endpoints to `0...1`, returning an empty path for invalid/empty intervals, and splitting `[from, to]` at the existing gap exactly as `batteryArc` does. For `hasTopGap == false`, do not remove any arc segment. Map visible fractions over the two equal halves of the visible arc and make `lastVisibleProgress` stop at the left gap edge when the fill endpoint falls inside the gap.

```swift
static func batteryArc(
    from start: Double,
    to end: Double,
    hasTopGap: Bool,
    topGapWidth: CGFloat = batteryChargingBoltTopGapWidth
) -> CGPath
```

- [ ] **Step 4: Re-run geometry tests** and add focused assertions for non-finite values, inverted intervals, `hasTopGap == false`, and a fill endpoint inside the gap.

Run: `swift test --filter ChargingEffectGeometryTests`
Expected: PASS, including empty paths for invalid/inverted ranges and monotonic visible-fraction mapping.

### Task 2: Pure phase, event, timeline, and frame policy

**Files:**
- Create: `Sources/StatusTrioCore/UI/Icon/ChargingEffectPhase.swift`
- Create: `Sources/StatusTrioCore/UI/Icon/ChargingEffectEvent.swift`
- Create: `Sources/StatusTrioCore/UI/Icon/ChargingEffectTimeline.swift`
- Create: `Sources/StatusTrioCore/UI/Icon/ChargingEffectPolicy.swift`
- Create: `Tests/StatusTrioCoreTests/ChargingEffectTimelineTests.swift`
- Create: `Tests/StatusTrioCoreTests/ChargingEffectPolicyTests.swift`

**Interfaces:**
- Consumes: `BatteryStatus`, the Task 1 visible-arc mapping, and the confirmed defaults: 32% tail, 1.8-second steady cycle, 0.6-second plug-in burst, 0.25-second heartbeat, and 20 steps/second.
- Produces: `ChargingEffectPhase(step:stepsPerCycle:kind:heartbeatMultiplier:)`, `ChargingEffectEvent.between(previous:current:)`, `ChargingEffectTimeline.phase(elapsed:kind:heartbeatMultiplier:)`, `ChargingEffectPolicy.shouldAnimate(battery:enabled:reduceMotion:displayAsleep:)`, and `ChargingEffectPolicy.frame(progress:phase:hasTopGap:topGapWidth:) -> ChargingEffectFrame?`.
- `ChargingEffectFrame` carries the optional tail interval, head progress, tail/bead alpha, and heartbeat scale; `.nil` tail means endpoint heartbeat only. `heartbeatMultiplier` defaults to `1`; an integer charge-level advance sets it to `1.35` for the next heartbeat without changing steady-cycle timing.

- [ ] **Step 1: Write failing pure tests** for event transitions, cycle boundaries, 0.6-second/1.8-second timeline lengths, a 1.35× next-heartbeat level pulse, 25% visible-fill suppression, gap-safe endpoints, tail length capped at 78% of visible fill, and the `shouldAnimate` truth table (charging, plugged but not charging, charged, disabled, Reduce Motion, and display asleep).

```swift
@Test func levelAdvanceDoesNotReplaceTheSteadyTimeline() {
    let event = ChargingEffectEvent.between(
        previous: batteryStatus(53, charging: true),
        current: batteryStatus(54, charging: true)
    )
    #expect(event == .levelAdvanced)
    #expect(
        ChargingEffectTimeline.phase(elapsed: 0.9, kind: .steady)?.step == 18
    )
}

private func batteryStatus(_ percentage: Int, charging: Bool) -> BatteryStatus {
    BatteryStatus(
        rawPercentage: percentage,
        isPresent: true,
        isCharging: charging,
        isLowPowerMode: false,
        isConnectedToPower: charging
    )
}
```

- [ ] **Step 2: Run the focused tests and verify they fail because the domain types are absent.**

Run: `swift test --filter 'ChargingEffect(Timeline|Policy)Tests'`
Expected: FAIL because `ChargingEffectEvent`, `ChargingEffectTimeline`, and `ChargingEffectPolicy` are not defined.

- [ ] **Step 3: Implement the value types and pure functions** with finite/clamped inputs. The timeline maps elapsed seconds to deterministic integer steps (20 per second); a burst is one 12-step compressed round. `between` returns `.pluggedIn` only on `false -> true` charging and `.levelAdvanced` only for an increasing integer percentage while charging. Frame calculation uses the gap's left edge as the terminal head when the fill endpoint lies inside the gap; under 25% visible fill it returns no tail but retains the heartbeat point.

```swift
struct ChargingEffectPhase: Equatable, Hashable, Sendable {
    enum Kind: Equatable, Hashable, Sendable { case burst, steady }
    let step: Int
    let stepsPerCycle: Int
    let kind: Kind
    let heartbeatMultiplier: Double

    init(
        step: Int,
        stepsPerCycle: Int,
        kind: Kind,
        heartbeatMultiplier: Double = 1
    ) {
        self.step = step
        self.stepsPerCycle = stepsPerCycle
        self.kind = kind
        self.heartbeatMultiplier = heartbeatMultiplier
    }
}
```

- [ ] **Step 4: Re-run focused tests and confirm all edge cases** including finite progress normalization, burst wrap, heartbeat decay, and no interval intersecting the top gap.

Run: `swift test --filter 'ChargingEffect(Timeline|Policy)Tests'`
Expected: PASS.

### Task 3: Automatic tail palette and static-safe renderer

**Files:**
- Modify: `Sources/StatusTrioCore/Models/BatteryIconOptions.swift`
- Create: `Sources/StatusTrioCore/UI/Icon/ChargingEffectPalette.swift`
- Modify: `Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift`
- Modify: `Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift`
- Create: `Tests/StatusTrioCoreTests/ChargingEffectRenderingTests.swift`
- Create: `Tests/StatusTrioCoreTests/ChargingEffectPaletteTests.swift`

**Interfaces:**
- Consumes: Task 2's `ChargingEffectFrame` and the existing fill role/color selection.
- Produces: `BatteryIconOptions.showsChargingEffect` (default `true`), an optional `phase: ChargingEffectPhase? = nil` input on the five public status-icon image/render/draw entry points and Dock image entry point, and `ChargingEffectPalette.automaticHighlight(for:)` that mixes the active fill toward white until it reaches at least 1.8:1 contrast (with a deterministic fallback when that direction cannot reach the target). Task 4 persists and exposes the option.

- [ ] **Step 1: Add failing renderer tests** proving `nil` phase matches a frozen pixel fingerprint captured from the current renderer before any production edit, a non-nil phase on a non-charging battery equals the static render, and an active phase changes pixels only on the battery fill/overlay region. Add color tests for charging green, critical red, low-power yellow, and monochrome foreground roles.

```swift
@Test func nonChargingBatteryIgnoresSuppliedChargingPhase() throws {
    let snapshot = StatusSnapshot(
        battery: BatteryStatus(
            rawPercentage: 62, isPresent: true, isCharging: false,
            isLowPowerMode: false, isConnectedToPower: false
        ),
        wifi: .placeholder,
        connection: .wifi,
        volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
    )
    let staticPixels = try pixelBytes(snapshot: snapshot, phase: nil)
    let animatedPixels = try pixelBytes(
        snapshot: snapshot,
        phase: .init(step: 7, stepsPerCycle: 36, kind: .steady)
    )
    #expect(animatedPixels == staticPixels)
}

private func pixelBytes(
    snapshot: StatusSnapshot,
    phase: ChargingEffectPhase?
) throws -> [UInt8] {
    let image = try #require(StatusIconRenderer.render(
        snapshot: snapshot,
        size: 20,
        scale: 2,
        foreground: CGColor(gray: 1, alpha: 1),
        phase: phase
    ))
    return try PixelBuffer(image: image).bytes
}
```

- [ ] **Step 2: Run the selected renderer tests and verify the new calls fail to compile** until the phase parameters exist.

Run: `swift test --filter 'ChargingEffectRenderingTests'`
Expected: FAIL because the renderer phase parameter and BatteryIconOptions toggle are not implemented yet.

- [ ] **Step 3: Add the phase parameter with a default of `nil` through `image`, `render`, and `draw`; in `drawBattery`, overlay only when both `options.showsChargingEffect` and `battery.isCharging` and a phase are present.** Draw the clipped, split highlight arc, bead, and heartbeat above the existing fill using the automatic role-derived palette. Leave the current track, fill, bolt, and all other icon layers in their existing order when phase is nil.

```swift
if options.showsChargingEffect, battery.isCharging, let phase,
   let frame = ChargingEffectPolicy.frame(
       progress: StatusMappings.batteryProgress(battery),
       phase: phase,
       hasTopGap: hasTopGap,
       topGapWidth: topGapWidth
   ) {
    drawChargingEffect(frame, fillColor: arcColor, in: context)
}
```

- [ ] **Step 4: Verify static and active pixel tests**, including top-gap endpoint, no-gap full arc, and `showsChargingEffect == false`.

Run: `swift test --filter 'StatusIconRendererTests|ChargingEffectRenderingTests|ChargingEffectPaletteTests|DockIconRendererTests'`
Expected: PASS; phase nil/non-charging/disabled outputs equal baseline pixels.

### Task 4: Persisted toggle, all-locale copy, and two-cycle preview

**Files:**
- Modify: `Sources/StatusTrioCore/Settings/SettingsStore.swift`
- Create: `Sources/StatusTrioCore/UI/Settings/ChargingEffectPreviewPlayback.swift`
- Modify: `Sources/StatusTrioCore/UI/Settings/BatterySectionView.swift`
- Modify: `Sources/StatusTrioCore/UI/Settings/StatusIconPreviewCard.swift`
- Modify: `Sources/StatusTrioCore/UI/IconPreviewComponents.swift`
- Modify: `Sources/StatusTrioCore/Localization/LocalizationKey.swift`
- Modify: `Sources/StatusTrioCore/Resources/ar.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/de.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/es.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/fr.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/it.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/ja.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/ko.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/pt-BR.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/ru.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/StatusTrioCore/Resources/zh-Hant.lproj/Localizable.strings`
- Create: `Tests/StatusTrioCoreTests/ChargingEffectSettingsTests.swift`
- Create: `Tests/StatusTrioCoreTests/ChargingEffectLocalizationTests.swift`
- Create: `Tests/StatusTrioCoreTests/ChargingEffectPreviewPlaybackTests.swift`

**Interfaces:**
- Consumes: existing `SettingsStore.batteryIconOptions`, `iconAppearancePublisher`, and `StatusIconPreviewCard`.
- Produces: persisted `SettingsStore.showsChargingEffect` (default `true`), and two keys `settingsBatteryChargingEffect` / `settingsBatteryChargingEffectDescription` in every shipped locale. While an enabled real charge is active, `StatusIconPreviewCard` displays the shared production clock phase and real status; otherwise, enabling the effect replays two 1.8-second steady cycles with a local preview-only charging status. The local replay never changes the real battery snapshot.

- [ ] **Step 1: Write failing persistence, option-propagation, localization-coverage, and preview-duration tests.** Assert a missing defaults key enables the effect, an explicit false persists across store instances and reaches `batteryIconOptions`, all 12 bundles have both keys, and preview playback expires after 3.6 seconds.

```swift
@MainActor @Test func chargingEffectDefaultsOnAndPersists() throws {
    let domain = "ChargingEffectSettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }

    let first = SettingsStore(defaults: defaults)
    #expect(first.showsChargingEffect)
    first.showsChargingEffect = false
    #expect(SettingsStore(defaults: defaults).showsChargingEffect == false)
    #expect(SettingsStore(defaults: defaults).batteryIconOptions.showsChargingEffect == false)
}
```

- [ ] **Step 2: Run only these focused tests and confirm they fail** on missing settings, playback, and localization keys.

Run: `swift test --filter 'ChargingEffectSettingsTests|ChargingEffectLocalizationTests|ChargingEffectPreviewPlaybackTests'`
Expected: FAIL for absent effect setting/API and locale keys.

- [ ] **Step 3: Implement the persisted setting and preview**. Add the setting to `SettingsStore` and the existing icon appearance pipeline; `BatteryIconOptions` already owns the effect option from Task 3. Place a green `sparkles` toggle directly below the charging-indicator toggle. The description must state that it runs only while charging and stops when Reduce Motion is on. When an enabled real charge is active, the settings preview uses the shared production clock phase and real battery status. On an off-to-on transition without a live phase, run two cycles using the view's local preview-only charging status; stop immediately for Reduce Motion, view disappearance, or after 3.6 seconds. Add equivalent localized strings to the 12 locale files using each locale's existing terms for charging and motion reduction.

```swift
SettingsToggleRow(
    symbol: "sparkles",
    tint: .green,
    title: localization.string(.settingsBatteryChargingEffect),
    subtitle: localization.string(.settingsBatteryChargingEffectDescription),
    isOn: $store.showsChargingEffect
)
```

- [ ] **Step 4: Re-run settings, localization, and preview tests**, including an active-charge test proving the preview uses the shared clock phase, then run `swift test --filter 'BatterySectionView|SettingsViewTests'` to catch layout or accessibility regressions.

Run: `swift test --filter 'SettingsStoreTests|LocalizationTests|ChargingEffectSettingsTests|ChargingEffectLocalizationTests|ChargingEffectPreviewPlaybackTests|SettingsViewTests'`
Expected: PASS; local preview replay never mutates battery status, live charging uses the shared phase, and all 12 translations are non-empty.

### Task 5: Shared 20-fps clock and Reduce Motion stop/resume

**Files:**
- Create: `Sources/StatusTrioCore/UI/Icon/ChargingEffectClock.swift`
- Create: `Sources/StatusTrioCore/App/ChargingEffectMotionMonitor.swift`
- Modify: `Sources/StatusTrioCore/App/AppEnvironment.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift`
- Modify: `Sources/StatusTrioCore/App/AppIconController.swift`
- Verify: `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift`
- Create: `Tests/StatusTrioCoreTests/ChargingEffectClockTests.swift`
- Create: `Tests/StatusTrioCoreTests/ChargingEffectMotionMonitorTests.swift`

**Interfaces:**
- Consumes: battery changes from `SystemStatusStore.snapshot`, `SettingsStore.showsChargingEffect`, `SystemStatusStore.isDisplayAsleep`, a Reduce Motion value, and injectable clock/sleep closures.
- Produces: one app-lifetime `@MainActor ChargingEffectClock` with `@Published private(set) var phase: ChargingEffectPhase?`, a read-only `isRunning` state, `start()`, `stop()`, and `update(battery:enabled:reduceMotion:displayAsleep:)`. The animation sleep interval is 50ms; event detection feeds `.pluggedIn` / `.levelAdvanced` into the timeline.

- [ ] **Step 1: Write failing clock and motion-monitor tests** for idle/no-loop, charging ticks, immediate stop on disable/unplug/Reduce Motion/display sleep, resume after wake, one initial plug-in burst, and a level increase that pulses the next heartbeat without resetting the steady cycle.

```swift
@MainActor @Test func reduceMotionClearsPhaseAndCancelsPendingTick() async {
    let sleeper = ManualEventSleeper()
    let clock = ChargingEffectClock(sleep: { await sleeper.sleep($0) })
    clock.update(battery: chargingBattery(61), enabled: true, reduceMotion: false, displayAsleep: false)
    await sleeper.waitForCallCount(1)
    clock.update(battery: chargingBattery(61), enabled: true, reduceMotion: true, displayAsleep: false)
    #expect(clock.phase == nil)
    #expect(clock.isRunning == false)
    sleeper.releaseAll()
    await sleeper.waitForCompletionCount(1)
    #expect(sleeper.callCount == 1)
}

private func chargingBattery(_ percentage: Int) -> BatteryStatus {
    BatteryStatus(
        rawPercentage: percentage,
        isPresent: true,
        isCharging: true,
        isLowPowerMode: false,
        isConnectedToPower: true
    )
}
```

- [ ] **Step 2: Run the focused tests and verify failure is due to missing clock/monitor types.**

Run: `swift test --filter 'ChargingEffectClockTests|ChargingEffectMotionMonitorTests'`
Expected: FAIL because the shared clock and Reduce Motion monitor do not exist.

- [ ] **Step 3: Implement an injected 20-fps clock** that starts only when charging and enabled, publishes deterministic phases, cancels its task and publishes nil immediately on all stop conditions, and resumes from a fresh phase after wake. Implement Reduce Motion reading/notifications with injected reader and notification center for tests. In `AppEnvironment`, create exactly one clock and pass the same instance to both icon controllers. Reuse `SystemStatusStore.isDisplayAsleep` and its existing sleep/wake notifications; do not add a duplicate display-sleep monitor.

```swift
clock.update(
    battery: store.snapshot.battery,
    enabled: settings.showsChargingEffect,
    reduceMotion: motionMonitor.shouldReduceMotion,
    displayAsleep: store.isDisplayAsleep
)
```

- [ ] **Step 4: Run clock, monitor, and store sleep/wake tests** and verify no active sleep task remains after stop; the existing store sleep/wake implementation must remain unchanged.

Run: `swift test --filter 'ChargingEffectClockTests|ChargingEffectMotionMonitorTests|SystemStatusStoreTests'`
Expected: PASS.

### Task 6: Menu-bar animation and event-only Dock bursts

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Icon/StatusBarRenderCache.swift`
- Modify: `Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift`
- Modify: `Sources/StatusTrioCore/App/AppIconController.swift`
- Modify: `Sources/StatusTrioCore/App/AppEnvironment.swift`
- Create: `Tests/StatusTrioCoreTests/ChargingEffectRenderCacheTests.swift`
- Create: `Tests/StatusTrioCoreTests/ChargingEffectControllerTests.swift`

**Interfaces:**
- Consumes: the shared clock's published phase, existing `StatusIconAppearance`, and the renderer's optional phase argument.
- Produces: `StatusBarRenderKey.phase` and event-gated `DockIconRenderKey.phase`; direct menu-bar phase renders bypass `IconRenderCoalescer`, while status/setting changes continue through the existing coalescer. Dock observes the same clock but renders only alternating clock steps during bursts (10 fps), with exactly six plug-in and three level-advance frames.

- [ ] **Step 1: Write failing key/controller tests** showing distinct steady phases invalidate the menu-bar key, no-`phase` keys remain deduped, Dock keys ignore steady phases, an idle Dock receives zero clock-driven image calls, and event bursts produce exactly six or three calls.

```swift
@Test func dockKeyDoesNotVaryForSteadyPhases() {
    let first = makeKey(phase: .init(step: 2, stepsPerCycle: 36, kind: .steady))
    let second = makeKey(phase: .init(step: 3, stepsPerCycle: 36, kind: .steady))
    #expect(first == second)
}
```

- [ ] **Step 2: Run focused cache/controller tests and confirm the new phase-aware expectations fail.**

Run: `swift test --filter 'StatusBarRenderCacheTests|DockIconRenderCacheTests|ChargingEffectRenderCacheTests|ChargingEffectControllerTests|AppIconControllerTests'`
Expected: FAIL until keys and controllers consume the clock phase.

- [ ] **Step 3: Subscribe both icon controllers to the single shared clock.** The menu bar passes every active phase directly to the renderer and key, without going through the coalescer. The Dock key and image include only event-burst phases sampled every other 20-fps step; steady clock updates return before cache lookup or rendering. On stop, nil phase invalidates a previously animated menu-bar key once to restore the static image; Dock remains untouched outside a burst.

```swift
clock.$phase
    .removeDuplicates()
    .sink { [weak self] phase in
        self?.renderAnimationPhase(phase)
    }
    .store(in: &cancellables)
```

- [ ] **Step 4: Re-run cache and controller tests**, including settings-off, no Dock tile visible, display sleep, repeated stop, and charging-to-not-charging transitions.

Run: `swift test --filter 'StatusBarRenderCacheTests|DockIconRenderCacheTests|ChargingEffectRenderCacheTests|ChargingEffectControllerTests|AppIconControllerTests'`
Expected: PASS; no idle Dock redraws and exact burst counts are asserted.

### Task 7: Full verification and energy acceptance

**Files:**
- Verify: all changed source and tests from Tasks 1–6.
- Update only if required: `docs/superpowers/specs/2026-09-20-charging-effects-design.md` with measured CPU result after a real charging run.

- [ ] **Step 1: Run the full debug suite.**

Run: `swift test`
Expected: PASS; record any pre-existing warnings separately from new warnings.

- [ ] **Step 2: Run the release build.**

Run: `swift build -c release`
Expected: PASS with CI-compatible Swift; do not use experimental flags to mask compiler diagnostics.

- [ ] **Step 3: Measure the menu-bar CPU budget** for 60 seconds with animation active, then for 60 seconds with `showsChargingEffect` disabled, using the same dev build. Record mean single-core percentage and method in the design doc. The user's updated acceptance is ≤3% mean (superseding the original <1% target). The 36-frame cache alone measured 11.759% mean; the layer-backed presentation A/B measured 1.651% enabled versus 0.136% disabled, meeting the accepted budget. A synthetic charging input was used only in a temporary explicit dev-bundle test mode, now removed.

- [ ] **Step 4: Non-publishing release workflow gate (deferred by user).** Before merging or publishing, run the release workflow with `publish=false` only after the user explicitly approves that preflight and confirms the next semantic version and build number. The user has said not to package or run preflight yet; do not dispatch it during this test-only phase. If later approved, watch the run to completion and do not merge or publish unless it passes.

```bash
read -r -p 'Next release version (greater than the latest published version): ' NEXT_VERSION
read -r -p 'Next build number (greater than the latest published build): ' NEXT_BUILD
test -n "$NEXT_VERSION" && test -n "$NEXT_BUILD"
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref feature/charging-effects \
  -f version="$NEXT_VERSION" \
  -f build="$NEXT_BUILD" \
  -f publish=false
```

- [ ] **Step 5: Inspect the final diff** to confirm phase nil preserves the old static code path, all 12 locales have both toggle keys, no preset/custom-color controls slipped into phase one, and no user-owned untracked demo/content files were deleted or copied.

Run: `git diff --check && git status --short`
Expected: no whitespace errors; only planned files are changed.

## Deliberate Phase-One Exclusions

- No preset palette grid, custom `ColorPicker`, HSB persistence, contrast-report UI, or 12-locale color setting strings; those belong to phase two.
- No README translation sweep or demo-file archival/deletion. The demo in the original checkout is untracked and remains user-owned.
- No parallel display-sleep observer; `SystemStatusStore.isDisplayAsleep` already tracks `NSWorkspace.screensDidSleepNotification` and `screensDidWakeNotification`.
- Dock animation is intentionally event-driven rather than continuous, as explicitly declared by the design spec and pinned by controller tests.

## Scope Coverage Check

This plan covers phase-one spec requirements for charging-only behavior, gap-aware geometry, low-fill behavior, initial and level-advance events, shared clock, Reduce Motion/display sleep, an enabled-by-default localized switch, automatic tail color, menu-bar/Dock render-key invalidation, a shared-phase live charging preview with a local replay fallback, static-pixel preservation, and CPU budget. Phase-two requirements (preset/custom color configuration and color-setting UI) are explicitly deferred, not omitted accidentally.

## Plan Self-Review

- **Spec coverage:** Every phase-one requirement has a task and verification in Tasks 1–7; the only architecture adjustment is reusing the existing display-asleep state rather than duplicating its notification observer.
- **Placeholder scan:** No TODO/TBD or unspecified implementation steps remain; dynamic color previews are deferred with the rest of phase two.
- **Type consistency:** `ChargingEffectPhase`, `ChargingEffectEvent`, `ChargingEffectTimeline`, `ChargingEffectFrame`, and the optional renderer phase are consistently named across tasks.
- **Review focus:** Each of the five risk classes above maps to explicit tests in its owning task.
- **Existing local artifacts:** The original checkout's untracked `charging-effects-demo.html` and `claude-code-oss-application.md` are outside the isolated worktree and must not be removed or edited.
