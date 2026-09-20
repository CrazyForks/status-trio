# Icon Parity And Lifecycle Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make it impossible to add an icon option that reaches only one of the two icon surfaces, and pin the teardown that releases app-lifetime objects so a regressed `deinit` fails a test instead of leaking a timer or a NotificationCenter observer.

**Architecture:** Tests only, plus one production task that a failing test forces. A new table-driven matrix enumerates every field of the four option structs and every case of the option enums, renders both surfaces with `StatusIconRenderer` and `DockIconRenderer`, and compares pixels; a `Mirror`-based guard makes the table itself fail when a field is added without a case. A second new file pins lifetime behavior with counting notification centers, weak boxes and deallocation assertions. `IconRenderCoalescer.cancel()` gets the two assertions its existing test is missing.

**Tech Stack:** Swift 6.3.3-compatible SwiftPM package, Swift Testing (`import Testing`, `@Test`, `#expect`, `arguments:`) for the parity matrix, XCTest (`XCTAssert*`) for the lifetime file to match the existing deinit tests in `WiFiClassifierTests`/`VolumeMonitorTests`, AppKit, CoreGraphics, the existing `PixelBuffer` test support.

**Spec:** Derived from the 2026-09-20 code review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3; local Xcode 27 / Swift 6.4 compiling is NOT proof. `docs/swift-ci-compatibility.md` lists the concrete failures this caused.
- Forbidden in this repo: `isolated deinit`, enabling `IsolatedDeinit`, `weak let` (use `weak var`), passing actor-isolated methods directly as function values (use an explicit closure), assuming `Bundle.module` casing.
- Run `swift test` and `swift build -c release` before committing Swift changes. A non-publishing release preflight (`gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false`, then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`) is mandatory for changes touching actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources.
- Every failed CI run must be recorded in `docs/swift-ci-compatibility.md` with run ID, failed stage, root cause, fix and verification.
- Any change to menu bar icon rendering or icon settings must be mirrored in the Dock icon in the same change, and covered by tests for both outputs.
- Tests are mixed: most use Swift Testing (`import Testing`, `@Test`, `#expect`, `@MainActor` suites), some XCTest (`XCTAssert*`, `XCTSkipUnless`). Match the file you extend.
- No snapshot or golden-file comparisons. The parity matrix compares two renders produced in the same process, never a stored reference image.
- This plan adds tests. Production code changes only in Task 3, only because a test in Task 2 fails without it, and only in the one file named there.
- Every new lifetime assertion uses a `weak var` (never `weak let`) through the `WeakBox` helper, so it does not add a fourth "`weak var` never mutated" warning on top of the four tracked by R-20.
- Teardown-owned storage may be `nonisolated(unsafe)` only with a comment that states why the access is safe (AGENTS.md). `MainActor.assumeIsolated` in a `deinit` is forbidden in this plan: it traps instead of hopping, and `deinit` runs on whatever thread released the last reference.

## Review Focus

- A user who picks the **bold** ring stroke must see both the menu bar icon and the Dock icon thicken: pinned by the `RingStrokeStyle.allCases` matrix test, which renders `light`/`regular`/`bold` on both surfaces and requires every pair to differ, and by the `batteryOptions.ringStrokeScale` / `volumeOptions.ringStrokeScale` rows of the field table.
- A user who turns on **replace the network icon with Bluetooth audio** must see the Dock tile change too, not only the menu bar: pinned by the `BluetoothAudioIconOptions` rows (`replacesNetworkIcon`, `usesVolumeColor`, `prioritizesNetworkErrors`, `symbolScale`), each rendered against a fixture whose current output device is `transport: .bluetooth` on both surfaces.
- A user on a Mac with a light or clear Dock background must get a different tile from the dark one: pinned by the `DockIconBackgroundStyle.allCases` pairwise-distinct Dock test and by `everyDockBackgroundPreferenceResolvesToARenderableStyle`, which fails if a new `DockIconBackgroundPreference` case resolves to a style the renderer cannot draw.
- A user quitting the app must not leave a repeating timer or NotificationCenter observers behind: pinned by `IconSurfaceLifetimeTests` (`appearanceMonitorRemovesObserversWhenDeallocatedWithoutStop`, `storeRemovesWakeObserverWhenDeallocatedWithoutStop`, `bluetoothControllerRemovesObserversWhenDeallocatedWhileActive`), each of which asserts the removal count on a counting center after the object deallocates.
- A user changing an icon setting twice in a row, once during shutdown, must still get the later change applied: pinned by `IconRenderCoalescerTests.testCancelDropsThePendingRedraw` (now proving the trailing redraw was scheduled first) and `testCancelCancelsTheScheduledTrailingRedraw` (proving `cancel()` cancels the pending sleep), plus the post-cancel `submit` assertion that the next change is applied immediately.

## Existing coverage this plan does not duplicate (verified at review revision `13cdbbc`)

| Area | Already covered by |
| --- | --- |
| Dock cache invalidation per icon setting | `Tests/StatusTrioCoreTests/IconAppearancePublisherTests.swift:13-58` (18-entry `iconMutations` table, `iconSize` documented as menu-bar-only) |
| Dock cache invalidation per status change | `DockIconRenderCacheTests.swift:7-258` |
| Menu bar pixel behavior per option | `StatusIconRendererTests.swift` (`testBatteryPercentageCanBeHidden` :257, `testVolumeArcStyleDiffersFromDotsStyle` :1079, `testWiFiIconOptionsReplaceEachSpecialConnectionMark` :821, `testBluetoothOutputReplacesNetworkIconWithBluePixels` :1187, and others) |
| Dock pixel behavior for two parity cases | `Issue13IconParityTests.swift` (volume arc style, light-style cutouts) |
| Volume/Wi-Fi/Battery teardown without `stop()` | `VolumeMonitorTests.swift:409`, `WiFiClassifierTests.swift:693`, `BatteryMonitorTests.swift:446` |
| Store deallocation with weak monitor references | `SystemStatusStoreTests.swift:870` |
| Background style resolution for every preference/theme pair | `DockIconBackgroundResolverTests.swift:5-45` |
| Placement matrix | `AppIconPlacementTests.swift:5-22` |

What is missing, and what the tasks below add: nothing enumerates the option structs' fields or the option enums' cases and asserts that the Dock render *changes* too (the existing tables assert cache-key invalidation, not rendered output); no test pins the `deinit` teardown of `SystemIconAppearanceMonitor`, `SystemStatusStore`'s observer removal on deallocation, or `BluetoothDeviceController`'s observer removal on deallocation; and `IconRenderCoalescerTests.testCancelDropsThePendingRedraw` (`:82-93`) can pass when no trailing redraw was ever scheduled.

---

### Task 1: Table-Driven Menu Bar ↔ Dock Parity Matrix

**Files:**
- Create: `Tests/StatusTrioCoreTests/IconOptionParityMatrixTests.swift`

**Interfaces:**
- Consumes: `StatusIconRenderer.render(menuBarStatus:size:scale:foreground:options:connectionOptions:volumeOptions:bluetoothAudioOptions:)` (`Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift:155-166`), `DockIconRenderer.image(status:options:connectionOptions:volumeOptions:bluetoothAudioOptions:backgroundStyle:)` (`DockIconRenderer.swift:82-89`), `DockIconBackgroundResolver.style(for:theme:isDarkAppearance:)`, `DockIconRenderKey(status:options:connectionOptions:volumeOptions:bluetoothAudioOptions:backgroundStyle:)`, and `PixelBuffer` (`Tests/StatusTrioCoreTests/TestSupport/PixelBuffer.swift`).
- Produces: `Appearance` (the four option structs plus `iconSize`), `OptionCase` (`structure`, `field`, `status`, `baseline`, `mutated`, `dockAffected`), and `optionCases: [OptionCase]`.

- [ ] **Step 1: Write the matrix file (expected RED: no assertion has ever run on these pairs, and any row that is wrong fails immediately)**

Create `Tests/StatusTrioCoreTests/IconOptionParityMatrixTests.swift`:

```swift
import AppKit
import CoreGraphics
import Testing
@testable import StatusTrioCore

/// Menu bar ↔ Dock parity for every icon input.
///
/// AGENTS.md makes parity a hard rule. `IconAppearancePublisherTests` proves a
/// setting invalidates both render caches; this file proves the two rendered
/// images actually change, and that the field list below still matches the
/// option structs, so a newly added field cannot ship with only one surface
/// covered.
@MainActor
struct IconOptionParityMatrixTests {
    @Test func everyOptionFieldHasAParityCase() throws {
        for structure in ["BatteryIconOptions", "ConnectionIconOptions",
                          "VolumeIconOptions", "BluetoothAudioIconOptions",
                          "StatusIconAppearance"] {
            let declared = try mirroredFieldNames(structure)
            let covered = Set(Self.optionCases.filter { $0.structure == structure }.map(\.field))
            #expect(
                covered == declared,
                "\(structure): add an OptionCase for \(declared.subtracting(covered).sorted()), remove cases for \(covered.subtracting(declared).sorted())"
            )
        }
    }

    @Test func everyOptionFieldChangesBothSurfaces() throws {
        for optionCase in Self.optionCases {
            let baselineMenuBar = try menuBarPixels(optionCase.baseline, status: optionCase.status)
            let mutatedMenuBar = try menuBarPixels(optionCase.mutated, status: optionCase.status)
            #expect(
                baselineMenuBar.bytes != mutatedMenuBar.bytes,
                "\(optionCase.structure).\(optionCase.field) must change the menu bar icon"
            )

            let baselineDock = try dockPixels(optionCase.baseline, status: optionCase.status)
            let mutatedDock = try dockPixels(optionCase.mutated, status: optionCase.status)
            if optionCase.dockAffected {
                #expect(
                    baselineDock.bytes != mutatedDock.bytes,
                    "\(optionCase.structure).\(optionCase.field) must change the Dock icon"
                )
                #expect(
                    dockKey(optionCase.baseline, status: optionCase.status)
                        != dockKey(optionCase.mutated, status: optionCase.status),
                    "\(optionCase.structure).\(optionCase.field) must invalidate the Dock render key"
                )
            } else {
                // Documented menu-bar-only input: the Dock tile must not move.
                #expect(baselineDock.bytes == mutatedDock.bytes, "\(optionCase.field) is menu bar only")
            }
        }
    }

    @Test func optionEnumCasesAreExactlyTheCoveredOnes() {
        #expect(VolumeDisplayStyle.allCases == [.dots, .arc])
        #expect(RingStrokeStyle.allCases == [.light, .regular, .bold])
        #expect(DockIconBackgroundStyle.allCases == [.dark, .light, .clear])
        #expect(DockIconBackgroundPreference.allCases == [.system, .dark, .light])
    }

    @Test func everyVolumeDisplayStyleRendersBothSurfacesDistinctly() throws {
        let status = Self.discharging(68)
        var menuBar: [VolumeDisplayStyle: [UInt8]] = [:]
        var dock: [VolumeDisplayStyle: [UInt8]] = [:]
        for style in VolumeDisplayStyle.allCases {
            var appearance = Appearance()
            appearance.volume = VolumeIconOptions(displayStyle: style)
            menuBar[style] = try menuBarPixels(appearance, status: status).bytes
            dock[style] = try dockPixels(appearance, status: status).bytes
        }
        for lhs in VolumeDisplayStyle.allCases {
            for rhs in VolumeDisplayStyle.allCases where lhs != rhs {
                #expect(menuBar[lhs] != menuBar[rhs], "\(lhs) and \(rhs) must differ in the menu bar")
                #expect(dock[lhs] != dock[rhs], "\(lhs) and \(rhs) must differ in the Dock")
            }
        }
    }

    @Test func everyRingStrokeStyleRendersBothSurfacesDistinctly() throws {
        let status = Self.discharging(68)
        var menuBar: [RingStrokeStyle: [UInt8]] = [:]
        var dock: [RingStrokeStyle: [UInt8]] = [:]
        for style in RingStrokeStyle.allCases {
            var appearance = Appearance()
            appearance.battery = BatteryIconOptions(ringStrokeScale: style.scale)
            appearance.volume = VolumeIconOptions(ringStrokeScale: style.scale)
            // Rendered at 16x: one stroke step is a sub-pixel width change at 8x,
            // and the assertion is about the drawn result, not about tolerance.
            menuBar[style] = try menuBarPixels(appearance, status: status, menuBarScale: 16).bytes
            dock[style] = try dockPixels(appearance, status: status).bytes
        }
        for lhs in RingStrokeStyle.allCases {
            for rhs in RingStrokeStyle.allCases where lhs != rhs {
                #expect(menuBar[lhs] != menuBar[rhs], "\(lhs) and \(rhs) must differ in the menu bar")
                #expect(dock[lhs] != dock[rhs], "\(lhs) and \(rhs) must differ in the Dock")
            }
        }
    }

    @Test func everyDockBackgroundStyleRendersDistinctly() throws {
        let status = Self.discharging(68)
        var renders: [DockIconBackgroundStyle: [UInt8]] = [:]
        for style in DockIconBackgroundStyle.allCases {
            renders[style] = try dockPixels(Appearance(), status: status, backgroundStyle: style).bytes
        }
        for lhs in DockIconBackgroundStyle.allCases {
            for rhs in DockIconBackgroundStyle.allCases where lhs != rhs {
                #expect(renders[lhs] != renders[rhs], "\(lhs) and \(rhs) must not render the same tile")
            }
        }
    }

    @Test func everyDockBackgroundPreferenceResolvesToARenderableStyle() throws {
        for preference in DockIconBackgroundPreference.allCases {
            for theme in Self.themes {
                let style = DockIconBackgroundResolver.style(
                    for: preference,
                    theme: theme,
                    isDarkAppearance: false
                )
                #expect(
                    DockIconBackgroundStyle.allCases.contains(style),
                    "\(preference) resolved \(style) outside the renderable styles"
                )
                _ = try dockPixels(Appearance(), status: Self.discharging(68), backgroundStyle: style)
            }
        }
    }

    // MARK: - Fixtures

    private struct Appearance {
        var iconSize: Double = 22
        var battery = BatteryIconOptions.standard
        var connection = ConnectionIconOptions.standard
        var volume = VolumeIconOptions.standard
        var bluetoothAudio = BluetoothAudioIconOptions.standard
    }

    private struct OptionCase {
        let structure: String
        let field: String
        let status: MenuBarStatus
        let baseline: Appearance
        let mutated: Appearance
        var dockAffected: Bool = true
    }

    private static let standardAppearance = Appearance()

    private static let optionCases: [OptionCase] = [
        OptionCase(
            structure: "StatusIconAppearance", field: "iconSize",
            status: Self.discharging(68), baseline: standardAppearance,
            mutated: Appearance(iconSize: 32), dockAffected: false
        ),
        OptionCase(
            structure: "BatteryIconOptions", field: "showsPercentage",
            status: discharging(68), baseline: standardAppearance,
            mutated: Appearance(battery: BatteryIconOptions(showsPercentage: false))
        ),
        OptionCase(
            structure: "BatteryIconOptions", field: "showsChargingIndicator",
            status: charging(68), baseline: standardAppearance,
            mutated: Appearance(battery: BatteryIconOptions(showsChargingIndicator: false))
        ),
        OptionCase(
            structure: "BatteryIconOptions", field: "usesStatusColors",
            status: discharging(12), baseline: standardAppearance,
            mutated: Appearance(battery: BatteryIconOptions(usesStatusColors: false))
        ),
        OptionCase(
            structure: "BatteryIconOptions", field: "showsPercentageWhenConnected",
            status: connectedToPower(68), baseline: standardAppearance,
            mutated: Appearance(battery: BatteryIconOptions(showsPercentageWhenConnected: true))
        ),
        OptionCase(
            structure: "BatteryIconOptions", field: "criticalThreshold",
            status: discharging(12), baseline: standardAppearance,
            mutated: Appearance(battery: BatteryIconOptions(criticalThreshold: 5))
        ),
        OptionCase(
            structure: "BatteryIconOptions", field: "textScale",
            status: discharging(68), baseline: standardAppearance,
            mutated: Appearance(battery: BatteryIconOptions(textScale: 2.4))
        ),
        OptionCase(
            structure: "BatteryIconOptions", field: "ringStrokeScale",
            status: discharging(68), baseline: standardAppearance,
            mutated: Appearance(battery: BatteryIconOptions(ringStrokeScale: 2.0))
        ),
        OptionCase(
            structure: "ConnectionIconOptions", field: "showsWiFiIconForEthernet",
            status: ethernetStatus(), baseline: standardAppearance,
            mutated: Appearance(connection: ConnectionIconOptions(showsWiFiIconForEthernet: true))
        ),
        OptionCase(
            structure: "ConnectionIconOptions", field: "showsWiFiIconForHotspot",
            status: wifiStatus(.hotspot), baseline: standardAppearance,
            mutated: Appearance(connection: ConnectionIconOptions(showsWiFiIconForHotspot: true))
        ),
        OptionCase(
            structure: "ConnectionIconOptions", field: "showsWiFiIconForTemporaryConnection",
            status: wifiStatus(.temporary), baseline: standardAppearance,
            mutated: Appearance(connection: ConnectionIconOptions(showsWiFiIconForTemporaryConnection: true))
        ),
        OptionCase(
            structure: "ConnectionIconOptions", field: "showsWiFiIconForInternetSharing",
            status: wifiStatus(.shared), baseline: standardAppearance,
            mutated: Appearance(connection: ConnectionIconOptions(showsWiFiIconForInternetSharing: true))
        ),
        OptionCase(
            structure: "ConnectionIconOptions", field: "wifiScale",
            status: wifiStatus(.connected), baseline: standardAppearance,
            mutated: Appearance(connection: ConnectionIconOptions(wifiScale: 1.5))
        ),
        OptionCase(
            structure: "VolumeIconOptions", field: "displayStyle",
            status: Self.discharging(68), baseline: standardAppearance,
            mutated: Appearance(volume: VolumeIconOptions(displayStyle: .arc))
        ),
        OptionCase(
            structure: "VolumeIconOptions", field: "ringStrokeScale",
            status: Self.discharging(68), baseline: standardAppearance,
            mutated: Appearance(volume: VolumeIconOptions(ringStrokeScale: 2.0))
        ),
        OptionCase(
            structure: "BluetoothAudioIconOptions", field: "replacesNetworkIcon",
            status: bluetoothStatus(), baseline: standardAppearance,
            mutated: Appearance(bluetoothAudio: BluetoothAudioIconOptions(replacesNetworkIcon: true))
        ),
        OptionCase(
            structure: "BluetoothAudioIconOptions", field: "usesVolumeColor",
            status: bluetoothStatus(), baseline: standardAppearance,
            mutated: Appearance(bluetoothAudio: BluetoothAudioIconOptions(usesVolumeColor: true))
        ),
        OptionCase(
            structure: "BluetoothAudioIconOptions", field: "prioritizesNetworkErrors",
            status: bluetoothStatus(wifi: .noInternet), baseline: standardAppearance,
            mutated: Appearance(bluetoothAudio: BluetoothAudioIconOptions(prioritizesNetworkErrors: false))
        ),
        OptionCase(
            structure: "BluetoothAudioIconOptions", field: "symbolScale",
            status: bluetoothStatus(), baseline: standardAppearance,
            mutated: Appearance(bluetoothAudio: BluetoothAudioIconOptions(symbolScale: 2.2))
        )
    ]

    private static let themes: [SystemIconAppearanceTheme] = [
        SystemIconAppearanceTheme(style: .defaultStyle, appearance: .light),
        SystemIconAppearanceTheme(style: .defaultStyle, appearance: .dark),
        SystemIconAppearanceTheme(style: .defaultStyle, appearance: .automatic),
        SystemIconAppearanceTheme(style: .clear, appearance: .dark),
        SystemIconAppearanceTheme(style: .tinted, appearance: .light)
    ]

    private static func discharging(_ percentage: Int) -> MenuBarStatus {
        MenuBarStatus(
            battery: BatteryStatus(
                rawPercentage: percentage, isPresent: true, isCharging: false,
                isLowPowerMode: false, isConnectedToPower: false
            ),
            wifi: WiFiStatus(state: .connected, rssi: -52),
            connection: .wifi,
            volume: MenuBarVolumeStatus(scalar: 0.5, isMuted: false, deviceName: "MacBook Speakers")
        )
    }

    private static func airPods() -> AudioOutputDevice {
        AudioOutputDevice(
            id: 42, name: "AirPods Pro", uid: "AirPods-Pro-uid", isCurrent: true,
            volume: 0.5, transport: .bluetooth
        )
    }

    private func menuBarPixels(
        _ appearance: Appearance,
        status: MenuBarStatus,
        menuBarScale: CGFloat = 8
    ) throws -> PixelBuffer {
        let image = try #require(StatusIconRenderer.render(
            menuBarStatus: status,
            size: CGFloat(appearance.iconSize),
            scale: menuBarScale,
            foreground: CGColor(gray: 1, alpha: 1),
            options: appearance.battery,
            connectionOptions: appearance.connection,
            volumeOptions: appearance.volume,
            bluetoothAudioOptions: appearance.bluetoothAudio
        ))
        return try PixelBuffer(image: image)
    }

    private func dockPixels(
        _ appearance: Appearance,
        status: MenuBarStatus,
        backgroundStyle: DockIconBackgroundStyle = .dark
    ) throws -> PixelBuffer {
        let image = try #require(DockIconRenderer.image(
            status: status,
            options: appearance.battery,
            connectionOptions: appearance.connection,
            volumeOptions: appearance.volume,
            bluetoothAudioOptions: appearance.bluetoothAudio,
            backgroundStyle: backgroundStyle
        ))
        let representation = try #require(image.representations.first as? NSBitmapImageRep)
        return try PixelBuffer(image: try #require(representation.cgImage))
    }

    private func dockKey(_ appearance: Appearance, status: MenuBarStatus) -> DockIconRenderKey {
        DockIconRenderKey(
            status: status,
            options: appearance.battery,
            connectionOptions: appearance.connection,
            volumeOptions: appearance.volume,
            bluetoothAudioOptions: appearance.bluetoothAudio,
            backgroundStyle: .dark
        )
    }

    private func mirroredFieldNames(_ structure: String) throws -> Set<String> {
        switch structure {
        case "BatteryIconOptions": return Set(Mirror(reflecting: BatteryIconOptions.standard).children.compactMap(\.label))
        case "ConnectionIconOptions": return Set(Mirror(reflecting: ConnectionIconOptions.standard).children.compactMap(\.label))
        case "VolumeIconOptions": return Set(Mirror(reflecting: VolumeIconOptions.standard).children.compactMap(\.label))
        case "BluetoothAudioIconOptions": return Set(Mirror(reflecting: BluetoothAudioIconOptions.standard).children.compactMap(\.label))
        case "StatusIconAppearance": return Set(Mirror(reflecting: Appearance()).children.compactMap(\.label))
        default: throw ParityMatrixError.unknownStructure(structure)
        }
    }
}

private enum ParityMatrixError: Error { case unknownStructure(String) }
```

The remaining fixtures referenced by the table are these five, plus the `airPods()` device already shown above:

```swift
    private static func charging(_ percentage: Int) -> MenuBarStatus {
        MenuBarStatus(
            battery: BatteryStatus(
                rawPercentage: percentage, isPresent: true, isCharging: true,
                isLowPowerMode: false, isConnectedToPower: true
            ),
            wifi: WiFiStatus(state: .connected, rssi: -52),
            connection: .wifi,
            volume: MenuBarVolumeStatus(scalar: 0.5, isMuted: false, deviceName: "MacBook Speakers")
        )
    }

    private static func connectedToPower(_ percentage: Int) -> MenuBarStatus {
        MenuBarStatus(
            battery: BatteryStatus(
                rawPercentage: percentage, isPresent: true, isCharging: false,
                isLowPowerMode: false, isConnectedToPower: true
            ),
            wifi: WiFiStatus(state: .connected, rssi: -52),
            connection: .wifi,
            volume: MenuBarVolumeStatus(scalar: 0.5, isMuted: false, deviceName: "MacBook Speakers")
        )
    }

    private static func ethernetStatus() -> MenuBarStatus {
        MenuBarStatus(
            battery: charging(68).battery,
            wifi: WiFiStatus(state: .notAssociated, rssi: nil),
            connection: .ethernet,
            volume: MenuBarVolumeStatus(scalar: 0.5, isMuted: false, deviceName: "MacBook Speakers")
        )
    }

    private static func wifiStatus(_ state: WiFiState) -> MenuBarStatus {
        MenuBarStatus(
            battery: charging(68).battery,
            wifi: WiFiStatus(state: state, rssi: -52),
            connection: .wifi,
            volume: MenuBarVolumeStatus(scalar: 0.5, isMuted: false, deviceName: "MacBook Speakers")
        )
    }

    private static func bluetoothStatus(wifi: WiFiState = .connected) -> MenuBarStatus {
        MenuBarStatus(
            battery: charging(68).battery,
            wifi: WiFiStatus(state: wifi, rssi: -52),
            connection: .wifi,
            volume: MenuBarVolumeStatus(
                scalar: 0.5, isMuted: false, deviceName: "AirPods Pro",
                currentDevice: airPods()
            )
        )
    }
```

The static fixtures are called as `Self.discharging(68)` and friends: they are `static` members of the suite, so every reference from an instance `@Test` method needs the explicit `Self.` prefix.

- [ ] **Step 2: Run the matrix and record the expected RED/GREEN split**

Run: `swift test --filter IconOptionParityMatrixTests`
Expected: PASS or a specific, actionable failure. `everyOptionFieldHasAParityCase` must pass (the table covers 19 rows for 18 declared fields across five structures; `iconSize` is the `StatusIconAppearance` row). Any `must change the Dock icon` failure means a real parity gap: record the field and stop — the Dock path must be fixed in this same change, per the AGENTS.md parity rule, and that fix is a production edit to a file owned by R-04, so escalate it as its own task instead of weakening the assertion.

- [ ] **Step 3: Prove the table guard has teeth**

Temporarily add a stored property to `BatteryIconOptions` (for example `let probeField: Bool = false` in the struct and in its memberwise initializer).

Run: `swift test --filter IconOptionParityMatrixTests/everyOptionFieldHasAParityCase`
Expected: FAIL with `BatteryIconOptions: add an OptionCase for ["probeField"]`. Revert the edit; `Sources/StatusTrioCore/Models/BatteryIconOptions.swift` must be byte-identical to `HEAD` before the commit.

- [ ] **Step 4: Run the neighbouring suites to be sure nothing was disturbed**

Run: `swift test --filter DockIconRenderCacheTests`
Run: `swift test --filter Issue13IconParityTests`
Run: `swift test --filter IconAppearancePublisherTests`
Expected: PASS. This plan adds a file and edits none of them.

- [ ] **Step 5: Commit**

```bash
git add Tests/StatusTrioCoreTests/IconOptionParityMatrixTests.swift
git commit -m "test(icons): enumerate every icon option on both surfaces

AGENTS.md requires menu bar and Dock coverage for every icon option, but the
existing tables assert cache-key invalidation rather than rendered output and
nothing enumerated the option structs' fields or the option enums' cases.

The new matrix renders both surfaces per field, compares pixels, guards the
field list with Mirror, and pins the option enums' cases so a new case or
field fails until it has a parity row."
```

---

### Task 2: Lifetime Tests For The Icon Surface And App-Lifetime Objects

**Files:**
- Create: `Tests/StatusTrioCoreTests/TestSupport/CountingNotificationCenter.swift`
- Create: `Tests/StatusTrioCoreTests/IconSurfaceLifetimeTests.swift`

**Interfaces:**
- Produces: `CountingNotificationCenter` — a `NotificationCenter` subclass that counts `addObserver(forName:object:queue:using:)` and `removeObserver(_:)` calls, mirroring the private `SpyWakeNotificationCenter` shape at `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift:1121-1141` (that exact shape already compiles on the CI toolchain; do not invent a new one).
- Produces: `WeakBox<T: AnyObject>` with a stored `weak var value: T?` so no local `weak var` is needed (a local one would add a "`weak var` never mutated" warning to the four R-20 already tracks).
- Consumes: `SystemIconAppearanceMonitor(readTheme:notificationCenter:pollingInterval:)`, `SystemStatusStore(batteryMonitor:wifiMonitor:volumeMonitor:refreshInterval:wakeNotificationCenter:)`, `BluetoothDeviceController(worker:stateMonitor:batteryReader:notificationCenter:workspaceNotificationCenter:)`.

- [ ] **Step 1: Add the shared support types**

`Tests/StatusTrioCoreTests/TestSupport/CountingNotificationCenter.swift`:

```swift
import Foundation

/// Counts observer registration and removal so a lifetime test can assert that
/// teardown removed what startup registered.
///
/// The shape mirrors `SpyWakeNotificationCenter` in SystemStatusStoreTests: a
/// `NotificationCenter` subclass with `@unchecked Sendable`, because the
/// overridden methods are nonisolated and the counters are only read from the
/// main actor after the object under test has been released.
final class CountingNotificationCenter: NotificationCenter, @unchecked Sendable {
    private(set) var addCount = 0
    private(set) var removeCount = 0

    override func addObserver(
        forName name: NSNotification.Name?,
        object: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> NSObjectProtocol {
        addCount += 1
        return super.addObserver(forName: name, object: object, queue: queue, using: block)
    }

    override func removeObserver(_ observer: Any) {
        removeCount += 1
        super.removeObserver(observer)
    }
}
```

- [ ] **Step 2: Write the lifetime tests (expected RED for the appearance monitor, PASS for the two pins)**

Create `Tests/StatusTrioCoreTests/IconSurfaceLifetimeTests.swift` with the support types and the three tests:

```swift
import AppKit
import XCTest
@testable import StatusTrioCore

/// Teardown tests for the objects that own timers, observers and run loop
/// sources. `VolumeMonitor`, `WiFiMonitor` and `BatteryMonitor` already have
/// these (`VolumeMonitorTests.swift:409`, `WiFiClassifierTests.swift:693`,
/// `BatteryMonitorTests.swift:446`); the three below had none.
@MainActor
final class IconSurfaceLifetimeTests: XCTestCase {
    func appearanceMonitorRemovesObserversWhenDeallocatedWithoutStop() {
        let center = CountingNotificationCenter()
        var box: WeakBox<SystemIconAppearanceMonitor>?

        do {
            let monitor = SystemIconAppearanceMonitor(
                readTheme: { .default },
                notificationCenter: center,
                pollingInterval: 0.05
            )
            box = WeakBox(monitor)
            monitor.start()
            XCTAssertEqual(center.addCount, 2, "start() registers the two appearance notifications")
        }

        XCTAssertNil(box?.value, "the monitor must not be retained by its own timer or observers")
        XCTAssertEqual(
            center.removeCount,
            2,
            "deallocating a started monitor must remove both observers; a released monitor that keeps them leaks a timer and a notification registration"
        )
    }

    func storeRemovesWakeObserverWhenDeallocatedWithoutStop() {
        let wakeCenter = CountingNotificationCenter()
        var box: WeakBox<SystemStatusStore>?

        do {
            let store = SystemStatusStore(
                batteryMonitor: LifetimeBatteryMonitor(),
                wifiMonitor: LifetimeWiFiMonitor(),
                volumeMonitor: LifetimeVolumeMonitor(),
                refreshInterval: .seconds(60),
                wakeNotificationCenter: wakeCenter
            )
            box = WeakBox(store)
            store.start()
            XCTAssertEqual(wakeCenter.addCount, 1)
        }

        XCTAssertNil(box?.value)
        XCTAssertEqual(wakeCenter.removeCount, 1, "SystemStatusStore.deinit must remove the wake observer")
    }

    func bluetoothControllerRemovesObserversWhenDeallocatedWhileActive() {
        let applicationCenter = CountingNotificationCenter()
        let workspaceCenter = CountingNotificationCenter()
        let stateMonitor = LifetimeBluetoothStateMonitor()
        var box: WeakBox<BluetoothDeviceController>?

        do {
            let controller = BluetoothDeviceController(
                worker: LifetimeBluetoothWorker(),
                stateMonitor: stateMonitor,
                batteryReader: LifetimeBluetoothBatteryReader(),
                notificationCenter: applicationCenter,
                workspaceNotificationCenter: workspaceCenter
            )
            box = WeakBox(controller)
            controller.activate()
            XCTAssertEqual(applicationCenter.addCount, 1, "activate() observes didBecomeActive")
            XCTAssertEqual(workspaceCenter.addCount, 1, "activate() observes didWake")
            XCTAssertEqual(stateMonitor.startCount, 1)
        }

        XCTAssertNil(box?.value)
        XCTAssertEqual(applicationCenter.removeCount, 1, "deinit must remove the activation observer")
        XCTAssertEqual(workspaceCenter.removeCount, 1, "deinit must remove the wake observer")
        XCTAssertEqual(stateMonitor.stopCount, 1, "deinit must stop the CoreBluetooth state monitor")
    }
}

@MainActor
private final class WeakBox<T: AnyObject> {
    /// `weak var`, never `weak let`: AGENTS.md forbids `weak let`.
    weak var value: T?

    init(_ value: T) { self.value = value }
}
```

The generic parameter is `AnyObject`-constrained, so the stored `weak var value: T?` is legal, and because the box is a class the `weak` binding needs no local `weak var` in the test body. Keep the `var box: WeakBox<...>?` declarations: the box is assigned inside the `do` block and read after it, which is what proves deallocation.

Append the three minimal fakes at the bottom of the same file:

```swift
@MainActor
private final class LifetimeBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class LifetimeWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() {}
}

@MainActor
private final class LifetimeVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class LifetimeBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() { startCount += 1; onStateChange?(.allowed, .poweredOn) }
    func stop() { stopCount += 1 }
}

private final class LifetimeBluetoothWorker: BluetoothPairedDeviceReading {
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(.success([]))
    }
}

private final class LifetimeBluetoothBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]) -> Void) {
        completion([:])
    }
}
```

- [ ] **Step 3: Run the lifetime tests and record the expected outcome**

Run: `swift test --filter IconSurfaceLifetimeTests`
Expected: `storeRemovesWakeObserverWhenDeallocatedWithoutStop` and `bluetoothControllerRemovesObserversWhenDeallocatedWhileActive` PASS (`SystemStatusStore.deinit` at `Sources/StatusTrioCore/Store/SystemStatusStore.swift:78-85` and R-01's `BluetoothDeviceController` teardown must have landed — this plan is wave 3 and R-01 is wave 1). `appearanceMonitorRemovesObserversWhenDeallocatedWithoutStop` FAILS with `XCTAssertEqual failed: ("0") is not equal to ("2")`: `SystemIconAppearanceMonitor` has no `deinit`, so a monitor released without `stop()` keeps both observers and its repeating timer. That failure is the next task.

If the Bluetooth test fails, report it against `2026-09-20-bluetooth-polling-and-lifetime.md` (R-01) instead of weakening the assertion here: it asserts the behavior R-01 promises.

- [ ] **Step 4: Commit the tests with the failing case documented**

```bash
git add Tests/StatusTrioCoreTests/TestSupport/CountingNotificationCenter.swift Tests/StatusTrioCoreTests/IconSurfaceLifetimeTests.swift
git commit -m "test(lifetime): pin observer teardown for the icon surface and app objects

Adds a counting notification center and three deallocation tests. The store and
Bluetooth controller assertions pin teardown that already exists (the latter is
R-01's fix); the appearance-monitor test currently fails because
SystemIconAppearanceMonitor has no deinit, which the next commit addresses."
```

---

### Task 3: Fix The Teardown The Lifetime Test Revealed (production change)

This is the only production change in this plan. It exists because Task 2 produced a failing test, not because of a review preference: a `SystemIconAppearanceMonitor` that is released while started keeps two NotificationCenter registrations and a repeating `Timer` (`Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift:33-46`) alive for the rest of the process.

**Files:**
- Modify: `Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift`

**Interfaces:**
- Consumes: `stop()` (:48-54), which removes the observers and invalidates the timer.
- Produces: `nonisolated(unsafe) private var observers` / `nonisolated(unsafe) private var pollTimer`, a shared `nonisolated private func tearDownRegistrations()`, and a plain `deinit` that calls it. No initializer or method signature changes, so every existing call site (`AppIconController.swift:72-75` constructs it, `:119` stops it) keeps compiling.

- [ ] **Step 1: Move the teardown-owned storage and add a plain `deinit`**

Do **not** write `deinit { MainActor.assumeIsolated { stop() } }`. `MainActor.assumeIsolated` is a fatal assertion rather than a hop, and `deinit` runs on whatever thread releases the last reference, so that form would add a fresh instance of the latent-trap class that `2026-09-20-volume-monitor-main-actor-io.md` (R-06) is removing from `VolumeMonitor`. Use the pattern the repo already sanctions for teardown-owned storage — `SystemStatusStore.swift:32` (`nonisolated(unsafe) private var wakeObserver`) with a plain `deinit` at `:78-85`:

```swift
    /// Teardown-owned registration state.
    ///
    /// `deinit` is nonisolated, so these are `nonisolated(unsafe)`: they are only
    /// ever mutated on the main actor while the monitor is alive, and the two
    /// operations the teardown performs are safe from any thread —
    /// `NotificationCenter.removeObserver(_:)` is thread-safe and
    /// `Timer.invalidate()` may be called from any thread. This mirrors
    /// `SystemStatusStore.wakeObserver` and avoids `MainActor.assumeIsolated`,
    /// which would trap rather than hop if the last reference were released off
    /// the main thread.
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var pollTimer: Timer?

    deinit {
        tearDownRegistrations()
    }

    /// Removes every observer and invalidates the poll timer.
    ///
    /// `stop()` and `deinit` share this body so the two teardown paths cannot
    /// drift apart; the assertions in `IconSurfaceLifetimeTests` pin both.
    nonisolated private func tearDownRegistrations() {
        observers.forEach(notificationCenter.removeObserver)
        observers.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func stop() {
        tearDownRegistrations()
    }
```

`observe(_:)` (:66-75) and `start()` (:33-46) keep mutating the same two properties plus `observers.append(...)`; they run on the main actor, so the `nonisolated(unsafe)` storage is only unguarded for the teardown path. The shared helper makes `stop()` idempotent, and a `deinit` after an explicit `stop()` is a no-op.

- [ ] **Step 2: Run the failing test**

Run: `swift test --filter IconSurfaceLifetimeTests/appearanceMonitorRemovesObserversWhenDeallocatedWithoutStop`
Expected: PASS, `removeCount == 2`.

- [ ] **Step 3: Run the whole appearance-monitor suite**

Run: `swift test --filter SystemIconAppearanceMonitorTests`
Run: `swift test --filter AppIconControllerTests`
Expected: both PASS. The second suite matters because `AppIconController.stop()` stops the monitor explicitly (`AppIconController.swift:119`), so the new `deinit` must be a no-op on that path.

- [ ] **Step 4: State the timer half of the claim honestly**

Run: `swift test --filter SystemIconAppearanceMonitorTests/pollsUntilStopped`
Expected: PASS. That test — rewritten by `2026-09-20-fixed-sleep-test-hardening.md` — proves that the shared teardown invalidates the timer, by showing a peer monitor with the same period still ticking while the stopped one stays silent. `deinit` now calls that same `tearDownRegistrations()`, so timer invalidation on deallocation is pinned transitively. Pinning it *directly* would need a timer-factory seam in this file, which this plan deliberately does not add: the file belongs to R-05 (`2026-09-20-appearance-poll-tolerance.md`), which lands first and changes the timer's tolerance.

- [ ] **Step 5: Confirm no main-actor assertion was introduced**

Run: `grep -n "assumeIsolated\|isolated deinit" Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
swift build
git add Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift
git commit -m "fix(appearance): release the poll timer and observers on deallocation

A SystemIconAppearanceMonitor released while started kept two NotificationCenter
registrations and a repeating timer alive for the process lifetime; only an
explicit stop() released them.

The registrations and the timer are now nonisolated(unsafe) teardown-owned
storage cleaned by a shared nonisolated helper that both stop() and deinit call,
mirroring SystemStatusStore's deinit. No MainActor.assumeIsolated is involved:
deinit runs on whatever thread released the object, so an assertion there would
be a trap rather than a hop."
```

---

### Task 4: Pin `IconRenderCoalescer.cancel()` Completely

**Files:**
- Modify: `Tests/StatusTrioCoreTests/IconRenderCoalescerTests.swift`

**Interfaces:**
- Consumes: `IconRenderCoalescer(minimumInterval:now:sleep:)` and `cancel()` (`Sources/StatusTrioCore/UI/Icon/IconRenderCoalescer.swift:55-90`), `ManualEventSleeper` (`Tests/StatusTrioCoreTests/ManualEventSleeper.swift`), the file-local `makeCoalescer(sleeper:now:)` (:95-102).
- Produces: `CoalescerSleepProbe`, a `@MainActor` probe that makes `Task` cancellation observable.

- [ ] **Step 1: Strengthen `testCancelDropsThePendingRedraw` (:82-93)**

```swift
    func testCancelDropsThePendingRedraw() async {
        let sleeper = ManualEventSleeper()
        var redraws: [String] = []
        let coalescer = makeCoalescer(sleeper: sleeper)

        coalescer.submit { redraws.append("prime") }
        coalescer.submit { redraws.append("pending") }

        // Prove the trailing redraw was actually scheduled. Without this the
        // assertions below also hold when no task was ever created, which is the
        // same "passes for the wrong reason" defect the 900 ms Dock sleeps had.
        await sleeper.waitForCallCount(1)
        XCTAssertEqual(sleeper.callCount, 1)

        coalescer.cancel()
        sleeper.releaseAll()
        await waitUntil { redraws.count > 1 }

        XCTAssertEqual(redraws, ["prime"], "cancel() must drop the pending trailing redraw")

        // cancel() must also clear the coalescing state, so the next change is
        // applied immediately instead of waiting out a cancelled interval.
        coalescer.submit { redraws.append("after-cancel") }

        XCTAssertEqual(redraws, ["prime", "after-cancel"])
        XCTAssertEqual(sleeper.callCount, 1, "the post-cancel submit must not be deferred")
    }

    /// The real scheduler's `Task.sleep` throws on cancellation; the manual
    /// sleeper cannot observe that, so cancellation is pinned with the real
    /// `Task.sleep` path and a main-actor probe.
    func testCancelCancelsTheScheduledTrailingRedraw() async {
        let probe = CoalescerSleepProbe()
        let fixedDate = Date()
        var redraws: [String] = []
        let coalescer = IconRenderCoalescer(
            minimumInterval: 0.05,
            now: { fixedDate },
            sleep: { _ in try await probe.sleepUntilCancelled() }
        )

        coalescer.submit { redraws.append("prime") }
        coalescer.submit { redraws.append("pending") }
        await waitUntil { probe.startedCount == 1 }

        coalescer.cancel()

        await waitUntil { probe.cancelledCount == 1 }
        XCTAssertEqual(probe.startedCount, 1, "exactly one trailing sleep is scheduled")
        XCTAssertEqual(redraws, ["prime"], "the cancelled trailing redraw must not run")
    }
```

Add the probe next to the existing private helpers at the bottom of the file:

```swift
@MainActor
private final class CoalescerSleepProbe {
    private(set) var startedCount = 0
    private(set) var cancelledCount = 0

    func sleepUntilCancelled() async throws {
        startedCount += 1
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            cancelledCount += 1
            throw error
        }
    }
}
```

The existing `waitUntil(_:attempts:)` helper (:104-112) is a `Task.yield` loop; both new waits resolve within a few yields, so it is sufficient here and no clock-based helper is needed.

- [ ] **Step 2: Run the coalescer suite**

Run: `swift test --filter IconRenderCoalescerTests`
Expected: PASS, six tests.

- [ ] **Step 3: Prove each new assertion has teeth**

Temporarily delete `self.pendingRender = nil` from `cancel()` (`IconRenderCoalescer.swift:85-89`).

Run: `swift test --filter IconRenderCoalescerTests/testCancelDropsThePendingRedraw`
Expected: FAIL with `XCTAssertEqual failed: (["prime", "pending"]) is not equal to (["prime"])`. Restore the line.

Temporarily delete `pendingTask?.cancel()` from `cancel()`.

Run: `swift test --filter IconRenderCoalescerTests/testCancelCancelsTheScheduledTrailingRedraw`
Expected: FAIL: `probe.cancelledCount` never reaches 1. Restore the line; `Sources/StatusTrioCore/UI/Icon/IconRenderCoalescer.swift` must be byte-identical to `HEAD` before the commit, because no task in this plan owns that file.

- [ ] **Step 4: Commit**

```bash
git add Tests/StatusTrioCoreTests/IconRenderCoalescerTests.swift
git commit -m "test(coalescer): prove cancel() had something to cancel

testCancelDropsThePendingRedraw passed even when no trailing redraw had been
scheduled. It now waits for the scheduled sleep first, asserts the next submit
is not deferred after cancel, and a second test pins the real Task.sleep
cancellation path that the manual sleeper cannot observe."
```

---

### Task 5: Full Verification, Preflight And CI Record

**Files:**
- Modify: `docs/swift-ci-compatibility.md` (only if the preflight fails)

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: acceptance evidence on the CI toolchain, mandatory here because Task 3 changes `deinit` and `@MainActor` teardown.

- [ ] **Step 1: Run the full suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 2: Run the release build and check the warning count**

Run: `swift build -c release 2>&1 | grep -c "warning:"`
Expected: `4` or fewer — the baseline the review recorded for R-20. A new `weak var` warning means a lifetime assertion used a local `weak var` instead of `WeakBox`; fix it there rather than adding a fifth warning.

- [ ] **Step 3: Confirm the new tests are the only production change**

Run: `git diff --stat main -- Sources/`
Expected: only `Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift` with the `nonisolated(unsafe)` storage, the shared `tearDownRegistrations()` helper and the `deinit` hunk. Any other production file in this diff is out of scope for this plan (Task 2's mutation checks must have been reverted; `IconRenderCoalescer.swift`, `BatteryIconOptions.swift` and `DockIconRenderer.swift` must be untouched).

- [ ] **Step 4: Run the non-publishing preflight**

```bash
git push -u origin test/icon-parity-lifecycle

gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref test/icon-parity-lifecycle \
  -f version=1.3.0 \
  -f build=15 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

`build=15` keeps the build number above the published appcast (9) and above the `build=13` and `build=14` used by this plan's sibling plans. Expected: all stages pass, nothing is published.

- [ ] **Step 5: Record the run**

If the preflight fails, append a row to the failure table in `docs/swift-ci-compatibility.md` in the format required by its "失败记录规则" section (lines 44-54). If it passes, append a short subsection with the run ID, the test counts, and the fact that the only production change is the `SystemIconAppearanceMonitor` teardown — `deinit` plus `nonisolated(unsafe)` teardown-owned storage is exactly the class of change the preflight exists for.

- [ ] **Step 6: Commit the record**

```bash
git add docs/swift-ci-compatibility.md
git commit -m "docs: record the icon parity and lifecycle preflight

Non-publishing preflight on test/icon-parity-lifecycle: the parity matrix,
the lifetime suites and the full test run pass on macos-26 / Xcode 26.6 /
Swift 6.3.3, with the new appearance-monitor teardown compiled there."
```

---

## Verification

- `swift test` and `swift build -c release` pass; `swift build -c release 2>&1 | grep -c "warning:"` stays at or below 4.
- `swift test --filter IconOptionParityMatrixTests` passes, and Step 3 of Task 1 records the exact failure produced by adding a field to `BatteryIconOptions`.
- `swift test --filter IconSurfaceLifetimeTests` passes, and Step 3 of Task 2 records the exact failure the appearance monitor produced before Task 3.
- `swift test --filter IconRenderCoalescerTests` passes, and Step 3 of Task 4 records the exact failure produced by removing `pendingRender = nil` and by removing `pendingTask?.cancel()`.
- `git diff --stat main -- Sources/` shows only the `SystemIconAppearanceMonitor.swift` teardown change, and `grep -n "assumeIsolated" Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift` finds nothing.
- The non-publishing preflight on `test/icon-parity-lifecycle` passes and `docs/swift-ci-compatibility.md` records the run ID and outcome.

## Out of Scope

- Snapshot or golden-file comparisons of rendered icons: every assertion compares two images produced in the same process.
- Rewriting `DockIconRenderCacheTests.swift` or `Issue13IconParityTests.swift`. The review index lists them under this finding, but the new matrix file covers the missing assertions without churning them; do not duplicate the enum coverage in three places.
- `UI/Icon/DockIconRenderer.swift`. It belongs to R-04 (`2026-09-20-icon-preview-rendering.md`), which lands first; this plan may only change production code when a new test proves a real bug, and Task 1 Step 2 tells the worker to escalate rather than patch if a parity gap appears.
- The Bluetooth teardown fix itself: that is R-01's (`2026-09-20-bluetooth-polling-and-lifetime.md`). This plan pins it.
- A timer-factory seam in `SystemIconAppearanceMonitor`. The file belongs to R-05, and the transitive argument in Task 3 Step 4 is recorded instead of a seam nobody asked for.
- Adding `@Suite(.serialized)` or any other parallel-execution control: the new tests use per-test fixtures and counting centers, so they do not depend on execution order.
- Release notes: no user-visible change.

## File Ownership & Conflicts

Owned by this plan:

| File | Change |
| --- | --- |
| `Tests/StatusTrioCoreTests/IconOptionParityMatrixTests.swift` | new |
| `Tests/StatusTrioCoreTests/TestSupport/CountingNotificationCenter.swift` | new |
| `Tests/StatusTrioCoreTests/IconSurfaceLifetimeTests.swift` | new |
| `Tests/StatusTrioCoreTests/IconRenderCoalescerTests.swift` | two tests strengthened |
| `Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift` | teardown-owned `nonisolated(unsafe)` storage, shared `tearDownRegistrations()`, plain `deinit` (Task 3 only) |
| `docs/swift-ci-compatibility.md` | one record entry |

Conflicts and sequencing:

- `Sources/StatusTrioCore/App/SystemIconAppearanceMonitor.swift` is owned by R-05 (`2026-09-20-appearance-poll-tolerance.md`), and `Tests/StatusTrioCoreTests/SystemIconAppearanceMonitorTests.swift` is shared between R-05 and R-16. Wave order: R-16 (wave 2) → R-05 (wave 2) → this plan (wave 3). Rebase Task 3 onto R-05's timer change: the storage declarations and `tearDownRegistrations()` do not depend on the interval or the tolerance, but they must keep R-05's timer construction inside `tearDownRegistrations()`'s invalidation. R-05's own conflict section describes this plan's teardown as "a `deinit` that forwards to `stop()`"; the final design shares `tearDownRegistrations()` between `stop()` and `deinit` instead, because `deinit` may run off the main actor and `MainActor.assumeIsolated` there would trap. The ordering requirement (R-05 first) and the idempotence argument are unchanged.
- `Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift` and `Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift` are owned by R-04 (`2026-09-20-icon-preview-rendering.md`), which lands first and adds a defaulted `pixelLength` parameter to both. This plan calls `DockIconRenderer.image(status:options:connectionOptions:volumeOptions:bluetoothAudioOptions:backgroundStyle:)` and `DockIconRenderKey(status:options:connectionOptions:volumeOptions:bluetoothAudioOptions:backgroundStyle:)` without it, which keeps compiling because the parameter is defaulted; the Dock-side default is `DockIconRenderer.pixelSize`. Rebase Task 1 on R-04 and, if the default ever becomes required, pass `DockIconRenderer.pixelSize` explicitly rather than copying a literal.
- `Tests/StatusTrioCoreTests/DockIconRenderCacheTests.swift` and `Tests/StatusTrioCoreTests/Issue13IconParityTests.swift` are listed under R-19 in the review index but are deliberately not modified here: the matrix file covers the missing assertions, and R-04 runs `DockIconRenderCacheTests` unmodified as its own regression proof.
- `Sources/StatusTrioCore/App/AppIconController.swift` is owned by R-16 (`2026-09-20-fixed-sleep-test-hardening.md`), which lands before this plan and adds an injectable `snapshotDebounceInterval`. This plan does not modify that file; if a lifetime seam there turns out to be necessary, take it up with that plan rather than editing it here.
- `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift` is shared by R-14 and R-16. This plan does not touch it, but it does define a `LifetimeBatteryMonitor` fake in its own new file — keep the type names distinct from the private fakes in the other suites (`FakeBatteryMonitor`, `EmptyBatteryMonitor`, `ControllableBatteryMonitor`) to avoid confusion during review.
- `Sources/StatusTrioCore/Monitoring/BluetoothDeviceController.swift` is owned by R-01. This plan must not edit it; `bluetoothControllerRemovesObserversWhenDeallocatedWhileActive` asserts the behavior R-01 promises, so R-01 must be merged before this plan is verified. If it fails after R-01 lands, report the gap against R-01.
- `Sources/StatusTrioCore/Store/SystemStatusStore.swift` and `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift` are owned by R-01/R-03. This plan adds its store lifetime assertion in a new file with its own fakes rather than editing that suite.
- `Tests/StatusTrioCoreTests/TestSupport/` currently holds view and pixel helpers only. Adding `CountingNotificationCenter.swift` there is new-file work; if another plan adds a shared notification spy in the same directory, keep one implementation — `SpyWakeNotificationCenter` at `SystemStatusStoreTests.swift:1121` is the duplicate to delete later, not a third copy to add.
- `docs/swift-ci-compatibility.md` is written by every plan whose preflight fails. Append subsections; never renumber the existing failure table.
- Wave order from the review index: this plan is wave 3 and lands after R-04 (icon preview rendering) and R-01 (Bluetooth lifetime). Do not start it earlier, because Tasks 1 and 2 assume both.
